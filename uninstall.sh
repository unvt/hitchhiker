#!/bin/sh
set -eu

SITE_ROOT="/var/www/hitchhiker"
CADDY_SNIPPET_FILE="/etc/caddy/Caddyfile.d/hitchhiker.caddy"
JUSTFILE_PATH="/home/hitchhiker/Justfile"

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		echo "ERROR: This uninstaller must run as root (use sudo)." >&2
		exit 1
	fi
}

main() {
	require_root

	# Remove Justfile
	if [ -f "$JUSTFILE_PATH" ]; then
		rm -f "$JUSTFILE_PATH"
		echo "Removed Justfile from $JUSTFILE_PATH"
	fi

	# Remove just command (if installed by Hitchhiker installer)
	if command -v just >/dev/null 2>&1; then
		apt-get remove -y just || true
		echo "Removed just package"
	fi

	# Remove Caddy site snippet (safe to remove).
	if [ -f "$CADDY_SNIPPET_FILE" ]; then
		rm -f "$CADDY_SNIPPET_FILE"
	fi

	# Remove document root (WARNING: this deletes your installed web content).
	# If you want to keep PMTiles, back up /var/www/hitchhiker/pmtiles first.
	if [ -d "$SITE_ROOT" ]; then
		rm -rf "$SITE_ROOT"
	fi

	# Restart Caddy if present.
	if command -v systemctl >/dev/null 2>&1; then
		if systemctl is-active --quiet caddy 2>/dev/null; then
			systemctl restart caddy || true
		fi
	fi

	echo "Uninstall complete."
}

main "$@"
