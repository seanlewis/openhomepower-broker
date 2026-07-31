# OpenHomepower Broker

**A secure, self-hostable MQTT broker to replace Enertek's abandoned cloud for
Energizer Homepower batteries.**

> Not affiliated with Energizer, 8 Star Energy or Enertek Holdings.

Enertek has walked away from the Homepower, leaving its cloud broker orphaned —
unreliable, and with a serious security weakness: **every device ships the same
shared credentials and the broker enforces no per-device isolation**, so anyone
with those credentials can read *and control* any unit whose serial they know.

This project lets you run your **own** broker and point your battery at it. Your
device leaves the vulnerable shared cloud entirely, and control keeps working
even when Enertek's servers are down.

## What it fixes

| Enertek's broker | This broker |
| --- | --- |
| One **shared** credential on every device | **Per-device** credentials |
| **No ACL** — any client reaches any unit | Each device confined to **its own serial's topics** |
| Plaintext, internet-exposed | On your **trusted network**; TLS for capable clients |

The isolation is one rule (`mosquitto/config/aclfile`):

```conf
pattern readwrite Enertek/%u/#
```

Each device authenticates with its **serial as the username**, so `%u` scopes it
to `Enertek/<own-serial>/#` — it can never touch another device. That single
line is the fix for the cross-tenant exposure.

## Install — pick your platform

- **Home Assistant OS / Supervised → add-on (one click).** Add-ons aren't
  distributed via HACS, so add this repo under **Settings → Add-ons → ⋮ →
  Repositories**, then install **OpenHomepower Secure Broker**. It runs on port
  **1884**, alongside — and never touching — the Mosquitto that Zigbee2MQTT uses.
  Configure your device(s) in its Configuration tab. See
  [`broker/DOCS.md`](broker/DOCS.md).
- **Docker (Proxmox VM/LXC, NAS, any Linux) → `docker compose`** — below.
- **Native (LXC, Debian, Raspberry Pi OS) → `apt install mosquitto`**, drop
  `mosquitto/config/*` into `/etc/mosquitto/conf.d/` (adjust the `/mosquitto/`
  paths), and provision with `mosquitto_passwd`.

## Quick start (Docker)

Requires Docker.

```bash
touch mosquitto/config/passwordfile     # start empty — nobody connects until provisioned
docker compose up -d

chmod +x provision-device.sh
./provision-device.sh 1234567890        # your device's TOPIC serial (from Enertek/<serial>/…)
```

`provision-device.sh` creates a per-device credential and prints the exact
`uci` commands to repoint your gateway at this broker (and the rollback). It
also tells you what to enter in Home Assistant → OpenHomepower → Configure.

Find your topic serial on the gateway:
`grep -oE 'Enertek/[0-9]+/' /tmp/wemonitor.log | head -1`.

## Important: the device speaks plaintext only

The Homepower gateway daemon links no crypto library — **it cannot do TLS.** So
the device→broker link (port 1883) is plaintext. That's fine on a **trusted LAN**.
For anything beyond your own network — or a hosted deployment — do **not** expose
1883 to the internet; put the hop inside a **VPN or tunnel** (WireGuard,
Tailscale, an `stunnel`/relay on the gateway's network). The TLS listener (8883)
is for clients that *can* do TLS — Home Assistant, the app, dashboards — not the
battery.

## Single-user vs. multi-tenant

- **Single-user (self-host, recommended):** one device, your own broker on your
  LAN. Authenticate Home Assistant/the app as the device serial too — same scope,
  nothing else to configure. The cross-tenant problem is moot; the per-device
  creds + ACL are belt-and-braces.
- **Multi-tenant / hosted:** the same package scales — every device already gets
  its own credential and ACL scope. To offer it as a service you'd add: a
  provisioning/signup flow, per-operator accounts (own ACL rules rather than
  reusing a device serial), TLS + a tunnel for the plaintext device leg, uptime
  monitoring, and — importantly — the operational and trust responsibilities of
  holding control access to other people's batteries. Start self-hostable; grow
  into hosted deliberately.

## TLS (optional, for capable clients)

Generate a CA + server cert into `mosquitto/config/certs/`, uncomment the `8883`
block in `mosquitto/config/mosquitto.conf`, and point HA/the app at `8883` with
the CA. (The battery stays on 1883 — it can't do TLS.)

## Rollback

Repointing is fully reversible. **Before** you repoint, note your current
settings with `uci show we2`; to roll back, set `we2.mqtt.host/port/user/pwd`
back to those values and `uci commit we2 && /etc/init.d/we2 restart`.

## Licence

MIT.
