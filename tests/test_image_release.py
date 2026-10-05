"""Tests for image release metadata and candidate promotion contracts."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))


def make_default(name: str) -> str:
    makefile = (ROOT / "Makefile").read_text()
    match = re.search(rf"^{re.escape(name)}\s*\?=\s*(\S+)", makefile, re.MULTILINE)
    assert match, f"{name} is not pinned in the Makefile"
    return match.group(1)


def load_script(name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"scripts/{name}.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


release = load_script("image_release")
publisher = load_script("publish_image")
container_e2e = load_script("e2e_container")
kind_e2e = load_script("e2e_kind_pod")

DIGEST = "sha256:" + "a" * 64
IMAGE_REF = f"quay.io/example/opencode@{DIGEST}"
BASELINE = "1" * 40
SOURCE_1 = "2" * 40
SOURCE_2 = "3" * 40


@pytest.mark.parametrize(("current", "expected"), [("0.5.2", "0.5.3"), ("1.9.9", "1.9.10")])
def test_next_version(current, expected):
    assert release.next_version(current) == expected


@pytest.mark.parametrize("invalid", ["", "1.2", "01.2.3", "1.2.3-rc1", "1.2.3\nnext"])
def test_invalid_semver_is_rejected(invalid):
    with pytest.raises(ValueError):
        release.next_version(invalid)


def test_digest_validation_and_registry_ownership(tmp_path):
    path = tmp_path / "IMAGE_DIGEST"
    release.write_digest(path, DIGEST, "quay.io/example")
    assert release.read_digest(path, "quay.io/example") == IMAGE_REF
    with pytest.raises(ValueError, match="belongs to"):
        release.read_digest(path, "quay.io/other")
    with pytest.raises(ValueError):
        release.write_digest(path, "sha256:bad", "quay.io/example")
    assert path.read_text().strip() == IMAGE_REF


def test_pending_merges_uses_pr_association_and_preserves_first_parent_order(monkeypatch):
    publisher_commit = "4" * 40

    def fake_run(*_args, **_kwargs):
        return None

    def fake_output(command, text, env):
        if command[1] == "rev-list":
            return "\n".join([SOURCE_1, publisher_commit, SOURCE_2]) + "\n"
        if command[0] == "gh":
            commit = command[2].split("/")[-2]
            if commit == publisher_commit:
                return "[[]]"
            return f'[[{{"merged_at":"now","base":{{"ref":"main"}},"merge_commit_sha":"{commit}"}}]]'
        raise AssertionError(command)

    monkeypatch.setattr(release.subprocess, "run", fake_run)
    monkeypatch.setattr(release.subprocess, "check_output", fake_output)
    assert release.pending_sources("example/repo", BASELINE, SOURCE_2, {"GH_TOKEN": "secret"}) == [
        SOURCE_1, SOURCE_2,
    ]


def test_make_build_and_push_allow_ci_registry_tag_and_digest_capture():
    build = subprocess.check_output(
        ["make", "-n", "build-opencode", "REGISTRY=quay.io/example", "IMAGE_TAG=0.5.3", "NOPROMPT=1", "SAVE_DEFAULTS=0"],
        cwd=ROOT,
        text=True,
    )
    push = subprocess.check_output(
        ["make", "-n", "push-opencode", "REGISTRY=quay.io/example", "IMAGE_TAG=0.5.3", "PUSH_LATEST=0", "PUSH_DIGEST_FILE=IMAGE_DIGEST"],
        cwd=ROOT,
        text=True,
    )
    assert 'REGISTRY="quay.io/example"' in build
    assert 'IMAGE_TAG="0.5.3"' in build
    assert 'SAVE_DEFAULTS="0"' in build
    mcp_revision = make_default("AGENT_SWARM_MCP_REVISION")
    assert re.fullmatch(r"[0-9a-f]{40}", mcp_revision)
    assert f"AGENT_SWARM_MCP_REVISION={mcp_revision}" in build
    assert 'PUSH_LATEST="0"' in push
    assert 'PUSH_DIGEST_FILE="IMAGE_DIGEST"' in push
    assert subprocess.check_output(["make", "-s", "lint-version"], cwd=ROOT, text=True).strip() == make_default("RUFF_VERSION")
    makefile = (ROOT / "Makefile").read_text()
    assert "commits?path=mcp-server&per_page=1" in makefile
    assert "LATEST_RUFF := $(shell curl -fsSL 'https://pypi.org/pypi/ruff/json'" in makefile


def _fake_container_tool(tmp_path):
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    tool = fake_bin / "podman"
    tool.write_text(
        "#!/bin/sh\n"
        'printf "%s\\n" "$*" >> "$PODMAN_CALLS"\n'
        'if [ "$1" = push ] && [ "$2" = --digestfile ]; then\n'
        '  [ -z "$FAIL_PUSH" ] || exit 1\n'
        '  printf "sha256:%064d\\n" 0 > "$3"\n'
        'fi\n'
    )
    tool.chmod(0o755)
    return fake_bin


def test_build_uses_explicit_ci_values_without_writing_local_defaults(tmp_path):
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    shutil.copy(ROOT / "scripts/build.sh", scripts / "build.sh")
    shutil.copy(ROOT / "Makefile", tmp_path / "Makefile")
    (tmp_path / "containerfiles").mkdir()
    (tmp_path / "containerfiles/Containerfile.agents").write_text("# fixture\n")
    source = tmp_path / "agent-swarm/mcp-server"
    source.mkdir(parents=True)
    (source / "pyproject.toml").write_text('[project]\nname = "fixture"\n')
    subprocess.run(["git", "init", "-q", str(source.parent)], check=True)
    subprocess.run(["git", "-C", str(source.parent), "config", "user.name", "test"], check=True)
    subprocess.run(["git", "-C", str(source.parent), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(source.parent), "add", "mcp-server/pyproject.toml"], check=True)
    subprocess.run(["git", "-C", str(source.parent), "commit", "-qm", "fixture"], check=True)
    defaults = tmp_path / ".push-defaults"
    defaults.write_text("REGISTRY=quay.io/local\nIMAGE_TAG=local-tag\n")
    calls = tmp_path / "podman-calls"
    env = {
        **os.environ,
        "PATH": f"{_fake_container_tool(tmp_path)}:{os.environ['PATH']}",
        "PODMAN_CALLS": str(calls),
    }
    result = subprocess.run(
        ["bash", "scripts/build.sh", "opencode", "containerfiles/Containerfile.agents"],
        cwd=tmp_path,
        env={
            **env,
            "NOPROMPT": "1",
            "REGISTRY": "quay.io/example",
            "IMAGE_TAG": "0.5.3",
            "SAVE_DEFAULTS": "0",
            "AGENT_SWARM_MCP_SOURCE": str(source),
        },
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    podman_calls = calls.read_text()
    assert "quay.io/example/opencode:0.5.3" in podman_calls
    assert f"AGENT_SWARM_MCP_REVISION={make_default('AGENT_SWARM_MCP_REVISION')}" in podman_calls
    assert defaults.read_text() == "REGISTRY=quay.io/local\nIMAGE_TAG=local-tag\n"
    assert (tmp_path / ".build-context/agent-swarm-mcp/pyproject.toml").exists()


def test_push_captures_digest_and_does_not_promote_candidate_by_default_when_disabled(tmp_path):
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    shutil.copy(ROOT / "scripts/push.sh", scripts / "push.sh")
    shutil.copy(ROOT / "scripts/image_release.py", scripts / "image_release.py")
    (tmp_path / "IMAGE_DIGEST").write_text("quay.io/example/opencode@sha256:" + "b" * 64 + "\n")
    calls = tmp_path / "podman-calls"
    env = {
        **os.environ,
        "PATH": f"{_fake_container_tool(tmp_path)}:{os.environ['PATH']}",
        "PODMAN_CALLS": str(calls),
    }
    command = ["bash", "scripts/push.sh", "opencode"]
    result = subprocess.run(
        command,
        cwd=tmp_path,
        env={**env, "REGISTRY": "quay.io/example", "IMAGE_TAG": "0.5.3", "PUSH_LATEST": "0", "PUSH_DIGEST_FILE": "IMAGE_DIGEST"},
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert release.read_digest(tmp_path / "IMAGE_DIGEST") == "quay.io/example/opencode@sha256:" + "0" * 64
    push_call = calls.read_text().strip()
    assert push_call.startswith("push --digestfile ")
    assert push_call.endswith("quay.io/example/opencode:0.5.3")

    previous_digest = release.read_digest(tmp_path / "IMAGE_DIGEST")
    failed = subprocess.run(
        command,
        cwd=tmp_path,
        env={**env, "REGISTRY": "quay.io/example", "IMAGE_TAG": "0.5.4", "PUSH_LATEST": "0", "PUSH_DIGEST_FILE": "IMAGE_DIGEST", "FAIL_PUSH": "1"},
        capture_output=True,
        text=True,
    )
    assert failed.returncode != 0
    assert release.read_digest(tmp_path / "IMAGE_DIGEST") == previous_digest


def _release_environment(monkeypatch, output_path):
    for key, value in {
        "GITHUB_REPOSITORY": "example/agent-containers",
        "GITHUB_ACTOR": "release-bot",
        "QUAY_REPOSITORY_PATH": "quay.io/example",
        "QUAY_ROBOT_USERNAME": "robot",
        "QUAY_PUSH_TOKEN": "quay-secret",
        "GH_TOKEN": "github-secret",
        "GITHUB_OUTPUT": str(output_path),
    }.items():
        monkeypatch.setenv(key, value)


def test_publish_prepares_each_candidate_in_order_without_passing_secrets_to_build(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "VERSION").write_text("0.5.2\n")
    (tmp_path / "IMAGE_DIGEST").write_text("\n")
    (tmp_path / "IMAGE_PUBLISH_STATE").write_text(BASELINE + "\n")
    output_path = tmp_path / "github-output"
    _release_environment(monkeypatch, output_path)
    monkeypatch.setattr(publisher, "pending_sources", lambda *_args: [SOURCE_1, SOURCE_2])
    monkeypatch.setattr(publisher, "output", lambda *_args, **_kwargs: BASELINE)
    calls = []

    def fake_run(*command, **kwargs):
        calls.append((command, kwargs))
        if command[:2] == ("make", "push-opencode"):
            release.write_digest(Path("IMAGE_DIGEST"), DIGEST, "quay.io/example")
        elif command[:2] == ("git", "restore"):
            Path("IMAGE_DIGEST").write_text("\n")

    monkeypatch.setattr(publisher, "run", fake_run)
    publisher.publish_candidates()

    build_calls = [(command, kwargs) for command, kwargs in calls if command[:2] == ("make", "build-opencode")]
    assert [next(arg for arg in cmd if arg.startswith("IMAGE_TAG=")) for cmd, _ in build_calls] == [
        "IMAGE_TAG=0.5.3", "IMAGE_TAG=0.5.4",
    ]
    for _, kwargs in build_calls:
        assert "GH_TOKEN" not in kwargs["env"]
        assert "QUAY_PUSH_TOKEN" not in kwargs["env"]
    assert (tmp_path / "VERSION").read_text() == "0.5.4\n"
    assert (tmp_path / "IMAGE_PUBLISH_STATE").read_text() == SOURCE_2 + "\n"
    assert output_path.read_text().count(IMAGE_REF) == 2


def test_failed_candidate_build_does_not_report_a_publish_or_advance_the_cursor(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "VERSION").write_text("0.5.2\n")
    (tmp_path / "IMAGE_DIGEST").write_text("\n")
    (tmp_path / "IMAGE_PUBLISH_STATE").write_text(BASELINE + "\n")
    output_path = tmp_path / "github-output"
    _release_environment(monkeypatch, output_path)
    monkeypatch.setattr(publisher, "pending_sources", lambda *_args: [SOURCE_1])
    monkeypatch.setattr(publisher, "output", lambda *_args, **_kwargs: BASELINE)

    def fail_build(*command, **_kwargs):
        if command[:2] == ("make", "build-opencode"):
            raise subprocess.CalledProcessError(1, command)

    monkeypatch.setattr(publisher, "run", fail_build)
    with pytest.raises(subprocess.CalledProcessError):
        publisher.publish_candidates()
    assert (tmp_path / "VERSION").read_text() == "0.5.2\n"
    assert (tmp_path / "IMAGE_PUBLISH_STATE").read_text() == BASELINE + "\n"
    assert not output_path.exists()


def test_promotion_failure_does_not_push_release_cursor(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "VERSION").write_text("0.5.3\n")
    (tmp_path / "IMAGE_DIGEST").write_text(IMAGE_REF + "\n")
    _release_environment(monkeypatch, tmp_path / "github-output")
    monkeypatch.setattr(publisher, "output", lambda *args, **_kwargs: "image-publisher" if args[1:3] == ("branch", "--show-current") else "1")
    calls = []

    def fake_run(*command, **kwargs):
        calls.append(command)
        if command[:2] == ("make", "push-opencode"):
            raise subprocess.CalledProcessError(1, command)

    monkeypatch.setattr(publisher, "run", fake_run)
    with pytest.raises(subprocess.CalledProcessError):
        publisher.promote_and_push()
    assert not any(command[:2] == ("git", "push") for command in calls)


def test_promote_requires_latest_digest_parity_before_metadata_push(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "VERSION").write_text("0.5.3\n")
    (tmp_path / "IMAGE_DIGEST").write_text(IMAGE_REF + "\n")
    _release_environment(monkeypatch, tmp_path / "github-output")
    monkeypatch.setattr(
        publisher,
        "output",
        lambda *args, **_kwargs: "image-publisher" if args[1:3] == ("branch", "--show-current") else "1",
    )
    calls = []

    def fake_run(*command, **kwargs):
        calls.append(command)
        if command[:2] == ("make", "push-opencode"):
            release.write_digest(Path("IMAGE_DIGEST"), DIGEST, "quay.io/example")

    monkeypatch.setattr(publisher, "run", fake_run)
    publisher.promote_and_push()
    assert next(i for i, c in enumerate(calls) if c[:2] == ("make", "push-opencode")) < next(
        i for i, c in enumerate(calls) if c[:2] == ("git", "push")
    )


def test_both_e2e_helpers_require_digest_refs_and_kind_runs_non_root_security_context():
    assert container_e2e.validate_image_ref(IMAGE_REF) == IMAGE_REF
    with pytest.raises(ValueError):
        container_e2e.validate_image_ref("quay.io/example/opencode:0.5.3")
    manifest = json.loads(kind_e2e.pod_manifest(IMAGE_REF))
    container = manifest["spec"]["containers"][0]
    assert container["securityContext"]["runAsUser"] == 1000
    assert container["securityContext"]["runAsNonRoot"] is True
    assert container["imagePullPolicy"] == "Always"
    assert 'test "$HOME" = /home/node' in container["command"][2]
    assert container["image"] == IMAGE_REF


def test_workflow_gates_promotion_on_both_e2e_stages():
    workflow = (ROOT / ".github/workflows/publish-image.yml").read_text()
    sca = workflow.index("Run SCA audit for every candidate digest")
    standalone = workflow.index("Run standalone container E2E for every candidate")
    kind = workflow.index("Run KinD Pod E2E for every candidate")
    sign = workflow.index("Sign each tested candidate digest with GitHub OIDC")
    promote = workflow.index("Promote tested candidate and publish release metadata")
    assert sca < standalone < kind < sign < promote
    assert workflow.count("steps.publish.outputs.published == 'true'") == 7
    assert "cancel-in-progress: false" in workflow
    assert "pull_request:" not in workflow
    assert "id-token: write" in workflow
    assert "50030de23cf40a18505f20426f6a8506bedf13c6e509244bd1fa9463721b0f54" in workflow
    assert ".sha256sum" not in workflow
    assert "sigstore/cosign-installer@6f9f17788090df1f26f669e9d70d6ae9567deba6" in workflow
    assert "pip-audit --local" in workflow


def test_pr_workflow_tests_every_pr_but_builds_images_only_for_trusted_prs():
    workflow = (ROOT / ".github/workflows/test.yml").read_text()
    assert "pull_request:" in workflow
    assert "python -m pytest -q" in workflow
    assert "github.event.pull_request.head.repo.full_name == github.repository" in workflow
    assert "make build-opencode REGISTRY=localhost" in workflow
    assert "SAVE_DEFAULTS=0" in workflow
    assert "Audit built image dependencies" in workflow
    assert "podman push" not in workflow
    lint = (ROOT / ".github/workflows/lint.yml").read_text()
    assert "pull_request:" in lint
    assert "make lint" in lint
    assert "make --no-print-directory -s lint-version" in lint

    security = (ROOT / ".github/workflows/security.yml").read_text()
    assert "pull_request:" in security and "push:" in security
    assert "github/codeql-action/init@1190a975f95ce23525efb6a3fc21ea29567c1b52" in security
    assert "actions/dependency-review-action@a1d282b36b6f3519aa1f3fc636f609c47dddb294" in security
    assert "github.event.pull_request.head.repo.full_name == github.repository" in security
