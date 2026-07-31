#!/bin/sh
# Home Assistant add-on entrypoint. Builds the password file from the devices
# configured in the add-on options, then starts Mosquitto. The pattern ACL
# (Enertek/%u/#) confines every device to its own serial's topics.
set -e

OPTS=/data/options.json
PWFILE=/data/passwordfile

: > "$PWFILE"
count=$(jq '.devices | length' "$OPTS" 2>/dev/null || echo 0)
i=0
while [ "$i" -lt "$count" ]; do
    serial=$(jq -r ".devices[$i].serial" "$OPTS")
    password=$(jq -r ".devices[$i].password" "$OPTS")
    if [ -n "$serial" ] && [ "$serial" != "null" ] \
       && [ -n "$password" ] && [ "$password" != "null" ]; then
        mosquitto_passwd -b "$PWFILE" "$serial" "$password"
        echo "provisioned device ${serial} (confined to Enertek/${serial}/#)"
    fi
    i=$((i + 1))
done

if [ "$count" -eq 0 ]; then
    echo "No devices configured yet — add one in the add-on Configuration tab."
fi

exec mosquitto -c /etc/openhomepower/mosquitto.conf
