"""Create a disposable KinD cluster and run the digest-pinned OpenCode image."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys

from e2e_container import validate_image_ref

CLUSTER_NAME = re.compile(r"[a-z0-9](?:[a-z0-9-]{0,36}[a-z0-9])?\Z")
POD = "opencode-release-e2e"


def run(command: list[str], *, check: bool = True, input: str | None = None) -> subprocess.CompletedProcess[str]:
    print("$ " + " ".join(command))
    result = subprocess.run(command, input=input, text=True, capture_output=True, check=False)
    if check and result.returncode:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}{result.stderr}"
        )
    return result


def diagnostics() -> None:
    for command in (
        ["kubectl", "get", "pods", "-A", "-o", "wide"],
        ["kubectl", "get", "events", "-A", "--sort-by=.lastTimestamp"],
        ["kubectl", "describe", "pod", POD],
        ["kubectl", "logs", POD],
    ):
        result = run(command, check=False)
        if result.stdout:
            print(result.stdout, file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr)


def pod_manifest(image_ref: str) -> str:
    manifest = {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {"name": POD},
        "spec": {
            "restartPolicy": "Never",
            "containers": [{
                "name": "runtime-check",
                "image": image_ref,
                "imagePullPolicy": "Always",
                "workingDir": "/home/node",
                "command": ["/bin/sh", "-ec", (
                    'test "$(id -u)" -eq 1000; '
                    'test "$(id -u sandbox)" -ne 0; '
                    'test "$HOME" = /home/node; '
                    'test -w /home/node; '
                    'test -w /home/node/.config; '
                    'test "$(stat -c %u /sandbox)" = "$(id -u sandbox)"; '
                    'opencode --version; agent-swarm-mcp-server --help >/dev/null; '
                    'echo "runtime uid=$(id -u) image-pull=ok mcp-startup=ok"'
                )],
                "securityContext": {
                    "runAsNonRoot": True,
                    "runAsUser": 1000,
                    "allowPrivilegeEscalation": False,
                    "capabilities": {"drop": ["ALL"]},
                    "seccompProfile": {"type": "RuntimeDefault"},
                },
            }],
        },
    }
    return json.dumps(manifest)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image-ref", required=True)
    parser.add_argument("--cluster-name", default="agent-containers-e2e")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()
    created = False
    failed = False
    try:
        image_ref = validate_image_ref(args.image_ref)
        if not CLUSTER_NAME.fullmatch(args.cluster_name):
            raise ValueError("cluster name must be a DNS label")
        missing = [cmd for cmd in ("kind", "kubectl", "docker") if shutil.which(cmd) is None]
        if missing:
            raise RuntimeError(f"missing required commands: {', '.join(missing)}")
        clusters = run(["kind", "get", "clusters"])
        if args.cluster_name in clusters.stdout.splitlines():
            raise RuntimeError(f"KinD cluster {args.cluster_name!r} already exists")
        created = True
        run(["kind", "create", "cluster", "--name", args.cluster_name, "--wait", "180s"])
        run(["kubectl", "apply", "-f", "-"], input=pod_manifest(image_ref))
        run(["kubectl", "wait", "--for=jsonpath={.status.phase}=Succeeded", f"pod/{POD}", f"--timeout={args.timeout}s"])
        result = run(["kubectl", "logs", POD])
        print(result.stdout.rstrip())
        if "runtime uid=1000 image-pull=ok mcp-startup=ok" not in result.stdout:
            raise RuntimeError("KinD workload did not report successful runtime checks")
        print("[PASS] KinD pulled and ran the digest-pinned Pod under non-root security context")
    except (ValueError, RuntimeError, subprocess.SubprocessError, OSError) as exc:
        failed = True
        print(f"[FAIL] KinD Pod E2E: {exc}", file=sys.stderr)
        if created:
            diagnostics()
    finally:
        if created:
            deleted = run(["kind", "delete", "cluster", "--name", args.cluster_name], check=False)
            if deleted.returncode:
                failed = True
                print(deleted.stderr, file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
