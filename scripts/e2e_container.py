"""Run standalone runtime and OpenCode health checks against an image digest."""

from __future__ import annotations

import argparse
import json
import shutil
import socket
import subprocess
import sys
import time
from urllib.error import URLError
from urllib.request import urlopen

from image_release import DIGEST, REPOSITORY


def validate_image_ref(reference: str) -> str:
    if "@" not in reference:
        raise ValueError("image reference must be pinned to a sha256 manifest digest")
    name, digest = reference.rsplit("@", 1)
    if not DIGEST.fullmatch(digest) or "/" not in name:
        raise ValueError("image reference must be pinned to a sha256 manifest digest")
    repository, image = name.rsplit("/", 1)
    if image != "opencode" or not REPOSITORY.fullmatch(repository):
        raise ValueError("image reference must identify a published OpenCode image")
    return reference


def run(command: list[str], *, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess[str]:
    print("$ " + " ".join(command))
    result = subprocess.run(command, text=True, capture_output=capture, check=False)
    if check and result.returncode:
        details = (result.stdout or "") + (result.stderr or "")
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}\n{details}")
    return result


def verify_runtime(podman: str, image_ref: str) -> None:
    check = r"""
test "$(id -u)" -eq 1000
test "$(id -u node)" -eq 1000
test "$(id -u sandbox)" -ne 0
test "$(stat -c %u /sandbox)" = "$(id -u sandbox)"
test "$HOME" = /home/node
test -w /home/node
test -w /home/node/.config
for tool in opencode node npm git gh go python3 rg fzf yq jira-mcp-server agent-swarm-mcp-server pip-audit govulncheck; do
  command -v "$tool" >/dev/null
done
opencode --version
go version
python3 --version
jira-mcp-server --help >/dev/null
agent-swarm-mcp-server --help >/dev/null
""".strip()
    run([podman, "run", "--rm", "--pull=always", "--entrypoint", "/bin/sh", image_ref, "-ec", check])


def unused_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_for_health(url: str, timeout: int) -> None:
    deadline = time.monotonic() + timeout
    last_error = "OpenCode health endpoint did not respond"
    while time.monotonic() < deadline:
        try:
            with urlopen(url, timeout=3) as response:
                if response.status != 200:
                    last_error = f"health endpoint returned HTTP {response.status}"
                else:
                    payload = json.loads(response.read())
                    if payload.get("healthy") is True:
                        print(f"[PASS] OpenCode health endpoint: {url}")
                        return
                    last_error = f"unexpected health response: {payload!r}"
        except (OSError, URLError, json.JSONDecodeError) as exc:
            last_error = str(exc)
        time.sleep(2)
    raise RuntimeError(last_error)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image-ref", required=True)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--container-command", default="podman")
    args = parser.parse_args()
    container_name = f"opencode-release-e2e-{int(time.time())}"
    try:
        image_ref = validate_image_ref(args.image_ref)
        if shutil.which(args.container_command) is None:
            raise RuntimeError(f"missing required command: {args.container_command}")
        verify_runtime(args.container_command, image_ref)
        print("[PASS] non-root user, permissions, pinned tools, and MCP startup")

        port = unused_port()
        run([
            args.container_command, "run", "--detach", "--pull=always", "--name", container_name,
            "-p", f"127.0.0.1:{port}:4096", image_ref,
            "opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096",
        ])
        wait_for_health(f"http://127.0.0.1:{port}/global/health", args.timeout)
    except (ValueError, RuntimeError, subprocess.SubprocessError, OSError) as exc:
        print(f"[FAIL] standalone image E2E: {exc}", file=sys.stderr)
        if shutil.which(args.container_command) and container_name:
            logs = run([args.container_command, "logs", container_name], check=False, capture=True)
            if logs.stdout:
                print(logs.stdout, file=sys.stderr)
            if logs.stderr:
                print(logs.stderr, file=sys.stderr)
        return 1
    finally:
        if shutil.which(args.container_command):
            run([args.container_command, "rm", "--force", container_name], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
