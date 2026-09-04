# OpenHomepower Secure Broker

A secure MQTT broker for Energizer Homepower batteries. It runs **alongside**
the default Mosquitto add-on (on its own port, `1885`), so it never touches the
broker Zigbee2MQTT uses — and it gives each battery **its own credentials** and
**its own isolated topics**, so your battery no longer depends on the vendor
cloud.

## 1. Configure your battery

In the **Configuration** tab:

```yaml
devices:
  - serial: "1234567890"              # your MQTT topic serial
    password: "choose-a-strong-one"   # the login Home Assistant / the app use
battery_login:
  username: "..."                     # the login the battery firmware uses
  password: "..."                     # (see "How the battery logs in" below)
```

- **`devices`** — one entry per battery. `serial` is the topic serial (the
  `<serial>` in `Enertek/<serial>/…`); `password` is what **Home Assistant and
  the app** log in with (their username is the serial).
- **`battery_login`** — the credential the **battery's own firmware** uses. The
  Homepower gateway authenticates with a fixed username baked into its firmware
  (it is *not* the serial), so it can't be confined by serial the way clients
  are. Set it here and the broker grants that login read/write on exactly your
  configured serial(s) — nothing else. Leave it blank if no battery connects
  directly (clients only).

Find your topic serial on the gateway (SSH in, `homepower` / `123456`):

```sh
grep -oE 'Enertek/[0-9]+/' /tmp/wemonitor.log | head -1
```

**Start** (or restart) the add-on after any change. The log prints a
`provisioned …` line for each login.

### How the battery logs in

The gateway daemon's MQTT username and password are **compiled into its
firmware**, not read from any config file — so you can't change them, and you
can't repoint the battery with a config edit. Recover them from your gateway
(the daemon prints its username in the startup log) and put them in
`battery_login`. The ACL confines that login to your configured serial(s).

## 2. Point the battery at this broker (network redirect)

Because the broker host is hardcoded in the firmware, you redirect the battery
at the **network layer**, not by config — one reversible `iptables` rule on the
gateway that sends its MQTT traffic to this broker. The exact commands (and how
to make them persist and roll back) are in the main
[README](https://github.com/seanlewis/openhomepower-broker#readme) → **Repoint
the battery**.

## 3. Point the OpenHomepower integration at it

In **OpenHomepower → Configure**, set the broker **host** to this Home Assistant
host, **port `1885`**, and the **username/password** to a `devices` serial and
its password.

## Notes

- **Plaintext, trusted network only.** The battery's firmware can't do TLS, so
  the device → broker link is plaintext. Fine on your home LAN. Don't expose
  1885 to the internet; for remote access use a VPN.
- **Isolation:** serial-named client logins are confined to `Enertek/<serial>/#`
  by `pattern readwrite Enertek/%u/#`; the shared battery login is confined to
  your configured serial(s) by explicit rules. No login can reach another
  household's topics.
- Once redirected, monitoring **and** control no longer depend on Enertek's
  cloud being up.
