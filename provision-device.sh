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

Provisioned device '$SERIAL'. The ACL confines it to Enertek/$SERIAL/# — it
cannot see or control any other device.

On the gateway (ssh -p 34522 homepower@<gateway-ip>), run:

  uci set we2.mqtt.host='<this-broker-host-or-ip>'
  uci set we2.mqtt.port='1883'
  uci set we2.mqtt.user='$SERIAL'
  uci set we2.mqtt.pwd='$PASS'
  uci commit we2
  /etc/init.d/we2 restart

To roll back, restore your original we2.mqtt.* values (run 'uci show we2' and
note them BEFORE repointing), then: uci commit we2; /etc/init.d/we2 restart

In Home Assistant → OpenHomepower → Configure, set the control broker host to
this broker and the username/password to the serial and the password above.
EOF
