# OpenHomepower Secure Broker

Run your Energizer Homepower battery's MQTT connection through your own Home
Assistant instead of Enertek's cloud. Once it's set up, monitoring **and**
control keep working when Enertek's servers are down.

This add-on runs **alongside** the standard Mosquitto add-on, on its own port
(`1885`). It doesn't touch the broker Zigbee2MQTT or anything else uses.

## Before you start

**What changes when you do this**

- ✅ Home Assistant can monitor and control the battery with no Enertek cloud in
  the path.
- ⚠️ **The Enertek app and web portal stop showing your battery.** It can only
  talk to one broker, and it will be talking to yours. You can undo this at any
  time (see [Undo](#undo)).
- ⚠️ The battery's connection now depends on your Home Assistant machine. If Home
  Assistant is off, the battery carries on with its current settings, but you
  can't see or change it until Home Assistant is back.

**You'll need**

- The [OpenHomepower integration](https://github.com/seanlewis/openhomepower-hass)
  installed and working. You'll copy two values from it in step 1.
- Your **Home Assistant IP address**: **Settings → System → Network**. Reserve it
  in your router (a "DHCP reservation" or "fixed IP") — the battery is pointed at
  this address, so if it changes, the battery loses its connection.
- Your **battery's IP address** (the one the integration uses).
- A computer on the same network with a terminal: **Terminal** on a Mac, or
  **PowerShell** on Windows 10/11. You'll paste a few commands into it once.

## The easy way: one click

With the OpenHomepower integration **version 0.7.0 or later**:

1. Install this add-on (**Settings → Add-ons → Add-on Store → ⋮ → Repositories**,
   add `https://github.com/seanlewis/openhomepower-broker`, then install
   **OpenHomepower Secure Broker**). You don't need to configure it.
2. **Settings → Devices & Services → OpenHomepower → Configure → Move to local
   broker.** Check the battery and Home Assistant addresses, then submit.

Home Assistant configures this add-on, points the battery at it, reboots the
battery's gateway and checks the battery has connected. It takes up to 6 minutes.
If the battery doesn't connect, the change is undone automatically. To reverse
it later, use **Move back to Enertek's broker** in the same menu.

If a step fails, the message says which one. **Settings → System → Logs**
(search `openhomepower`) and this add-on's **Log** tab have the detail.

## Stopping or removing this add-on

While your battery is moved here, this add-on **is** its broker. If you stop or
uninstall it, the battery keeps running on its current settings but Home
Assistant loses control of it (and, on MQTT-only units, its readings). **Move
back to Enertek's broker first**, then stop or remove the add-on.

## Manual steps (backup)

Use these if the button isn't available or reports a problem. They make exactly
the same change, so the button's **Move back** can undo a manual move and vice
versa. Allow about 15 minutes. The battery keeps running normally throughout.

## Step 1 — Copy your battery's details

Do this **before** changing anything else. The integration has already read these
values from your battery; this is the easiest place to get them.

1. **Settings → Devices & Services → OpenHomepower → Configure → Settings.**
2. Write down these three values (you don't need to save the form):
   - **Control broker username** and **Control broker password** — the login the
     battery itself uses to connect to its broker.
   - **MQTT topic serial** — a 10-digit number identifying your battery's topics.
     (It's often *not* the serial printed on the battery or shown in the portal.)
3. Close the form without changing anything.

<details>
<summary>Fields are blank?</summary>

The integration reads them from the battery over your network. If they're blank,
Home Assistant can't reach the battery — fix that first (see the integration's
README, "Check Home Assistant can reach the battery"). Alternatively, read them
directly from the battery using the SSH steps in step 3, running:

```sh
uci show we2 | grep mqtt
grep -oE 'Enertek/[0-9]+/' /tmp/wemonitor.log | head -1
```

`we2.mqtt.user` / `we2.mqtt.pwd` are the battery login; the number in
`Enertek/<number>/` is the topic serial.

</details>

## Step 2 — Configure and start the add-on

1. Install this add-on if you haven't: **Settings → Add-ons → Add-on Store → ⋮
   (top right) → Repositories**, add
   `https://github.com/seanlewis/openhomepower-broker`, then find and install
   **OpenHomepower Secure Broker**.
2. Open the add-on's **Configuration** tab and enter (switch to **Edit in YAML**
   from the ⋮ menu if that's easier):

   ```yaml
   devices:
     - serial: "1234567890"             # the MQTT topic serial from step 1
       password: "make-up-a-new-one"    # a NEW password — Home Assistant uses it in step 5
   battery_login:
     username: "..."                    # Control broker username from step 1
     password: "..."                    # Control broker password from step 1
   ```

   - `devices` → `password` is a new password you choose now. Keep it — you'll
     type it into the integration in step 5.
   - `battery_login` must be **exactly** what you copied in step 1, or the
     battery will be refused.
3. **Save**, then go to the **Info** tab and **Start** the add-on.
4. Open the **Log** tab. You should see:

   ```
   provisioned client login '1234567890' (confined to Enertek/1234567890/#)
   provisioned battery login '...'
   ```

   If either line is missing, re-check the Configuration tab.

## Step 3 — Point the battery at the add-on

The battery's broker address is fixed in its firmware, so it can't be changed in
a settings screen. Instead you add one network rule on the battery's gateway that
sends its broker traffic to your Home Assistant. Nothing in the firmware is
changed, and it's fully reversible.

1. Open Terminal (Mac) or PowerShell (Windows) and connect to the battery,
   replacing `<battery-ip>`:

   ```sh
   ssh -p 34522 homepower@<battery-ip>
   ```

   Type `yes` if asked to trust the device, then the password `123456` (nothing
   appears as you type — that's normal).

2. Paste these three lines, replacing **`<ha-ip>`** (in both places) with your
   Home Assistant IP address:

   ```sh
   iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <ha-ip>:1885
   grep -q 'dport 1884 -j DNAT' /etc/firewall.user || echo "iptables -t nat -A OUTPUT -p tcp --dport 1884 -j DNAT --to-destination <ha-ip>:1885" >> /etc/firewall.user
   reboot
   ```

   The first line redirects the traffic, the second keeps the rule after a
   restart, and the third restarts the gateway so it reconnects cleanly. Your
   terminal will disconnect — that's expected.

> **Why reboot?** The rule only affects new connections, and restarting just the
> battery's software on this firmware can leave an old copy running. A reboot
> gives one clean, redirected connection.

## Step 4 — Check the battery has connected

Wait about two minutes, then open the add-on's **Log** tab. You're looking for a
line like:

```
New client connected from <battery-ip>:... as ... (..., u'<battery username>').
```

That's the battery, now talking to your broker. If it isn't there after five
minutes, see [Troubleshooting](#troubleshooting).

## Step 5 — Point the integration at the add-on

1. **Settings → Devices & Services → OpenHomepower → Configure → Settings.**
2. Set:

   | Field | Value |
   | --- | --- |
   | Control broker host | your Home Assistant IP address |
   | Control broker port | `1885` |
   | Control broker username | your topic serial (e.g. `1234567890`) |
   | Control broker password | the **new** password you chose in step 2 |

3. **Submit.** If the integration uses the MQTT telemetry source, its sensors
   update within a minute — that confirms the whole path. With the SSH source,
   sensors don't use the broker; control changes (e.g. application mode) are the
   check.

You're done. Your battery no longer depends on Enertek's cloud.

## Undo

Connect to the battery as in step 3, then run:

```sh
sed -i '/--dport 1884 -j DNAT/d' /etc/firewall.user
reboot
```

After the reboot the battery reconnects to Enertek, and the app and portal work
again. Put the original values from step 1 back into the integration's
**Configure → Settings** screen.

## Troubleshooting

| Symptom | Likely cause and fix |
| --- | --- |
| Add-on stops straight after starting (its Log ends with `running mosquitto as user: mosquitto`, then stops) | You're on version 0.2.1, which has a bug. **Update the add-on** to 0.2.2 or later. |
| Add-on won't start: port in use | Something else is using port 1885. Stop it, or change the port on the add-on's **Network** section and use that port in steps 3 and 5. |
| Log shows the battery connecting, then `not authorised` / `bad user name or password` | `battery_login` doesn't match step 1 exactly. Fix it and restart the add-on — no need to touch the battery. |
| No battery connection in the log | The rule isn't there or points at the wrong address. Reconnect as in step 3 and run `iptables -t nat -S OUTPUT \| grep 1884`: it should show your Home Assistant IP. If Home Assistant's IP has changed, run [Undo](#undo), then step 3 again with the new IP. |
| `ssh: no matching host key type found` | Your computer's SSH is newer than the battery's. Add `-o HostKeyAlgorithms=+ssh-rsa` after `ssh`. |
| `Permission denied` when connecting | The password is `123456` unless it has been changed. It must be typed in when prompted. |
| Control entities unavailable after step 5 | Check the host, port `1885`, username (the topic serial) and password in the integration's **Configure → Settings** screen. |

## Security notes

- **Each login is confined.** Home Assistant logs in as your topic serial and can
  only reach that serial's topics. The battery's login can only reach the
  serial(s) you list under `devices`.
- **Plaintext on your network.** The battery can't do TLS, so its connection to
  this broker is unencrypted. That's fine on your home network — **never** expose
  port 1885 to the internet. For remote access, use a VPN such as Tailscale.
