"""Metadata and Git helpers for the OpenCode image release workflow."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

SEMVER = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\Z")
DIGEST = re.compile(r"sha256:[0-9a-f]{64}\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")
REPOSITORY = re.compile(r"[a-z0-9][a-z0-9.-]*(?::[0-9]+)?(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)+\Z")
IMAGE = re.compile(r"[a-z0-9]+(?:[._-][a-z0-9]+)*\Z")


def read_semver(path: Path) -> str:
    version = path.read_text(encoding="utf-8").strip()
    if not SEMVER.fullmatch(version):
        raise ValueError(f"Invalid semantic version in {path}: {version!r}")
    return version


def next_version(version: str) -> str:
    if not SEMVER.fullmatch(version):
        raise ValueError(f"Invalid semantic version: {version!r}")
    major, minor, patch = version.split(".")
    return f"{major}.{minor}.{int(patch) + 1}"


def image_reference(repository: str, image: str, digest: str) -> str:
    if not REPOSITORY.fullmatch(repository) or not IMAGE.fullmatch(image) or not DIGEST.fullmatch(digest):
        raise ValueError("Invalid registry repository, image name, or sha256 manifest digest")
    return f"{repository}/{image}@{digest}"


def read_digest(path: Path, repository: str = "", image: str = "opencode") -> str:
    reference = path.read_text(encoding="utf-8").strip() if path.exists() else ""
    if "@" not in reference:
        raise ValueError(f"Missing or invalid image reference in {path}; run make push-opencode first")
    name, digest = reference.rsplit("@", 1)
    suffix = f"/{image}"
    if not name.endswith(suffix) or image_reference(name[: -len(suffix)], image, digest) != reference:
        raise ValueError(f"Invalid image reference in {path}; run make push-opencode first")
    if repository and name != f"{repository}/{image}":
        raise ValueError(f"Image reference in {path} belongs to {name}, not {repository}/{image}")
    return reference


def atomic_write(path: Path, value: str) -> None:
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
        try:
            handle.write(value + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def write_digest(path: Path, digest: str, repository: str, image: str = "opencode") -> None:
    atomic_write(path, image_reference(repository, image, digest.strip()))


def pending_sources(
    repo: str, baseline: str, tip: str, github_env: dict[str, str] | None = None
) -> list[str]:
    """Return associated squash merges in first-parent order; ignore direct pushes."""
    if not SHA.fullmatch(baseline) or not SHA.fullmatch(tip):
        raise ValueError("Invalid publication cursor or main SHA")
    clean_env = {key: value for key, value in (github_env or os.environ).items() if key != "GH_TOKEN"}
    subprocess.run(["git", "merge-base", "--is-ancestor", baseline, tip], check=True, env=clean_env)
    commits = subprocess.check_output(
        ["git", "rev-list", "--first-parent", "--reverse", f"{baseline}..{tip}"],
        text=True,
        env=clean_env,
    ).splitlines()
    sources: list[str] = []
    api_env = github_env or os.environ
    for commit in commits:
        if not SHA.fullmatch(commit):
            raise ValueError(f"Invalid commit SHA: {commit!r}")
        response = subprocess.check_output(
            ["gh", "api", f"repos/{repo}/commits/{commit}/pulls", "--paginate", "--slurp"],
            text=True,
            env=api_env,
        )
        pages = json.loads(response)
        if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
            raise ValueError(f"Incomplete PR association for commit {commit}")
        pulls = [pull for page in pages for pull in page]
        if any(
            pull.get("merged_at")
            and pull.get("base", {}).get("ref") == "main"
            and pull.get("merge_commit_sha") == commit
            for pull in pulls
        ):
            sources.append(commit)
    return sources


def record_push(path: Path, digest_file: Path, repository: str, image: str) -> None:
    write_digest(path, digest_file.read_text(encoding="utf-8"), repository, image)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("next-version").add_argument("path", type=Path)
    read = subcommands.add_parser("read-digest")
    read.add_argument("path", type=Path)
    read.add_argument("--repository", default="")
    read.add_argument("--image", default="opencode")
    push = subcommands.add_parser("record-push")
    push.add_argument("path", type=Path)
    push.add_argument("digestfile", type=Path)
    push.add_argument("repository")
    push.add_argument("image")
    pending = subcommands.add_parser("pending")
    pending.add_argument("repo")
    pending.add_argument("baseline")
    pending.add_argument("tip")
    args = parser.parse_args()
    try:
        if args.command == "next-version":
            print(next_version(read_semver(args.path)))
        elif args.command == "read-digest":
            print(read_digest(args.path, args.repository, args.image))
        elif args.command == "record-push":
            record_push(args.path, args.digestfile, args.repository, args.image)
        else:
            print("\n".join(pending_sources(args.repo, args.baseline, args.tip)))
    except (ValueError, OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
