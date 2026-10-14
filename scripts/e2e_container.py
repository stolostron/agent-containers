"""Run standalone runtime and OpenCode health checks against an image digest."""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import secrets
import shlex
import shutil
import socket
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from image_release import DIGEST, REPOSITORY

_SECRET_NAME = re.compile(r"(?i)(?:PASSWORD|PASSWD|TOKEN|SECRET|CREDENTIAL|API[-_]?KEY|AUTH)")
_SECRET_ASSIGNMENT = re.compile(
    r"(?i)([A-Z0-9_]*(?:PASSWORD|PASSWD|TOKEN|SECRET|CREDENTIAL|API[-_]?KEY|AUTH)[A-Z0-9_]*=).*",
    re.DOTALL,
)


def redact_text(text: str, sensitive_values: tuple[str, ...] = ()) -> str:
    """Remove known secrets and all text following a secret assignment."""
    for secret in sensitive_values:
        if secret:
            text = text.replace(secret, "<redacted>")
    return _SECRET_ASSIGNMENT.sub(r"\1<redacted>", text)


def redact_command(command: list[str], sensitive_values: tuple[str, ...] = ()) -> str:
    """Render a command with secret-valued options and assignments hidden."""
    redacted: list[str] = []
    redact_next = False
    for argument in command:
        if redact_next:
            redacted.append("<redacted>")
            redact_next = False
            continue
        argument = redact_text(argument, sensitive_values)
        if argument.startswith("-") and _SECRET_NAME.search(argument) and "=" not in argument:
            redacted.append(argument)
            redact_next = True
        else:
            redacted.append(argument)
    return shlex.join(redacted)


def generate_server_password() -> str:
    """Generate an unpredictable password for this one E2E container run."""
    return secrets.token_urlsafe(32)


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


def run(
    command: list[str],
    *,
    check: bool = True,
    capture: bool = False,
    sensitive_values: tuple[str, ...] = (),
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    safe_command = redact_command(command, sensitive_values)
    print("$ " + safe_command)
    result = subprocess.run(command, text=True, capture_output=capture, check=False, env=env)
    if check and result.returncode:
        # Command output can include container diagnostics or credentials; keep
        # it out of normal E2E failure output rather than forwarding raw logs.
        raise RuntimeError(f"command failed ({result.returncode}): {safe_command}")
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


def wait_for_health(url: str, timeout: int, password: str) -> None:
    """Poll the OpenCode V2 /api/info endpoint with Basic auth until healthy."""
    auth = base64.b64encode(f"opencode:{password}".encode()).decode()
    deadline = time.monotonic() + timeout
    last_error = "OpenCode health endpoint did not respond"
    while time.monotonic() < deadline:
        try:
            request = Request(url, headers={"Authorization": f"Basic {auth}"})
            with urlopen(request, timeout=3) as response:
                if response.status != 200:
                    last_error = f"health endpoint returned HTTP {response.status}"
                else:
                    payload = json.loads(response.read())
                    if payload.get("version"):
                        print(f"[PASS] OpenCode V2 API info endpoint: {url} (version {payload['version']})")
                        return
                    last_error = "unexpected response from OpenCode V2 API info endpoint"
        except (OSError, URLError, json.JSONDecodeError) as exc:
            last_error = str(exc)
        time.sleep(2)
    raise RuntimeError(last_error)


def verify_unauthenticated_rejected(url: str) -> None:
    """Assert /api/info rejects requests without credentials (HTTP 401)."""
    request = Request(url)
    try:
        with urlopen(request, timeout=3) as response:
            status = response.status
    except HTTPError as error:
        status = error.code
    if status != 401:
        raise RuntimeError(f"unauthenticated /api/info request was not rejected (HTTP {status})")
    print(f"[PASS] OpenCode V2 API info endpoint rejects unauthenticated requests: {url}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image-ref", required=True)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--container-command", default="podman")
    args = parser.parse_args()
    container_name = f"opencode-release-e2e-{int(time.time())}"
    server_password = ""
    try:
        image_ref = validate_image_ref(args.image_ref)
        if shutil.which(args.container_command) is None:
            raise RuntimeError(f"missing required command: {args.container_command}")
        verify_runtime(args.container_command, image_ref)
        print("[PASS] non-root user, permissions, pinned tools, and MCP startup")

        port = unused_port()
        # OpenCode V2 requires server auth; use a unique secret for this run.
        server_password = generate_server_password()
        run([
            args.container_command, "run", "--detach", "--pull=always", "--name", container_name,
            "-p", f"127.0.0.1:{port}:4096",
            "-e", "OPENCODE_PASSWORD",
            image_ref,
            "opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096",
        ], sensitive_values=(server_password,), env={**os.environ, "OPENCODE_PASSWORD": server_password})
        info_url = f"http://127.0.0.1:{port}/api/info"
        wait_for_health(info_url, args.timeout, server_password)
        verify_unauthenticated_rejected(info_url)
    except (ValueError, RuntimeError, subprocess.SubprocessError, OSError) as exc:
        sensitive_values = (server_password,)
        if server_password:
            sensitive_values += (base64.b64encode(f"opencode:{server_password}".encode()).decode(),)
        print(f"[FAIL] standalone image E2E: {redact_text(str(exc), sensitive_values)}", file=sys.stderr)
        if shutil.which(args.container_command) and container_name:
            print("[INFO] container logs suppressed to prevent credential disclosure", file=sys.stderr)
        return 1
    finally:
        if shutil.which(args.container_command):
            run([args.container_command, "rm", "--force", container_name], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
