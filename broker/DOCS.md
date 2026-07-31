# OpenHomepower Secure Broker

A secure MQTT broker for Energizer Homepower batteries. It runs **alongside**
the default Mosquitto add-on (on its own port, `1884`), so it never touches the
broker Zigbee2MQTT uses — and it gives each battery **its own credentials** and
**its own isolated topics**, so your battery no longer depends on the vendor
cloud.

## 1. Add your battery

In the **Configuration** tab, add a device:

```yaml
devices:
  - serial: "1234567890"      # your MQTT topic serial
    password: "choose-a-strong-one"
```

Find the serial on the gateway (SSH in, `homepower` / `123456`):

```sh
grep -oE 'Enertek/[0-9]+/' /tmp/wemonitor.log | head -1
```

**Start** (or restart) the add-on after changing devices.

## 2. Point the battery at this broker

SSH into the gateway and repoint its daemon (use **this Home Assistant host's IP**
and port **1884**, with the serial + password from step 1). The first line backs
up your current config, so rollback is one command later:

```sh
[ -f /etc/config/we2.orig ] || cp /etc/config/we2 /etc/config/we2.orig
uci set we2.mqtt.host='<home-assistant-ip>'
uci set we2.mqtt.port='1884'
uci set we2.mqtt.user='1234567890'
uci set we2.mqtt.pwd='choose-a-strong-one'
uci commit we2
/etc/init.d/we2 restart
```

To roll back, restore that backup:

```sh
cp /etc/config/we2.orig /etc/config/we2 && /etc/init.d/we2 restart
```

## 3. Point the OpenHomepower integration at it

In **OpenHomepower → Configure**, set the control broker to this host / port
`1884` and the same serial + password.

## Notes

- **Plaintext, trusted network only.** The battery's firmware can't do TLS, so the
  device → broker link is plaintext. That's fine on your home LAN. Don't expose
  port 1884 to the internet; for remote access use a VPN.
- **Isolation:** the ACL `pattern readwrite Enertek/%u/#` confines every device
  to `Enertek/<its-serial>/#`. A device can't see or control any other.
- Once repointed, control no longer depends on Enertek's cloud being up.
