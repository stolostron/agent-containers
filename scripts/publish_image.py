"""Build image candidates for unprocessed squash merges and promote after E2E."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path

from image_release import (
    atomic_write,
    next_version,
    pending_sources,
    read_digest,
    read_semver,
)

SHA = re.compile(r"[0-9a-f]{40}\Z")
REGISTRY = re.compile(r"quay\.io/[a-z0-9]+(?:[._-][a-z0-9]+)*\Z")


def run(*command: str, env: dict[str, str] | None = None, input: str | None = None, text: bool = False) -> None:
    subprocess.run(command, check=True, env=env, input=input, text=text)


def output(*command: str, env: dict[str, str] | None = None) -> str:
    return subprocess.check_output(command, text=True, env=env).strip()


def build_environment() -> dict[str, str]:
    """Allowlist runner settings required by Podman; never inherit credentials."""
    allowed = (
        "PATH", "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "XDG_RUNTIME_DIR",
        "XDG_CONFIG_HOME", "LANG", "LC_ALL", "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY",
        "CONTAINER_CMD",
    )
    return {key: os.environ[key] for key in allowed if key in os.environ}


def github_environment(clean_env: dict[str, str]) -> dict[str, str]:
    return {**clean_env, "GH_TOKEN": os.environ["GH_TOKEN"]}


def git_environment(directory: str, github_env: dict[str, str]) -> dict[str, str]:
    askpass = Path(directory) / "git-askpass"
    askpass.write_text(
        '#!/bin/sh\ncase "$1" in\n'
        '  *sername*) printf "%s\\n" x-access-token ;;\n'
        '  *assword*) printf "%s\\n" "$GH_TOKEN" ;;\n'
        '  *) exit 1 ;;\nesac\n',
        encoding="utf-8",
    )
    askpass.chmod(0o700)
    return {**github_env, "GIT_ASKPASS": str(askpass), "GIT_TERMINAL_PROMPT": "0"}


def validate_registry_credentials() -> tuple[str, str, str]:
    registry = os.environ["QUAY_REPOSITORY_PATH"]
    username = os.environ["QUAY_ROBOT_USERNAME"]
    token = os.environ["QUAY_PUSH_TOKEN"]
    if not REGISTRY.fullmatch(registry) or not username or not token:
        raise ValueError("Valid Quay repository path, robot username and token are required")
    return registry, username, token


def write_github_output(published: bool, references: list[str]) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    with Path(output_path).open("a", encoding="utf-8") as output_file:
        output_file.write(f"published={'true' if published else 'false'}\n")
        if references:
            output_file.write("image_refs<<IMAGE_REFS_EOF\n")
            output_file.write("\n".join(references))
            output_file.write("\nIMAGE_REFS_EOF\n")


def publish_candidates() -> None:
    """Push SemVer candidates and prepare local release metadata for E2E."""
    repo = os.environ["GITHUB_REPOSITORY"]
    clean_env = build_environment()
    github_env = github_environment(clean_env)
    checkout = output("git", "rev-parse", "HEAD", env=clean_env)
    if not SHA.fullmatch(checkout):
        raise ValueError("Invalid checkout commit")

    references: list[str] = []
    with tempfile.TemporaryDirectory() as directory:
        git_env = git_environment(directory, github_env)
        run("git", "fetch", "origin", "main", env=git_env)
        remote_tip = output("git", "rev-parse", "origin/main", env=clean_env)
        baseline = Path("IMAGE_PUBLISH_STATE").read_text(encoding="utf-8").strip()
        sources = pending_sources(repo, baseline, remote_tip, github_env)
        if not sources:
            print("No unprocessed squash merges")
            write_github_output(False, references)
            return
        if not SHA.fullmatch(remote_tip):
            raise ValueError("Invalid origin/main commit")
        registry, username, token = validate_registry_credentials()

        run("git", "switch", "-C", "image-publisher", remote_tip, env=clean_env)
        authfile = str(Path(directory) / "quay-auth.json")
        push_env = {**clean_env, "REGISTRY_AUTH_FILE": authfile}
        run(
            "podman", "login", "--authfile", authfile, "--username", username,
            "--password-stdin", "quay.io", input=token, text=True, env=push_env,
        )

        print(f"Found {len(sources)} unprocessed squash merge(s)")
        for index, source in enumerate(sources, start=1):
            version = next_version(read_semver(Path("VERSION")))
            run("git", "switch", "--detach", source, env=clean_env)
            print(f"::group::Candidate {index}/{len(sources)} — opencode:{version} ({source})")
            try:
                args = (
                    f"REGISTRY={registry}", f"IMAGE_TAG={version}", "NOPROMPT=1",
                    "SAVE_DEFAULTS=0", "PUSH_LATEST=0", "PUSH_DIGEST_FILE=IMAGE_DIGEST",
                )
                print("Build candidate image from the squash merge")
                run("make", "build-opencode", *args, env=clean_env)
                print("Push the SemVer candidate and record its immutable digest")
                run("make", "push-opencode", *args, env=push_env)
                reference = read_digest(Path("IMAGE_DIGEST"), registry)
                references.append(reference)

                run("git", "restore", "IMAGE_DIGEST", env=clean_env)
                run("git", "switch", "image-publisher", env=clean_env)
                atomic_write(Path("VERSION"), version)
                atomic_write(Path("IMAGE_DIGEST"), reference)
                atomic_write(Path("IMAGE_PUBLISH_STATE"), source)
                run("git", "add", "VERSION", "IMAGE_DIGEST", "IMAGE_PUBLISH_STATE", env=clean_env)
                actor = os.environ["GITHUB_ACTOR"]
                run(
                    "git", "-c", f"user.name={actor}",
                    "-c", f"user.email={actor}@users.noreply.github.com",
                    "commit", "-m", f"Publish OpenCode image {version}\n\nImage-Publish-Source-SHA: {source}",
                    env=clean_env,
                )
            finally:
                print("::endgroup::")

    write_github_output(True, references)


def promote_and_push() -> None:
    """Promote the final E2E-tested candidate and publish the cursor metadata."""
    registry, username, token = validate_registry_credentials()
    clean_env = build_environment()
    github_env = github_environment(clean_env)
    version = read_semver(Path("VERSION"))
    candidate_ref = read_digest(Path("IMAGE_DIGEST"), registry)

    with tempfile.TemporaryDirectory() as directory:
        git_env = git_environment(directory, github_env)
        authfile = str(Path(directory) / "quay-auth.json")
        push_env = {**clean_env, "REGISTRY_AUTH_FILE": authfile}
        if output("git", "branch", "--show-current", env=clean_env) != "image-publisher":
            raise ValueError("Prepared release metadata is not checked out on image-publisher")
        run("git", "fetch", "origin", "main", env=git_env)
        run("git", "merge-base", "--is-ancestor", "origin/main", "HEAD", env=clean_env)
        count = output("git", "rev-list", "--count", "origin/main..HEAD", env=clean_env)
        if not count.isdigit() or count == "0":
            raise ValueError("No prepared release metadata commits to push")

        print(f"::group::Promote tested candidate opencode:{version} to latest")
        try:
            run(
                "podman", "login", "--authfile", authfile, "--username", username,
                "--password-stdin", "quay.io", input=token, text=True, env=push_env,
            )
            run(
                "podman", "tag", f"{registry}/opencode:{version}",
                f"{registry}/opencode:latest", env=push_env,
            )
            run(
                "make", "push-opencode", f"REGISTRY={registry}", "IMAGE_TAG=latest",
                "PUSH_LATEST=0", "PUSH_DIGEST_FILE=IMAGE_DIGEST", env=push_env,
            )
            if read_digest(Path("IMAGE_DIGEST"), registry) != candidate_ref:
                raise ValueError("Latest and SemVer pushes produced different registry digests")
        finally:
            print("::endgroup::")

        print("::group::Push release metadata commits to main")
        try:
            run("git", "push", "origin", "HEAD:main", env=git_env)
        finally:
            print("::endgroup::")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", required=True, choices=("publish", "promote-and-push"))
    args = parser.parse_args()
    if args.stage == "publish":
        publish_candidates()
    else:
        promote_and_push()


if __name__ == "__main__":
    main()
