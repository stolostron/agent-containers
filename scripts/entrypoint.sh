#!/usr/bin/env bash
# Copy the SSH deploy key with correct permissions so SSH will accept it.
# The secret is mounted read-only at /run/secrets/github/id_rsa (root-owned,
# world-readable). Copying it makes the node user the owner, then chmod 600
# satisfies SSH's strict permission requirements.
mkdir -p -m 700 /home/node/.ssh
for i in 1 2 3 4 5; do
    if cp /run/secrets/github/id_rsa /home/node/.ssh/id_rsa 2>/dev/null; then
        chmod 600 /home/node/.ssh/id_rsa
        break
    fi
    sleep 1
done
exec "$@"
