#!/bin/bash

# One-time privileged setup for omarchy-app-theme.
#
#   sudo ~/.config/omarchy/app-theme/install-privileged.sh
#
# Installs:
#   /usr/local/bin/omarchy-app-theme-browser   root-owned helper
#   /etc/sudoers.d/omarchy-app-theme-browser   NOPASSWD for that helper only
#
# The helper can only remove the browser color policy or write one validated
# theme color into the four Chromium-family managed-policy directories.

set -euo pipefail

if (( EUID != 0 )); then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

user=${SUDO_USER:-${OMARCHY_APP_THEME_USER:-}}
if [[ -z $user && -n ${PKEXEC_UID:-} ]]; then
  user=$(id -nu "$PKEXEC_UID" 2>/dev/null || true)
fi
if [[ -z $user || $user == root ]]; then
  echo "Cannot determine the desktop user. Run it through sudo, or set OMARCHY_APP_THEME_USER." >&2
  exit 1
fi

here=$(cd -- "$(dirname -- "$0")" && pwd)
helper_src="$here/omarchy-app-theme-browser"
helper_dst=/usr/local/bin/omarchy-app-theme-browser
sudoers_dst=/etc/sudoers.d/omarchy-app-theme-browser

[[ -f $helper_src ]] || {
  echo "Missing $helper_src" >&2
  exit 1
}

install -d -m 0755 -o root -g root /usr/local/bin
install -m 0755 -o root -g root "$helper_src" "$helper_dst"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  printf '%s\n' "# Managed by omarchy-app-theme: lets $user switch the browser theme policy."
  printf '%s\n' "$user ALL=(root) NOPASSWD: $helper_dst"
} >"$tmp"

visudo -cf "$tmp" >/dev/null
install -m 0440 -o root -g root -T "$tmp" "$sudoers_dst"

echo "Installed $helper_dst"
echo "Installed $sudoers_dst"
echo
echo "Now run as your desktop user:"
echo "  omarchy-app-theme apply"
