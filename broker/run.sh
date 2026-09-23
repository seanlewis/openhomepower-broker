#!/bin/sh
# Home Assistant add-on entrypoint. Builds the password + ACL files from the
# add-on options, then starts Mosquitto.
#
# Two kinds of login:
#  * per-serial CLIENT logins (Home Assistant, the app) — username = the topic
#    serial, so the pattern rule confines each to Enertek/<serial>/#.
#  * the BATTERY firmware login — the gateway daemon authenticates with a
#    fixed username baked into its firmware (NOT its serial), so it can't be
#    scoped by the pattern. It gets explicit readwrite on each configured
#    serial's topics instead. Leave battery_login blank if no battery connects
#    directly (clients only).
set -e

OPTS=/data/options.json
PWFILE=/data/passwordfile
ACLFILE=/etc/openhomepower/aclfile
BLTOPICS=/tmp/ohp_battery_topics       # per-serial rules for the battery login

# Mosquitto runs as the unprivileged `mosquitto` user and opens these files as
# that user, so they must be owned by it (and private to it). Root-owned 0600
# made the password file unreadable: mosquitto exited at start and nothing
# listened on 1885. Persistence gets its own mosquitto-owned directory for the
# same reason (/data itself is root-owned).
mkdir -p /data/mosquitto
chown mosquitto:mosquitto /data/mosquitto
# Rebuilt from scratch each start: root writes it (mosquitto_passwd warns about a
# file root doesn't own), then it's handed to mosquitto just before launch.
rm -f "$PWFILE"
(umask 077; : > "$PWFILE")
: > "$BLTOPICS"

# --- ACL header: serial-named clients confined by the pattern ----------------
{
    echo "# Generated at start from the add-on configuration — do not edit by hand."
    echo "# Serial-named client logins (Home Assistant, the app):"
    echo "pattern readwrite Enertek/%u/#"
} > "$ACLFILE"

# --- per-serial client logins ------------------------------------------------
count=$(jq '.devices | length' "$OPTS" 2>/dev/null || echo 0)
i=0
while [ "$i" -lt "$count" ]; do
    serial=$(jq -r ".devices[$i].serial" "$OPTS")
    password=$(jq -r ".devices[$i].password" "$OPTS")
    if [ -n "$serial" ] && [ "$serial" != "null" ] \
       && [ -n "$password" ] && [ "$password" != "null" ]; then
        mosquitto_passwd -b "$PWFILE" "$serial" "$password"
        echo "topic readwrite Enertek/$serial/#" >> "$BLTOPICS"
        echo "provisioned client login '${serial}' (confined to Enertek/${serial}/#)"
    fi
    i=$((i + 1))
done

# --- battery firmware login --------------------------------------------------
bl_user=$(jq -r '.battery_login.username // ""' "$OPTS")
bl_pass=$(jq -r '.battery_login.password // ""' "$OPTS")
if [ -n "$bl_user" ] && [ "$bl_user" != "null" ] \
   && [ -n "$bl_pass" ] && [ "$bl_pass" != "null" ]; then
    mosquitto_passwd -b "$PWFILE" "$bl_user" "$bl_pass"
    {
        echo ""
        echo "# Battery firmware login (fixed username), scoped to your serial(s):"
        echo "user $bl_user"
        cat "$BLTOPICS"
    } >> "$ACLFILE"
    echo "provisioned battery login '${bl_user}'"
fi

if [ "$count" -eq 0 ]; then
    echo "No devices configured yet — add one in the add-on Configuration tab."
fi

rm -f "$BLTOPICS"
chown mosquitto:mosquitto "$PWFILE" "$ACLFILE"
chmod 600 "$PWFILE" "$ACLFILE"
exec mosquitto -c /etc/openhomepower/mosquitto.conf
