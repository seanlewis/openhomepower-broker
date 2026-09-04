# OpenHomepower MQTT Broker

**A secure, self-hostable MQTT broker for Energizer Homepower batteries — run
your own, instead of depending on the vendor cloud.**

> Not affiliated with Energizer, 8 Star Energy or Enertek Holdings.

Enertek has walked away from the Homepower — the product is discontinued and its
cloud has been unreliable, offline for extended periods at a time. This project
lets you run your **own** local MQTT broker and point your battery at it, so it no
longer depends on the vendor's servers: control keeps working when their cloud is
down, everything stays on your own network, and each login gets its own isolated
topics.

Pair it with the [**OpenHomepower Home Assistant integration**](https://github.com/seanlewis/openhomepower-hass):
the integration reads telemetry and sends control commands, this broker is the
local transport that carries them.

## How it works

Your battery's gateway has its broker address **and** its MQTT login **compiled
into its firmware** — you can't repoint it by editing a config file. So the
setup has two parts:

1. **Run this broker** on your LAN and give it two kinds of login — one for the
   battery (its firmware login) and one for your clients (Home Assistant, the app).
2. **Redirect the battery** to it with a single, reversible `iptables` rule on
   the gateway. The firmware won't do it, so the network does.

## Security

- **Per-client isolation via ACL.** Clients (HA, the app) authenticate with the
  battery's serial as their username, and one pattern rule confines each to that
  serial's topics:
  ```conf
  pattern readwrite Enertek/%u/#
  ```
- **Scoped battery login.** The battery's firmware login isn't a serial, so it
  gets an explicit rule granting read/write on exactly your configured serial(s)
  — and nothing else.
- **Plaintext on a trusted LAN**; TLS available for clients that support it. The
  battery itself can't do TLS (see below).

## Install — pick your platform

- **Home Assistant OS / Supervised → add-on (one click).** Add-ons aren't
  distributed via HACS, so add this repo under **Settings → Add-ons → ⋮ →
  Repositories**, then install **OpenHomepower Secure Broker**. It runs on port
  **1885** — clear of the Mosquitto add-on (which uses 1883/1884/8883/8884) and
  never touching the broker Zigbee2MQTT uses. See [`broker/DOCS.md`](broker/DOCS.md).
- **Docker (Proxmox VM/LXC, NAS, any Linux) → `docker compose up -d`** (listens
  on 1883).
- **Native (LXC, Debian, Raspberry Pi OS) → `apt install mosquitto`**, drop
  `mosquitto/config/*` into `/etc/mosquitto/conf.d/` (adjust the `/mosquitto/`
  paths), and provision with `mosquitto_passwd`.

## Configure

### Home Assistant add-on

In the add-on's **Configuration** tab:

```yaml
devices:
  - serial: "1234567890"              # your topic serial (the <serial> in Enertek/<serial>/…)
    password: "a-strong-password"     # clients (HA/app) log in with this + the serial
battery_login:
  username: "..."                     # the battery firmware's MQTT username
  password: "..."                     # ...and its password  (see "Finding the values")
```

**Restart** the add-on. The log prints a `provisioned …` line for each login
(`client login '<serial>'` and `battery login '<username>'`). Add one `devices`
entry per battery; `battery_login` is granted read/write on every serial you list.

#### Finding the values

- **Topic serial** — on the gateway: `grep -oE 'Enertek/[0-9]+/' /tmp/wemonitor.log | head -1`.
- **Battery firmware login** — the gateway's monitoring daemon prints its MQTT
  username in its **startup log**; use that username (and its password) for
  `battery_login`. It is a fixed value in the firmware, not the serial.

### Docker / native

Provision a client login with `./provision-device.sh <serial>`, then add the
battery's firmware login by hand — `mosquitto_passwd -b mosquitto/config/passwordfile
<fw-user> <fw-pass>`, and in `mosquitto/config/aclfile`:

```conf
user <fw-user>
topic readwrite Enertek/<serial>/#
```

Restart the broker.

## Point Home Assistant (and other clients) at it

In **OpenHomepower → Configure**: broker **host** = this broker, **port `1885`**
(add-on) or `1883` (Docker), **username** = a `devices` serial, **password** =
that serial's password. Any MQTT client (dashboards, the app) connects the same
way.

## Repoint the battery

The gateway daemon's broker address and login are compiled into its firmware —
editing `/etc/config/we2` does nothing. So you redirect it at the **network
layer**: one `iptables` rule on the gateway rewrites its outbound MQTT to your
broker. Nothing is written to the firmware, and it's fully reversible.

> **Do this only after** the broker is running with your `battery_login`
> provisioned — otherwise the battery's login is rejected.

SSH to the gateway in a **real terminal** (it needs an interactive password) and,
as root:

```sh
ssh -p 34522 homepower@<gateway-ip>

# Redirect the daemon's outbound MQTT to your broker. Match on port 1884 (the
# vendor broker's port); --to-destination is YOUR broker.
# <broker-ip>:<port> e.g. 192.168.1.50:1885 (add-on) or 192.168.1.50:1883 (Docker).
iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-ip>:<port>

# Persist it — OpenWrt runs /etc/firewall.user on every firewall start / boot:
echo "iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-ip>:<port>" >> /etc/firewall.user

# Confirm the rule is present (should print the -A OUTPUT … DNAT line):
iptables -t nat -S OUTPUT | grep 1884

# Reboot to pick it up cleanly (see note):
reboot
```

**Why reboot rather than restart the daemon?** A DNAT rule only affects *new*
connections — the daemon's existing connection to the vendor keeps running until
it reconnects. And `/etc/init.d/we2 restart` on this firmware doesn't reliably
stop the old process (it can leave a second daemon running). A reboot guarantees
one clean daemon making one fresh, redirected connection.

**Verify.** After it comes back, the battery should be on your broker. From a
client logged in as the serial, publish the read-all request bytes `31 02 ff ff`
to `Enertek/<serial>/Read_All_Input_Registers/Input` and watch for the register
dump on `…/Output`. (The gateway's own log still shows the vendor hostname — it
doesn't know it's redirected; the proof is that the reply arrives on *your*
broker.)

**Rollback** — remove the rule and the battery returns to the vendor broker:

```sh
sed -i '/--dport 1884 -j DNAT/d' /etc/firewall.user
iptables -t nat -D OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-ip>:<port>
reboot
```

## Plaintext & TLS

The Homepower gateway daemon links no crypto library — **it cannot do TLS** — so
the battery → broker hop is plaintext (your broker's `1885`/`1883` listener).
That's fine on a **trusted LAN**. Never expose that port to the internet; for
anything off-network put the hop inside a VPN or tunnel (WireGuard, Tailscale, an
`stunnel`/relay near the gateway).

For clients that *can* do TLS (Home Assistant, the app, dashboards), generate a
CA + server cert into `mosquitto/config/certs/`, uncomment the `8883` block in
`mosquitto/config/mosquitto.conf`, and point them at `8883` with the CA. The
battery stays on the plaintext port.

## Licence

MIT.
