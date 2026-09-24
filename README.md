# OpenHomepower MQTT Broker

**Run your Energizer Homepower battery's MQTT connection through your own
broker, instead of depending on Enertek's cloud.**

> Not affiliated with Energizer, 8 Star Energy or Enertek Holdings.

Enertek has walked away from the Homepower: the product is discontinued and its
cloud has been unreliable, offline for extended periods at a time. This project
lets you run your **own** MQTT broker on your network and point your battery at
it. Control keeps working when Enertek's cloud is down, everything stays on your
network, and each login is confined to its own topics.

It pairs with the [**OpenHomepower Home Assistant
integration**](https://github.com/seanlewis/openhomepower-hass): the integration
reads telemetry and sends control commands, and this broker carries them.

## Should I do this?

You **don't need** this broker to monitor your battery. With the integration's
SSH source (the default for most units), sensors work without it. It's for
people who want **control** (mode, reserve limits, schedules) that doesn't
depend on Enertek's servers.

| | Without this broker | With this broker |
| --- | --- | --- |
| Home Assistant sensors | ✅ Work with the SSH source (the MQTT source needs Enertek's cloud) | ✅ Work with either source |
| Home Assistant control | Only while Enertek's cloud is up | ✅ Always (while your broker is up) |
| Enertek app and portal | ✅ Work | ❌ Stop showing your battery |
| Extra moving parts | None | A broker you keep running |

It's fully reversible: one command on the battery puts it back on Enertek's
cloud.

## How it works

Your battery's gateway has its broker address and MQTT login **fixed in its
firmware**, so there's no setting to repoint it. Setup has two parts:

1. **Run this broker** with two kinds of login: the battery's own login, and one
   for your clients (Home Assistant, the app).
2. **Redirect the battery** to it with one reversible network rule on the
   gateway. The firmware won't do it, so the network does.

## Install

### Home Assistant OS / Supervised — add-on (recommended)

**One click:** install the add-on, then in Home Assistant go to **OpenHomepower
→ Configure → Move to local broker** (integration 0.7.0 or later). It configures
the add-on, redirects the battery, checks it connected, and undoes everything if
not.

**Manual backup:** the step-by-step guide in the add-on's **Documentation** tab
does the same by hand. It's also here: [`broker/DOCS.md`](broker/DOCS.md).

In short: **Settings → Add-ons → Add-on Store → ⋮ → Repositories**, add
`https://github.com/seanlewis/openhomepower-broker`, and install **OpenHomepower
Secure Broker**. It listens on port **1885**, clear of the standard Mosquitto
add-on (1883/1884/8883/8884), so Zigbee2MQTT and anything else on that broker
are unaffected.

### Docker (Proxmox VM/LXC, NAS, any Linux)

1. **Get your battery's details.** In Home Assistant, **OpenHomepower →
   Configure → Settings** shows the **Control broker username/password** (the battery's own
   login) and the **MQTT topic serial**. Copy them before changing anything. No
   Home Assistant? See [Reading the details from the battery](#reading-the-details-from-the-battery).
2. **Start the broker:** `docker compose up -d` (listens on **1883**).
3. **Add a client login** for Home Assistant or the app:
   `./provision-device.sh <topic-serial>`. It prints the generated password.
4. **Add the battery's login:**

   ```sh
   docker compose exec mosquitto mosquitto_passwd -b /mosquitto/config/passwordfile <battery-username> <battery-password>
   ```

   and append to `mosquitto/config/aclfile`:

   ```conf
   user <battery-username>
   topic readwrite Enertek/<topic-serial>/#
   ```

   Then `docker compose restart mosquitto`.
5. **[Redirect the battery](#redirect-the-battery)**, using this machine's IP and
   port `1883`.
6. **Point your clients at it:** host = this machine, port `1883`, username = the
   topic serial, password = from step 3.

### Native (Debian, Raspberry Pi OS, LXC)

`apt install mosquitto`, copy `mosquitto/config/*` into `/etc/mosquitto/conf.d/`
(adjusting the `/mosquitto/` paths), then follow the Docker steps from step 3,
using `mosquitto_passwd` directly and `systemctl restart mosquitto`.

## Redirect the battery

> Do this **after** the broker is running with the battery's login, or the
> battery will be refused. The add-on guide has these same steps with more
> detail.

Reserve your broker machine's IP in your router first: the battery is pointed at
that address.

Connect from a terminal (**Terminal** on a Mac, **PowerShell** on Windows); the
password is `123456`:

```sh
ssh -p 34522 homepower@<battery-ip>
```

Then run, replacing `<broker-ip>:<port>` in both places (e.g.
`192.168.1.50:1885` for the add-on, `192.168.1.50:1883` for Docker):

```sh
iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-ip>:<port>
grep -q 'dport 1884 -j DNAT' /etc/firewall.user || echo "iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-ip>:<port>" >> /etc/firewall.user
reboot
```

The first line redirects the battery's outbound MQTT (port 1884) to your broker,
the second makes it survive restarts (OpenWrt runs `/etc/firewall.user` at every
boot), and the reboot gives one clean, redirected connection. Restarting only the
battery's software on this firmware can leave an old copy running, so reboot.

**Check it worked:** your broker's log should show a client connecting from the
battery's IP with the battery's username. The gateway's own log still names
Enertek's server — it doesn't know it's been redirected.

**Undo:**

```sh
sed -i '/--dport 1884 -j DNAT/d' /etc/firewall.user
reboot
```

### Reading the details from the battery

If you can't get them from the integration, connect as above and run:

```sh
uci show we2 | grep mqtt
grep -oE 'Enertek/[0-9]+/' /tmp/wemonitor.log | head -1
```

`we2.mqtt.user` / `we2.mqtt.pwd` are the battery's login; the number in
`Enertek/<number>/` is the topic serial.

**SSH troubleshooting:** `no matching host key type found` → add
`-o HostKeyAlgorithms=+ssh-rsa` after `ssh`. `Permission denied` → the password
must be typed at the prompt.

## Security

- **Each client is confined to its own topics.** Clients log in with the battery's
  topic serial as their username, and one pattern rule restricts each to that
  serial's topics:
  ```conf
  pattern readwrite Enertek/%u/#
  ```
- **The battery's login is scoped** to exactly the serial(s) you configure, and
  nothing else.
- **Plaintext on your network; TLS available for clients.** The battery can't do
  TLS (see below).

## Plaintext and TLS

The battery's gateway software has no encryption support, so it **cannot do
TLS**. The battery-to-broker connection is plaintext on your broker's
`1885`/`1883` port. That's fine on a **trusted home network**. Never expose that
port to the internet; for anything off-network, use a VPN or tunnel (WireGuard,
Tailscale, or an `stunnel` relay near the gateway).

For clients that *can* do TLS (Home Assistant, the app, dashboards), generate a
CA and server certificate into `mosquitto/config/certs/`, uncomment the `8883`
block in `mosquitto/config/mosquitto.conf`, and point those clients at `8883`
with the CA. The battery stays on the plaintext port.

## Licence

MIT.
