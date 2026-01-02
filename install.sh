#!/bin/sh
set -eu

# Environment knobs:
#  - HITCHHIKER_HOST: host to configure for Caddy (TLS only when explicitly set)
#  - HITCHHIKER_PROGRESS: progress display for downloads: auto|always|never
#    - auto: show progress only on TTY (default)
#    - always: always show curl progress
#    - never: never show progress
HITCHHIKER_PROGRESS=${HITCHHIKER_PROGRESS:-auto}

# Simple logging helpers
info() { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# download_file <url> <out>
# Uses HITCHHIKER_PROGRESS and respects TTY when set to auto.
download_file() {
	url=$1
	out=$2

	case "${HITCHHIKER_PROGRESS:-auto}" in
		always)
			CURL_OPTS="-fSL -#"
			;;
		never)
			CURL_OPTS="-fsSL"
			;;
		*)
			if [ -t 2 ]; then
				CURL_OPTS="-fSL -#"
			else
				CURL_OPTS="-fsSL"
			fi
			;;
	esac

	if curl $CURL_OPTS -o "$out" "$url"; then
		chmod 644 "$out" || true
		info "Downloaded $(basename "$out")"
		return 0
	else
		warn "failed to download ${url}; skipping $(basename "$out")"
		rm -f "$out" || true
		return 1
	fi
}

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

verify_pmtiles_protocol() {
	echo "Verifying local HTTP server and PMTiles assets (best-effort)"
	if ! command -v curl >/dev/null 2>&1; then
		echo "Notice: curl not available; skipping verification"
		return 0
	fi

	# Check local HTTP server
	if ! curl -fsS http://127.0.0.1/ >/dev/null 2>&1; then
		echo "Warning: local HTTP server did not respond at http://127.0.0.1/." >&2
		echo "If Caddy is not running, start it (systemctl start caddy) or inspect /var/log/syslog." >&2
		return 0
	fi

	# Fetch vendor pmtiles.js via HTTP and look for expected hints
	if [ -f "$VENDOR_DIR/pmtiles/pmtiles.js" ]; then
		tmpf="/tmp/hitch_pmtiles.js"
		if curl -fsS http://127.0.0.1/vendor/pmtiles/pmtiles.js -o "$tmpf"; then
			if grep -qE 'maplibre|registerProtocol|pmtiles' "$tmpf"; then
				echo "pmtiles.js served and contains MapLibre/pmtiles integration hints"
			else
				echo "Notice: pmtiles.js served but did not contain expected keywords; it may be a different build"
			fi
			rm -f "$tmpf" || true
		else
			echo "Warning: failed to fetch /vendor/pmtiles/pmtiles.js from local server" >&2
		fi
	else
		echo "Notice: $VENDOR_DIR/pmtiles/pmtiles.js not present on disk; vendor download may have failed" >&2
	fi

	# Verify that any downloaded PMTiles are being served
	for f in protomaps-sl.pmtiles mapterhorn-sl.pmtiles; do
		if [ -f "$PMTILES_DIR/$f" ]; then
			if curl -fsI "http://127.0.0.1/pmtiles/$f" >/dev/null 2>&1; then
				echo "PMTiles $f is accessible at /pmtiles/$f"
			else
				echo "Warning: $f exists on disk but is not accessible at /pmtiles/$f" >&2
			fi
		fi
	done
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
	<title>UNVT Hitchhiker — Offline Map</title>
	<link rel="stylesheet" href="/vendor/maplibre/maplibre-gl.css" />
	<style>
		html, body, #map { height: 100%; margin: 0; }
		#banner { position: absolute; top: 0; left: 0; right: 0; z-index: 2; padding: 8px 10px; background: rgba(255,255,255,0.9); font: 14px/1.3 system-ui, -apple-system, sans-serif; }
		#map { position: absolute; top: 0; left: 0; right: 0; bottom: 0; }
		.notice { font-size: 12px; color: #444; }
	</style>
</head>
<body>
	<div id="banner">
		<strong>UNVT Hitchhiker</strong> — Offline map using local PMTiles.
		<div class="notice">Edit /var/www/hitchhiker/style/protomaps-light/style.json to customize.</div>
	</div>
	<div id="map"></div>

	<script src="/vendor/pmtiles/pmtiles.js"></script>
	<script src="/vendor/maplibre/maplibre-gl.js"></script>
	<script>
		(async function() {
			// Register pmtiles protocol per MapLibre example:
			// const protocol = new pmtiles.Protocol();
			// maplibregl.addProtocol('pmtiles', protocol.tile);
			// PMTiles registration must succeed — fail loudly if not available.
			const PM = window.pmtiles || window.PMTiles;
			if (!PM || typeof PM.Protocol !== 'function') {
				console.error('FATAL: PMTiles plugin not found or Protocol constructor missing; cannot continue.');
				return; // stop initialization
			}
			// Instantiate protocol and register; allow exceptions to surface (fatal)
			const protocol = new PM.Protocol();
			if (!window.maplibregl || typeof maplibregl.addProtocol !== 'function') {
				console.error('FATAL: maplibregl.addProtocol not available; cannot register pmtiles protocol.');
				return;
			}
			maplibregl.addProtocol('pmtiles', protocol.tile);
			console.log('pmtiles protocol registered via maplibregl.addProtocol');

			// Load the offline style (bundled by installer) with improved diagnostics.
			let style = null;
			try {
				const resp = await fetch('/style/protomaps-light/style.json');
				if (!resp.ok) {
					const txt = await resp.text().catch(() => '<unreadable response>');
					console.error('Failed to fetch style.json:', resp.status, txt);
					style = { version: 8, sources: {}, layers: [] };
				} else {
					try {
						style = await resp.json();
					} catch (e) {
						const txt = await resp.text().catch(() => '<unreadable response>');
						console.error('Style JSON parse failed:', e, txt);
						style = { version: 8, sources: {}, layers: [] };
					}
				}
			} catch (e) {
				console.error('Failed to load style.json:', e);
				style = { version: 8, sources: {}, layers: [] };
			}

			// Create the map with the loaded style.
			// Prefer a non-CSP worker if available (installer places it at /vendor/maplibre/maplibre-gl-worker.js).
			// If that file is missing, MapLibre will use its default worker loading behavior.
			maplibregl.workerUrl = '/vendor/maplibre/maplibre-gl-worker.js';
			const map = new maplibregl.Map({
				container: 'map',
				style: style,
				hash: 'map',
				center: [-11.5, 8.5],
				zoom: 7
			});
			map.addControl(new maplibregl.NavigationControl());

			// If you want to add 3D lighting or hillshade, extend the style.json with
			// sources referencing /pmtiles/mapterhorn-sl.pmtiles and vector layers from protomaps.
			// The installer places the style under /style/protomaps-light/style.json.
		})();
	</script>
</body>
</html>
HTML
	fi

	# Ensure ownership and permissions suitable for a webserver user.
	# Prefer the 'caddy' group (used by the Caddy package); fall back to 'www-data' or root.
	if getent group caddy >/dev/null 2>&1; then
		WEBGROUP=caddy
	elif getent group www-data >/dev/null 2>&1; then
		WEBGROUP=www-data
	else
		WEBGROUP=root
	fi

	# Make root the owner and the chosen web group the group owner so Caddy can read files.
	# Prefer making the local user 'hitchhiker' the owner so the device admin can edit files
	if id -u hitchhiker >/dev/null 2>&1; then
		SITE_OWNER=hitchhiker
	else
		SITE_OWNER=root
	fi
	chown -R "$SITE_OWNER":"$WEBGROUP" "$SITE_ROOT" || true

	# Standard static-site permissions: dirs 755, files 644.
	find "$SITE_ROOT" -type d -exec chmod 755 {} \; || true
	find "$SITE_ROOT" -type f -exec chmod 644 {} \; || true
}

download_vendor_assets() {
	echo "Downloading vendor assets (latest)..."

	# MapLibre GL JS: prefer non-CSP build (simpler worker loading). Fall back to CSP build if non-CSP not available.
	if curl -fsSL -o "$VENDOR_DIR/maplibre/maplibre-gl.js" "https://cdn.jsdelivr.net/npm/maplibre-gl/dist/maplibre-gl.js"; then
		echo "Downloaded non-CSP maplibre-gl.js"
		# Try to fetch a corresponding worker; not all CDN builds expose a separate worker file.
		if curl -fsSL -o "$VENDOR_DIR/maplibre/maplibre-gl-worker.js" "https://cdn.jsdelivr.net/npm/maplibre-gl/dist/maplibre-gl-worker.js"; then
			echo "Downloaded maplibre-gl-worker.js"
		else
			echo "Notice: maplibre-gl-worker.js not available on CDN; client will use default worker loading behavior"
			rm -f "$VENDOR_DIR/maplibre/maplibre-gl-worker.js" || true
		fi
		curl -fsSL -o "$VENDOR_DIR/maplibre/maplibre-gl.css" "https://cdn.jsdelivr.net/npm/maplibre-gl/dist/maplibre-gl.css" || true
	else
		# Fallback: CSP distribution
		curl -fsSL "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl-csp.js" -o "$VENDOR_DIR/maplibre/maplibre-gl-csp.js"
		curl -fsSL "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl-csp-worker.js" -o "$VENDOR_DIR/maplibre/maplibre-gl-csp-worker.js"
		curl -fsSL "https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl.css" -o "$VENDOR_DIR/maplibre/maplibre-gl.css"
	fi

	# pmtiles.js
	curl -fsSL "https://unpkg.com/pmtiles@latest/dist/pmtiles.js" -o "$VENDOR_DIR/pmtiles/pmtiles.js"

	chmod 644 "$VENDOR_DIR/maplibre/"* "$VENDOR_DIR/pmtiles/"* || true
}

download_remote_pmtiles() {
	echo "Attempting to download pre-extracted PMTiles from tunnel.optgeo.org (if available)..."
	for f in protomaps-sl.pmtiles mapterhorn-sl.pmtiles; do
		url="https://tunnel.optgeo.org/${f}"
		out="$PMTILES_DIR/${f}"
		# Skip download if file already exists to save bandwidth; remove this file to force re-download.
		if [ -f "$out" ]; then
			echo "Found existing ${f}; skipping download. Remove it to re-download."
			continue
		fi

		# Light reachability check (HEAD).
		if ! curl -fsI "$url" >/dev/null 2>&1; then
			echo "Notice: ${url} not reachable; skipping ${f}"
			continue
		fi

		# Use the shared download helper (respects HITCHHIKER_PROGRESS)
		if download_file "$url" "$out"; then
			:
		fi

		done

}
download_protomaps_style() {
	# Place offline style and minimal assets under the site root so the device can operate offline.
	STYLE_DIR="$SITE_ROOT/style/protomaps-light"
	mkdir -p "$STYLE_DIR"

	# If a packaged style exists in the repo, copy it; otherwise attempt to download a canonical one.
	if [ -f "$(pwd)/style/protomaps-light-style.json" ]; then
		cp "$(pwd)/style/protomaps-light-style.json" "$STYLE_DIR/style.json" || true
		chmod 644 "$STYLE_DIR/style.json" || true
		echo "Installed local protomaps light style to $STYLE_DIR/style.json"
		return 0
	fi

	# Fallback: try to download a style (best-effort).
	STYLE_URLS=
	STYLE_URLS="https://raw.githubusercontent.com/protomaps/basemaps-flavors/main/light/style.json https://maps.protomaps.com/styles/light.json"
	for u in $STYLE_URLS; do
		if curl -fsSL "$u" -o "$STYLE_DIR/style.json"; then
			chmod 644 "$STYLE_DIR/style.json" || true
			echo "Downloaded style.json from $u"
			return 0
		fi
	done

	# Try fetching the bundled style from this repo (when installer is run via curl|sh)
	REPO_RAW="https://raw.githubusercontent.com/unvt/hitchhiker/main/style/protomaps-light-style.json"
	if curl -fsSL "$REPO_RAW" -o "$STYLE_DIR/style.json"; then
		chmod 644 "$STYLE_DIR/style.json" || true
		echo "Downloaded bundled style.json from repository"
		return 0
	fi

	echo "Notice: could not obtain a protomaps light style.json; using bundled minimal style if present."
}

download_style_assets() {
	echo "Installing style assets (sprites & glyphs)..."
	STYLE_DIR="$SITE_ROOT/style/protomaps-light"
	mkdir -p "$STYLE_DIR/sprites" "$STYLE_DIR/glyphs"

	# If repository includes packaged sprites, prefer those.
	if [ -f "$(pwd)/style/protomaps-sprite.json" ] && [ -f "$(pwd)/style/protomaps-sprite.png" ]; then
		cp "$(pwd)/style/protomaps-sprite.json" "$STYLE_DIR/sprites/sprite.json" || true
		cp "$(pwd)/style/protomaps-sprite.png" "$STYLE_DIR/sprites/sprite.png" || true
		echo "Installed packaged sprites to $STYLE_DIR/sprites/"
	else
		# Try to fetch packaged sprites from the repository raw URLs (best-effort)
		SPR_JSON_RAW="https://raw.githubusercontent.com/unvt/hitchhiker/main/style/protomaps-sprite.json"
		SPR_PNG_RAW="https://raw.githubusercontent.com/unvt/hitchhiker/main/style/protomaps-sprite.png"
		if curl -fsSL "$SPR_JSON_RAW" -o "$STYLE_DIR/sprites/sprite.json"; then
			curl -fsSL "$SPR_PNG_RAW" -o "$STYLE_DIR/sprites/sprite.png" || true
			echo "Downloaded sprites from repository"
		fi
	fi

	# Attempt to discover a "sprite" entry in the installed style.json and download it if remote.
	if [ -f "$STYLE_DIR/style.json" ]; then
		sprite_url=$(sed -n 's/.*"sprite"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STYLE_DIR/style.json" | head -n1 || true)
		if [ -n "$sprite_url" ]; then
			case "$sprite_url" in
				http*)
					if curl -fsSL "${sprite_url}.json" -o "$STYLE_DIR/sprites/sprite.json"; then
						curl -fsSL "${sprite_url}.png" -o "$STYLE_DIR/sprites/sprite.png" || true
						echo "Downloaded sprites from $sprite_url"
					fi
					;;
				/*)
					echo "Sprite referenced as local path; ensure files exist under $STYLE_DIR"
					;;
			esac
		fi

		# Inspect glyphs configuration -- prefetching all ranges is expensive; only warn.
		glyphs_url=$(sed -n 's/.*"glyphs"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STYLE_DIR/style.json" | head -n1 || true)
		if [ -n "$glyphs_url" ]; then
			case "$glyphs_url" in
				http*)
					echo "Notice: style requests remote glyphs ($glyphs_url). Installer will not prefetch all ranges." >&2
					echo "Tip: add pre-generated glyph PBFs under $STYLE_DIR/glyphs/ if you need fully-offline fonts." >&2
					;;
				/*)
					echo "Glyphs reference local path; ensure PBF ranges exist under $glyphs_url"
					;;
			esac
		fi
	fi

	chmod -R 644 "$STYLE_DIR" || true
}

finalize_site_permissions() {
	# Recompute preferred owner/group (in case files were created after initial chown)
	if getent group caddy >/dev/null 2>&1; then
		WEBGROUP=caddy
	elif getent group www-data >/dev/null 2>&1; then
		WEBGROUP=www-data
	else
		WEBGROUP=root
	fi

	if id -u hitchhiker >/dev/null 2>&1; then
		SITE_OWNER=hitchhiker
	else
		SITE_OWNER=root
	fi

	echo "Applying final ownership: $SITE_OWNER:$WEBGROUP and standard perms under $SITE_ROOT"
	chown -R "$SITE_OWNER":"$WEBGROUP" "$SITE_ROOT" || true

	# Dirs 755, files 644, ensure pmtiles and vendor dirs readable by web group
	find "$SITE_ROOT" -type d -exec chmod 755 {} \; || true
	find "$SITE_ROOT" -type f -exec chmod 644 {} \; || true

	# Ensure pmtiles files are readable by group (some systems respect ACLs differently)
	if [ -d "$PMTILES_DIR" ]; then
		find "$PMTILES_DIR" -type f -exec chmod 644 {} \; || true
	fi

	# Ensure vendor JS/CSS are readable
	if [ -d "$VENDOR_DIR" ]; then
		find "$VENDOR_DIR" -type f -exec chmod 644 {} \; || true
	fi
}

ensure_caddy_config() {
	mkdir -p "$CADDY_SNIPPET_DIR"

	# Default host name for local reference; do NOT enable TLS unless the
	# user explicitly set HITCHHIKER_HOST. This avoids Caddy attempting ACME
	# certificate issuance for the bare default name which is not a public
	# resolvable hostname.
	HOST=${HITCHHIKER_HOST:-hitchhiker}

	# Detect whether HITCHHIKER_HOST was provided by the user (set vs unset).
	# POSIX-safe check: the expansion ${VAR+set} yields 'set' when VAR is set.
	if [ "${HITCHHIKER_HOST+set}" = "set" ] && [ -n "${HITCHHIKER_HOST}" ]; then
		ENABLE_TLS=1
	else
		ENABLE_TLS=0
	fi

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

	# Write (or overwrite) the Hitchhiker site snippet. TLS is enabled only
	# when the user explicitly provided HITCHHIKER_HOST (ENABLE_TLS=1).
	if [ "$ENABLE_TLS" -eq 1 ]; then
		cat > "$CADDY_SNIPPET_FILE" <<EOF
$HOST {
	root * $SITE_ROOT
	file_server
	}
EOF
		echo "Configured Caddy site for host: $HOST (Caddy will attempt automatic HTTPS)."
	else
		cat > "$CADDY_SNIPPET_FILE" <<EOF
:80 {
	root * $SITE_ROOT
	file_server
}
EOF
		echo "Configured Caddy site on :80 (HTTP only)."
		if [ "$HOST" != "hitchhiker" ]; then
			echo "Note: HITCHHIKER_HOST set to '$HOST' but TLS was not enabled because the variable was not explicitly provided." >&2 || true
		fi
		echo "To enable automatic HTTPS, re-run with HITCHHIKER_HOST=your.domain" 
	fi

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
	download_protomaps_style
	download_style_assets
	# Ensure final ownership/permissions after downloads to avoid manual fixes
	finalize_site_permissions
	ensure_caddy_config
	# Best-effort verification that the site serves assets and pmtiles.js
	verify_pmtiles_protocol

	echo "Done. Try: http://$(hostname -I 2>/dev/null | awk '{print $1}')/"
}

main "$@"
