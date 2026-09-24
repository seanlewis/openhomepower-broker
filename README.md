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

It's fully reversible: one click (or one command on the battery) puts it back
on Enertek's cloud.

## How it works

Your battery's gateway has its broker address and MQTT login **fixed in its
firmware**, so there's no setting to repoint it. Setup has two parts:

1. **Run this broker** with two kinds of login: the battery's own login, and one
   for your clients (Home Assistant, the app).
2. **Redirect the battery** to it with one reversible network rule on the
   gateway. The firmware won't do it, so the network does.

The Standard install below does both for you in one click.

## Install

**Most people want the Standard install.** Only use an Advanced option if you
can't run Home Assistant add-ons (for example Home Assistant Container), or you
want the broker on a different machine.

<details open>
<summary><b>⭐ Standard install — start here</b> (Home Assistant OS / Supervised, about 10 minutes)</summary>

&nbsp;

**You'll need:** the [OpenHomepower integration](https://github.com/seanlewis/openhomepower-hass)
**0.7.0 or later**, already set up and working.

1. **Add this repository to Home Assistant.**
   **Settings → Add-ons → Add-on Store → ⋮ (top right) → Repositories**, paste
   `https://github.com/seanlewis/openhomepower-broker`, and click **Add**.
2. **Install the add-on.** Find **OpenHomepower Secure Broker** in the store
   (refresh the page if it isn't there yet) and click **Install**. You don't
   need to configure it.
3. **Reserve Home Assistant's IP address** in your router (a "DHCP reservation"
   or "fixed IP"). The battery will be pointed at this address.
4. **Move the battery.** **Settings → Devices & Services → OpenHomepower →
   Configure → Move to local broker.** Check the two addresses and click
   **Submit**.

It takes up to 6 minutes. When it says **Done**, your battery is on your own
broker and Home Assistant has switched over. If the battery doesn't connect, the
change is undone automatically and the message says why.

- **To undo:** **Configure → Move back to Enertek's broker.**
- **Before stopping or removing the add-on**, move back first, because while
  moved the add-on is your battery's only broker.
- **If the button reports a problem**, the add-on's **Documentation** tab (also
  [`broker/DOCS.md`](broker/DOCS.md)) has the same steps to do by hand.

The add-on uses port **1885**, so it never clashes with the standard Mosquitto
add-on or Zigbee2MQTT.

</details>

<details>
<summary><b>Advanced: Docker</b> (Home Assistant Container, Proxmox VM/LXC, NAS, any Linux)</summary>

&nbsp;

There's no button for this route, so the battery is redirected by hand.

1. **Copy your battery's details.** In Home Assistant, **OpenHomepower →
   Configure → Settings** shows the **Control broker username/password** (the
   battery's own login) and the **MQTT topic serial**. Copy them before changing
   anything. No Home Assistant? See *Reading the details from the battery*
   below.
2. **Start the broker:** `docker compose up -d`. It listens on port **1883**.
3. **Add a login for Home Assistant (or the app):**
   `./provision-device.sh <topic-serial>`. It prints the password it generated.
4. **Add the battery's login:**

   ```sh
   docker compose exec mosquitto mosquitto_passwd -b /mosquitto/config/passwordfile <battery-username> <battery-password>
   ```

   append these two lines to `mosquitto/config/aclfile`:

   ```conf
   user <battery-username>
   topic readwrite Enertek/<topic-serial>/#
   ```

   then run `docker compose restart mosquitto`.
5. **Redirect the battery** using the commands in *Redirecting the battery by
   hand* below, with this machine's IP and port `1883`.
6. **Point Home Assistant at it:** **OpenHomepower → Configure → Settings**,
   and set the broker host to this machine, port `1883`, username to the topic
   serial and password to the one from step 3.

</details>

<details>
<summary><b>Advanced: native Mosquitto</b> (Debian, Raspberry Pi OS, LXC)</summary>

&nbsp;

Run `apt install mosquitto` and copy `mosquitto/config/*` into
`/etc/mosquitto/conf.d/`, adjusting the `/mosquitto/` paths. Then follow the
**Docker** steps from step 3, using `mosquitto_passwd` directly and
`systemctl restart mosquitto` in place of the `docker compose` commands.

</details>

<details>
<summary><b>Redirecting the battery by hand</b> (for the Advanced options, or if the button can't be used)</summary>

&nbsp;

Only do this **after** your broker is running with the battery's login, or the
battery will be refused. Reserve the broker machine's IP in your router first.

**1. Connect to the battery** from a terminal (**Terminal** on a Mac,
**PowerShell** on Windows). The password is `123456`:

```sh
ssh -p 34522 homepower@<battery-ip>
```

**2. Run these three lines,** replacing `<broker-ip>:<port>` in both places
(for example `192.168.1.50:1883` for Docker, or `:1885` for the add-on):

```sh
iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-ip>:<port>
grep -q 'dport 1884 -j DNAT' /etc/firewall.user || echo "iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <broker-ip>:<port>" >> /etc/firewall.user
reboot
```

The first line redirects the battery's MQTT traffic to your broker, the second
keeps the rule after restarts, and the reboot makes the battery reconnect
cleanly. They're safe to run more than once.

**3. Check it worked:** after a couple of minutes, your broker's log should show
a client connecting from the battery's IP with the battery's username.

**To undo,** connect again and run:

```sh
sed -i '/--dport 1884 -j DNAT/d' /etc/firewall.user
reboot
```

#### Reading the details from the battery

If you can't get the login and topic serial from the integration, connect as
above and run:

```sh
uci show we2 | grep mqtt
grep -oE 'Enertek/[0-9]+/' /tmp/wemonitor.log | head -1
```

`we2.mqtt.user` and `we2.mqtt.pwd` are the battery's login. The number in
`Enertek/<number>/` is the topic serial.

#### SSH problems

- `no matching host key type found`: add `-o HostKeyAlgorithms=+ssh-rsa` after
  `ssh`.
- `Permission denied`: type the password at the prompt (it's `123456` unless
  it's been changed).

</details>

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
