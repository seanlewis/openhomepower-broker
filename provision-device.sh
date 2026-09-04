#!/usr/bin/env bash
# Provision a Homepower device (or a client) on this broker, and print the
# commands to repoint the gateway at it.
#
#   ./provision-device.sh <topic-serial> [password]
#
# The username IS the device's topic serial (the <serial> in Enertek/<serial>/),
# so the pattern ACL confines it to its own topics automatically. Run the broker
# first (docker compose up -d).
set -euo pipefail

SERIAL="${1:?usage: ./provision-device.sh <topic-serial> [password]}"
if ! [[ "$SERIAL" =~ ^[0-9]+$ ]]; then
    echo "error: serial must be numeric (the Enertek/<serial>/ topic serial)" >&2
    exit 1
fi
PASS="${2:-$(openssl rand -base64 18)}"

PWFILE="mosquitto/config/passwordfile"
touch "$PWFILE"

# Add/update the user (username = serial). mosquitto_passwd runs inside the
# container so the hash format always matches the broker's version.
docker compose exec -T mosquitto \
    mosquitto_passwd -b /mosquitto/config/passwordfile "$SERIAL" "$PASS"

# Reload without dropping existing sessions.
docker compose kill -s HUP mosquitto >/dev/null 2>&1 || docker compose restart mosquitto

cat <<EOF

Provisioned client login '$SERIAL' (password: $PASS). The ACL confines it to
Enertek/$SERIAL/# — it cannot see or control any other device. Use these in
Home Assistant → OpenHomepower → Configure (host = this broker, port 1883).

Two more steps to bring the BATTERY onto this broker:

  1. Provision the battery's firmware login (it authenticates with a fixed
     username baked into the firmware, NOT its serial). Add a user + an ACL
     rule scoped to this serial, e.g.:
       mosquitto_passwd -b mosquitto/config/passwordfile <fw-user> <fw-pass>
     then in mosquitto/config/aclfile:
       user <fw-user>
       topic readwrite Enertek/$SERIAL/#
     and restart the broker.

  2. Redirect the gateway at the network layer — the broker host is hardcoded
     in the firmware, so a config edit won't move it. See the README →
     "Repoint the battery" for the reversible iptables rule.
EOF
