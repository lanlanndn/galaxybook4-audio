# Galaxy Book4 Pro — Sound on Arch Linux

Working **internal speakers** and automatic **HDMI/DisplayPort output switching** for the **Samsung Galaxy Book4 Pro** (NP940XGK, Intel Core Ultra / Meteor Lake).

Tested on: Arch Linux (kernel 7.2.9-zen), PipeWire 1.6.9 + WirePlumber 0.5.18, Hyprland.

## The problem

Out of the box on Linux:

1. **No sound from the internal speakers.** The Galaxy Book4 Pro drives its speakers with four **MAX98390** amplifier chips on an I²C bus, but the mainline kernel has no driver for them (`snd-hda-scodec-max98390` does not exist yet, as of kernel 7.2.x, October 2026). The ALC298 codec handles headphones and microphone fine, but nothing drives the speaker amps — so the laptop is silent.
2. **HDMI/DP sound stays on the laptop.** Even when the kernel sees the TV (valid ELD) and PipeWire exposes the HDMI sink as *available*, WirePlumber keeps the internal speakers as the default output because the speaker sink has a higher session priority (1000 vs 696).

## The fix

Two independent parts:

### 1. MAX98390 speaker amplifier driver (DKMS)

A DKMS package of the driver from **[PR #5616](https://github.com/thesofproject/linux/pull/5616) (thesofproject/linux, by Kevin Cuperus)**, not yet merged upstream, plus a small systemd setup around it:

| File | Role |
| --- | --- |
| `etc/modules-load.d/max98390-hda.conf` | Loads `snd-hda-scodec-max98390` and `snd-hda-scodec-max98390-i2c` at boot |
| `etc/usr/local/sbin/max98390-hda-i2c-setup.sh` | Finds the I²C bus and instantiates the 3 additional amplifiers (ACPI only exposes the first one, at `0x38`) |
| `systemd/max98390-hda-i2c-setup.service` | Runs that script before `sound.target` |
| `etc/usr/local/sbin/max98390-hda-check-upstream.sh` | Detects when PR #5616 finally lands upstream and **auto-removes the whole workaround** |
| `systemd/max98390-hda-check-upstream.service` | Runs the check once per boot |

The upstream check looks for three signatures in the running kernel:

1. `serial-multi-instantiate` with a MAX98390 alias
2. the `alc298-samsung-max98390` fixup in `snd-hda-codec-alc269`
3. a native `snd-hda-scodec-max98390` in the kernel tree

When all three are present, the service removes the DKMS module, the services and the autoload config — the next reboot uses the native driver.

### 2. HDMI/DP output priority (WirePlumber)

`wireplumber/51-galaxybook-hdmi-priority.conf` raises `priority.session` of the card's HDMI/DP sinks above the internal speakers, so WirePlumber:

- picks the TV/monitor as the default sink **as soon as it is plugged in** (the sink is marked available via the kernel ELD),
- falls back to the internal speakers when unplugged.

Without this rule, sound keeps playing on the laptop even with a TV connected.

## Install

Requirements: `dkms`, kernel headers matching the running kernel (`linux-zen-headers` if you run `linux-zen`), `i2c-tools`, systemd, PipeWire + WirePlumber.

```bash
git clone https://github.com/lanlanndn/galaxybook4-audio.git
cd galaxybook4-audio
sudo ./install.sh
systemctl --user restart wireplumber
```

No reboot needed: the installer loads the modules immediately and enables the services.

### Kernel updates

DKMS rebuilds the module automatically on kernel upgrades (pacman hook). If a partial upgrade left the headers out of sync with the running kernel, fix with:

```bash
sudo pacman -Syu
sudo dkms install max98390-hda/1.0 -k $(uname -r)
```

## Troubleshooting

Speakers:

```bash
dkms status                    # is the module built for the running kernel?
journalctl -b -g max98390      # amps instantiated on the I2C bus? "workaround still needed"?
lsmod | grep max98390          # are both modules loaded?
```

HDMI/DP:

```bash
cat /proc/asound/card0/eld#2.17 | head -2   # does the kernel see the TV? (monitor_present / eld_valid)
pactl list sinks | grep -B2 -A2 HDMI         # is the HDMI sink marked "available"?
wpctl status                                 # is the default sink (*) the HDMI one?
```

If a TV/monitor is plugged in and gets video but no `monitor_present` in the ELD, the kernel side has no audio route for that connector — try another port (on this machine the TV worked on a USB-C port, shown as `DP-4`, DisplayPort alt mode).

## Credits

- **Kevin Cuperus** — author of the MAX98390 HDA driver, [PR #5616 on thesofproject/linux](https://github.com/thesofproject/linux/pull/5616)
- **Landry** — DKMS packaging, systemd glue, WirePlumber rule, installer

## License

GPL-2.0 (matching the kernel driver).
