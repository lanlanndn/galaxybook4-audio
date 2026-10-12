#!/usr/bin/env bash
# Installer for the Galaxy Book4 audio fix:
#   1. MAX98390 speaker amplifier driver (DKMS) + systemd glue
#   2. WirePlumber rule to prefer HDMI/DP output over internal speakers
#
# Requirements: dkms, kernel headers matching the running kernel
# (linux-zen-headers if you run linux-zen), i2c-tools, systemd,
# PipeWire + WirePlumber.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DKMS_NAME="max98390-hda"
DKMS_VER="1.0"
KVER="$(uname -r)"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (try: sudo ./install.sh)" >&2
    exit 1
fi

# ---- 1. DKMS module -----------------------------------------------------
echo "== Installing DKMS module ${DKMS_NAME}-${DKMS_VER} for kernel ${KVER}"
rm -rf "/usr/src/${DKMS_NAME}-${DKMS_VER}"
cp -r "${REPO_DIR}/${DKMS_NAME}-${DKMS_VER}" "/usr/src/${DKMS_NAME}-${DKMS_VER}"

dkms add "${DKMS_NAME}/${DKMS_VER}" 2>/dev/null || true   # ok if already registered
dkms build "${DKMS_NAME}/${DKMS_VER}" -k "${KVER}"
dkms install "${DKMS_NAME}/${DKMS_VER}" -k "${KVER}"

# ---- 2. Helper scripts ---------------------------------------------------
install -Dm755 "${REPO_DIR}/etc/usr/local/sbin/max98390-hda-i2c-setup.sh" \
    /usr/local/sbin/max98390-hda-i2c-setup.sh
install -Dm755 "${REPO_DIR}/etc/usr/local/sbin/max98390-hda-check-upstream.sh" \
    /usr/local/sbin/max98390-hda-check-upstream.sh

# ---- 3. systemd services -------------------------------------------------
install -Dm644 "${REPO_DIR}/systemd/max98390-hda-i2c-setup.service" \
    /etc/systemd/system/max98390-hda-i2c-setup.service
install -Dm644 "${REPO_DIR}/systemd/max98390-hda-check-upstream.service" \
    /etc/systemd/system/max98390-hda-check-upstream.service
systemctl daemon-reload
systemctl enable --now max98390-hda-i2c-setup.service
systemctl enable max98390-hda-check-upstream.service

# ---- 4. Module autoload ---------------------------------------------------
install -Dm644 "${REPO_DIR}/etc/modules-load.d/max98390-hda.conf" \
    /etc/modules-load.d/max98390-hda.conf

# ---- 5. WirePlumber rule (user-level) ------------------------------------
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
    WP_DIR="${USER_HOME}/.config/wireplumber/wireplumber.conf.d"
    install -Dm644 -o "${SUDO_USER}" -g "$(id -g "${SUDO_USER}")" \
        "${REPO_DIR}/wireplumber/51-galaxybook-hdmi-priority.conf" \
        "${WP_DIR}/51-galaxybook-hdmi-priority.conf"
    echo "WirePlumber rule installed to ${WP_DIR}/"
    echo "Restart WirePlumber for the rule to apply:"
    echo "  systemctl --user restart wireplumber"
else
    echo "Warning: no SUDO_USER set — skipping the user-level WirePlumber rule."
    echo "Copy wireplumber/51-galaxybook-hdmi-priority.conf to"
    echo "~/.config/wireplumber/wireplumber.conf.d/ yourself."
fi

# ---- 6. Load the modules now (no reboot needed) ---------------------------
modprobe snd-hda-scodec-max98390 || true
modprobe snd-hda-scodec-max98390-i2c || true

echo
echo "Done."
echo "Speakers work right away, and HDMI/DP output becomes the default"
echo "sink automatically whenever a TV/monitor is plugged in."
