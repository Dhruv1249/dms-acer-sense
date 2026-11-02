#!/bin/sh
# Installs the privileged helper for the Acer Sense Dux Shell plugin.
# Can be run via sudo or pkexec:
#   sudo sh install.sh
#   pkexec sh install.sh
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "uninstall" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: Uninstall must be run with root privileges (sudo or pkexec)." >&2
        exit 1
    fi
    rm -f /usr/local/bin/acer-ctl /etc/sudoers.d/acer-ctl /usr/local/bin/nitro-ctl /etc/sudoers.d/nitro-ctl
    echo "Success: acer-ctl helper and sudoers rule have been removed."
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This installer must be run with root privileges. Run: sudo sh $0" >&2
    exit 1
fi

# Determine non-root target user (supports sudo and pkexec)
USER_NAME="${SUDO_USER:-${PKEXEC_UID:+$(id -nu "$PKEXEC_UID" 2>/dev/null)}:-$(logname 2>/dev/null || id -un)}}"
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
    echo "Error: Could not automatically detect the non-root user. Set SUDO_USER manually: sudo SUDO_USER=username sh $0" >&2
    exit 1
fi

# 1) Install helper binary root-owned
install -o root -g root -m 0755 "$DIR/acer-ctl" /usr/local/bin/acer-ctl

# 2) Generate and validate sudoers NOPASSWD rule for user
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/acer-ctl\n' "$USER_NAME" > "$TMP"
visudo -cf "$TMP"
install -o root -g root -m 0440 "$TMP" /etc/sudoers.d/acer-ctl
visudo -cf /etc/sudoers.d/acer-ctl

# 3) Cleanup legacy nitro-ctl if present
rm -f /usr/local/bin/nitro-ctl /etc/sudoers.d/nitro-ctl

echo "Success: acer-ctl installed in /usr/local/bin/acer-ctl with passwordless sudo rule for $USER_NAME."
