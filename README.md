# OpenHomepower MQTT Broker

**A secure, self-hostable MQTT broker for Energizer Homepower batteries — run
your own, instead of depending on the vendor cloud.**

> Not affiliated with Energizer, 8 Star Energy or Enertek Holdings.

Enertek has walked away from the Homepower — the product is discontinued and its
cloud has been unreliable, offline for extended periods at a time. This project
lets you run your **own** local MQTT broker and point your battery at it, so it no
longer depends on the vendor's servers: control keeps working when their cloud is
down, everything stays on your own network, and each device gets its own
credentials and isolated topics.

Pair it with the [**OpenHomepower Home Assistant integration**](https://github.com/seanlewis/openhomepower-hass)
to run battery control entirely on your own network — the integration sends the
commands, this broker is the local transport that carries them.

## Security

- **Per-device credentials** — every device authenticates with its own login.
- **Per-device isolation** — one ACL rule confines each device to its own topics
  (`mosquitto/config/aclfile`):

  ```conf
  pattern readwrite Enertek/%u/#
  ```

  A device authenticates with its **serial as the username**, so `%u` scopes it
  to `Enertek/<own-serial>/#` — it can only ever see or control its own battery.
- **On your trusted network**; TLS available for clients that support it (Home
  Assistant, the app, dashboards).

## Install — pick your platform

- **Home Assistant OS / Supervised → add-on (one click).** Add-ons aren't
  distributed via HACS, so add this repo under **Settings → Add-ons → ⋮ →
  Repositories**, then install **OpenHomepower Secure Broker**. It runs on port
  **1885** — clear of the Mosquitto add-on (which uses 1883/1884/8883/8884) and
  never touching the broker Zigbee2MQTT uses.
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

`provision-device.sh` creates a per-device (client) credential and tells you
what to enter in Home Assistant → OpenHomepower → Configure. You also need the
battery's own **firmware login** on the broker and a network redirect on the
gateway — see *Repoint the battery* below.

Find your topic serial on the gateway:
`grep -oE 'Enertek/[0-9]+/' /tmp/wemonitor.log | head -1`.

## Important: the device speaks plaintext only

The Homepower gateway daemon links no crypto library — **it cannot do TLS.** So
the device→broker link (port 1883) is plaintext. 

That's fine on a **trusted LAN**. For anything beyond your own network — or a 
hosted deployment — do **not** expose 1883 to the internet; put the hop inside a 
**VPN or tunnel** (WireGuard, Tailscale, an `stunnel`/relay on the gateway's 
network). The TLS listener (8883) is for clients that *can* do TLS — Home 
Assistant, the app, dashboards — not the battery.

## TLS (optional, for capable clients)

Generate a CA + server cert into `mosquitto/config/certs/`, uncomment the `8883`
block in `mosquitto/config/mosquitto.conf`, and point HA/the app at `8883` with
the CA. (The battery stays on 1883 — it can't do TLS.)

## Repoint the battery

The gateway daemon's broker host **and** login are compiled into its firmware —
they are **not** read from any config file (editing `/etc/config/we2` does
nothing). So the battery is redirected at the **network layer**: one `iptables`
rule on the gateway rewrites its outbound MQTT to your broker.

First provision the battery's firmware login on the broker (the add-on's
`battery_login`, or a matching user + ACL on the Docker route). Then, on the
gateway (`ssh -p 34522 homepower@<gateway-ip>`):

```sh
# Redirect the daemon's outbound MQTT (port 1884) to your broker.
# <broker-host>:<port> = your broker, e.g. 192.168.1.50:1885 (add-on) or :1883 (Docker).
iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-host>:<port>

# Make it persist across reboots (OpenWrt runs /etc/firewall.user on every firewall start):
echo "iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-host>:<port>" >> /etc/firewall.user

/etc/init.d/we2 restart      # reconnect the daemon so it takes the redirect
```

Nothing is written to the firmware and no config file is changed, so **rollback**
is just removing the rule:

```sh
sed -i '/--dport 1884 -j DNAT/d' /etc/firewall.user
iptables -t nat -D OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-host>:<port>
/etc/init.d/we2 restart      # back to the vendor broker
```

## Licence

MIT.
