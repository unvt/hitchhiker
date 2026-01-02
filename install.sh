#!/bin/sh
set -eu

SITE_ROOT="/var/www/hitchhiker"
VENDOR_DIR="$SITE_ROOT/vendor"
PMTILES_DIR="$SITE_ROOT/pmtiles"
CADDY_SNIPPET_DIR="/etc/caddy/Caddyfile.d"
CADDY_SNIPPET_FILE="$CADDY_SNIPPET_DIR/hitchhiker.caddy"
CADDYFILE="/etc/caddy/Caddyfile"

CADDY_INSTALLED=0

is_stock_caddyfile() {
	# Detect the default Caddyfile that ships with the Debian package.
	# We only rewrite the Caddyfile when it looks like this stock template.
	[ -f "$CADDYFILE" ] || return 1
	grep -q 'The Caddyfile is an easy way to configure your Caddy web server\.' "$CADDYFILE" || return 1
	grep -qE '^[[:space:]]*:80[[:space:]]*\{' "$CADDYFILE" || return 1
	grep -qE '^[[:space:]]*root[[:space:]]+\*[[:space:]]+/usr/share/caddy[[:space:]]*$' "$CADDYFILE" || return 1
	grep -qE '^[[:space:]]*file_server([[:space:]]|$)' "$CADDYFILE" || return 1
	return 0
}

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		echo "ERROR: This installer must run as root (use sudo)." >&2
		exit 1
	fi
}

need_cmd() {
	cmd="$1"
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "ERROR: Required command not found: $cmd" >&2
		exit 1
	fi
}

ensure_packages() {
	# Minimal dependencies for downloading assets and managing services.
	# We keep this conservative; Raspberry Pi OS is Debian-based.
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	apt-get install -y ca-certificates curl
}

get_caddy_latest_tag() {
	# Returns a tag like "v2.10.2".
	# Uses GitHub API to keep "latest" behavior at install time.
	# (No jq dependency; keep it POSIX sh.)
	tag=$(curl -fsSL "https://api.github.com/repos/caddyserver/caddy/releases/latest" \
		| sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
		| head -n 1)
	if [ -z "$tag" ]; then
		echo "ERROR: Failed to determine latest Caddy release tag from GitHub API." >&2
		exit 1
	fi
	echo "$tag"
}

install_caddy_from_github_release() {
	arch=$(uname -m 2>/dev/null || echo unknown)
	case "$arch" in
		armv6l|armv6*) suffix="linux_armv6" ;;
		armv7l|armv7*) suffix="linux_armv7" ;;
		armv8l) suffix="linux_armv7" ;;
		aarch64) suffix="linux_arm64" ;;
		x86_64|amd64) suffix="linux_amd64" ;;
		*)
			echo "ERROR: Unsupported architecture for automatic Caddy install: $arch" >&2
			echo "ERROR: Please install Caddy manually, then re-run install.sh." >&2
			exit 1
			;;
	esac

	tag=$(get_caddy_latest_tag)
	ver=${tag#v}
	deb="caddy_${ver}_${suffix}.deb"
	url="https://github.com/caddyserver/caddy/releases/download/${tag}/${deb}"
	tmp="/tmp/${deb}"

	echo "Installing Caddy from GitHub release: $deb"
	curl -fsSL "$url" -o "$tmp"

	# Install the .deb (and fix up dependencies if needed)
	if ! dpkg -i "$tmp"; then
		apt-get -f install -y
	fi

	# Verify the binary runs on this CPU.
	if ! caddy version >/dev/null 2>&1; then
		echo "ERROR: Caddy was installed but failed to run on this CPU." >&2
		echo "ERROR: (This may indicate an architecture/GOARM mismatch.)" >&2
		exit 1
	fi
}

install_caddy_if_missing() {
	if command -v caddy >/dev/null 2>&1; then
		# Some builds can be present but not runnable on older ARM (Illegal instruction).
		if caddy version >/dev/null 2>&1; then
			return 0
		fi
		echo "Detected an installed Caddy that cannot run; reinstalling a compatible build..." >&2
	fi

	install_caddy_from_github_release
	CADDY_INSTALLED=1
}

ensure_site_root() {
	mkdir -p "$VENDOR_DIR/maplibre" "$VENDOR_DIR/pmtiles" "$PMTILES_DIR"

	# Create a minimal default index.html if it does not exist.
	if [ ! -f "$SITE_ROOT/index.html" ]; then
		cat > "$SITE_ROOT/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>UNVT Hitchhiker</title>
  <link rel="stylesheet" href="/vendor/maplibre/maplibre-gl.css" />
  <style>
    html, body, #map { height: 100%; margin: 0; }
    #banner { position: absolute; top: 0; left: 0; right: 0; z-index: 1; padding: 8px 10px; background: rgba(255,255,255,0.9); font: 14px/1.3 system-ui, -apple-system, sans-serif; }
    #map { position: absolute; top: 0; left: 0; right: 0; bottom: 0; }
  </style>
</head>
<body>
  <div id="banner">
    <strong>UNVT Hitchhiker</strong> — edit <code>/var/www/hitchhiker/index.html</code> and drop PMTiles into <code>/var/www/hitchhiker/pmtiles/</code>.
  </div>
  <div id="map"></div>

  <script src="/vendor/maplibre/maplibre-gl-csp.js"></script>
  <script src="/vendor/pmtiles/pmtiles.js"></script>
  <script>
    // Minimal, data-agnostic example map.
    // Replace this with your own style + sources.
    const map = new maplibregl.Map({
      container: 'map',
      style: {
        version: 8,
        sources: {
          osm: {
            type: 'raster',
            tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
            tileSize: 256,
            attribution: '© OpenStreetMap contributors'
          }
        },
        layers: [{ id: 'osm', type: 'raster', source: 'osm' }]
      },
      center: [0, 0],
      zoom: 1
    });
    map.addControl(new maplibregl.NavigationControl());

    // Hint: pmtiles.js is available globally as `pmtiles`.
    // See https://github.com/protomaps/PMTiles for usage.
  </script>
</body>
</html>
HTML
	fi

	chmod 755 "$SITE_ROOT" "$VENDOR_DIR" "$PMTILES_DIR" || true
	find "$SITE_ROOT" -type d -exec chmod 755 {} \; || true
	find "$SITE_ROOT" -type f -exec chmod 644 {} \; || true
}

download_vendor_assets() {
	echo "Downloading vendor assets (latest)..."

	# MapLibre GL JS (CSP build) + worker + CSS
	curl -fsSL "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl-csp.js" -o "$VENDOR_DIR/maplibre/maplibre-gl-csp.js"
	curl -fsSL "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl-csp-worker.js" -o "$VENDOR_DIR/maplibre/maplibre-gl-csp-worker.js"
	curl -fsSL "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl.css" -o "$VENDOR_DIR/maplibre/maplibre-gl.css"

	# pmtiles.js
	curl -fsSL "https://unpkg.com/pmtiles@latest/dist/pmtiles.js" -o "$VENDOR_DIR/pmtiles/pmtiles.js"

	chmod 644 "$VENDOR_DIR/maplibre/"* "$VENDOR_DIR/pmtiles/"* || true
}

download_remote_pmtiles() {
	echo "Attempting to download pre-extracted PMTiles from tunnel.optgeo.org (if available)..."
	for f in protomaps-sl.pmtiles mapterhorn-sl.pmtiles; do
		url="https://tunnel.optgeo.org/${f}"
		out="$PMTILES_DIR/${f}"
		if curl -fsSL "$url" -o "$out"; then
			chmod 644 "$out" || true
			echo "Downloaded ${f}"
		else
			echo "Notice: ${url} not available; skipping ${f}"
			rm -f "$out" || true
		fi
	done
}

ensure_caddy_config() {
	mkdir -p "$CADDY_SNIPPET_DIR"

	# Decide how to integrate with any existing Caddyfile.
	# - If Caddyfile is missing, or it is the stock template, replace it with an import-only file.
	#   This avoids the common :80 conflict with the stock site block.
	# - If the user already has a custom :80 site, we do NOT install a second :80 site (conflict).
	#   We fail safely with guidance.
	if [ ! -f "$CADDYFILE" ] || is_stock_caddyfile; then
		mkdir -p "$(dirname "$CADDYFILE")"
		cat > "$CADDYFILE" <<'EOF'
{
	# Global options
}

import Caddyfile.d/*.caddy
EOF
	else
		if grep -qE '^[[:space:]]*:80[[:space:]]*\{' "$CADDYFILE"; then
			echo "WARNING: /etc/caddy/Caddyfile already defines a :80 site." >&2
			echo "WARNING: To avoid conflicting configs, Hitchhiker will NOT be enabled automatically." >&2
			echo "WARNING: Options:" >&2
			echo "WARNING:  - Edit /etc/caddy/Caddyfile to serve $SITE_ROOT, or" >&2
			echo "WARNING:  - Replace it with an import-only Caddyfile that imports Caddyfile.d/*.caddy" >&2
			return 0
		fi

		if ! grep -qE '^[[:space:]]*import[[:space:]]+Caddyfile\.d/\*\.caddy[[:space:]]*$' "$CADDYFILE"; then
			echo "Adding import line to $CADDYFILE"
			printf '\nimport Caddyfile.d/*.caddy\n' >> "$CADDYFILE"
		fi
	fi

	# Write (or overwrite) the Hitchhiker site snippet.
	cat > "$CADDY_SNIPPET_FILE" <<EOF
:80 {
	root * $SITE_ROOT
	file_server
}
EOF

	# Validate config before restarting to give clearer errors.
	if command -v caddy >/dev/null 2>&1; then
		caddy validate --config "$CADDYFILE" --adapter caddyfile
	fi

	if command -v systemctl >/dev/null 2>&1; then
		systemctl daemon-reload || true
		systemctl enable caddy
		systemctl restart caddy
	else
		echo "WARNING: systemctl not found; please start Caddy manually." >&2
	fi
}

main() {
	require_root
	need_cmd id
	need_cmd apt-get

	ensure_packages
	need_cmd curl
	install_caddy_if_missing
	ensure_site_root
	download_vendor_assets
	download_remote_pmtiles
	ensure_caddy_config

	echo "Done. Try: http://$(hostname -I 2>/dev/null | awk '{print $1}')/"
}

main "$@"
