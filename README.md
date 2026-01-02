# UNVT Hitchhiker

A portable, low-power web map server that “hitches a ride” on your personal hotspot.

UNVT Hitchhiker is a lightweight UNVT Portable-style setup for serving static web maps (HTML/CSS/JS + PMTiles) from small devices such as Raspberry Pi Zero-class hardware.

This repository is intentionally simple:
- A shell installer served via GitHub Pages
- A matching uninstaller
- A static document root under `/var/www/hitchhiker`

## Status

This project is under active construction. The installer aims to be:
- Practical on a fresh Raspberry Pi OS Lite installation
- Idempotent (safe to re-run)
- Conservative (does not aggressively overwrite existing Caddy configs)

## Supported Environment

- OS: Raspberry Pi OS (Debian-based). Target: Raspberry Pi OS Lite (32-bit)
- Internet access during installation (to download packages and JS assets)
- Privileges: root is required (writes to `/var`, `/etc`, uses `systemctl`)

## Install

The installer is hosted on GitHub Pages (repository root):

```sh
curl -fsSL https://unvt.github.io/hitchhiker/install.sh | sudo sh
```

Notes:
- `sudo` is required.
- If you do not trust pipe-to-shell, inspect first:

 download pre-extracted PMTiles into `/var/www/hitchhiker/pmtiles/` (if found at the example tunnel URLs),
curl -fsSL https://unvt.github.io/hitchhiker/install.sh | less
```

## Terrain / DEM requirements

If you enable terrain (3D elevation) in the shipped style, follow these requirements so MapLibre can consume the DEM correctly:

- **PMTiles file location:** the default style expects a DEM PMTiles named `mapterhorn-sl.pmtiles` served from `/pmtiles/` on the device. The installer will attempt to download example files into `/var/www/hitchhiker/pmtiles/` if they are available on the configured tunnel host.
- **Encoding:** DEM tiles must use the *terrarium* encoding (the style sets `encoding: "terrarium"`).
- **Tile size:** the style is configured for 512px tiles (`"tileSize": 512`); your PMTiles must contain 512px terrarium tiles or MapLibre will misinterpret elevation values.
- **Max zoom:** the style limits DEM requests to `maxzoom: 13` to avoid requesting very high-resolution elevation tiles. Only increase this if your PMTiles include higher zoom levels and you accept the storage and bandwidth costs.

Ensure your PMTiles generation/extraction workflow produces 512px terrarium PNG tiles up to the desired zoom. If you require reproducible installer behavior, pin vendor versions as noted in the "MapLibre GL JS and pmtiles.js (How We Fetch \"Latest\")" section.

## Uninstall

Uninstall removes the Hitchhiker document root and the Hitchhiker Caddy site snippet.
If you have PMTiles data you want to keep, back it up first.

```sh
curl -fsSL https://unvt.github.io/hitchhiker/uninstall.sh | sudo sh
```

## What Gets Installed (Filesystem)

Document root:

```
/var/www/hitchhiker
├── index.html
├── vendor/
│   ├── maplibre/
│   │   ├── maplibre-gl-csp.js
│   │   ├── maplibre-gl-csp-worker.js
│   │   └── maplibre-gl.css
│   └── pmtiles/
│       └── pmtiles.js
└── pmtiles/
    └── (your .pmtiles files)
```

Why `/var/www/hitchhiker`?
- It matches common Debian conventions (and avoids inventing a new top-level under `/var`).

Why not `/var/www` directly?
- On Debian/Raspberry Pi OS, `/var/www` is commonly shared by other web content (often `/var/www/html`). Using a dedicated subdirectory avoids accidental conflicts.
- It makes uninstall safer: removing `/var/www/hitchhiker` is predictable, whereas “uninstalling” from `/var/www` risks deleting unrelated files.

If you still want the absolute simplest layout (`/var/www` as the site root), you can do it, but Hitchhiker’s installer/uninstaller should then be more conservative (delete only the specific files it created, and never remove `/var/www` itself).

## Web Server (Caddy)

The installer installs Caddy (if missing) and configures Hitchhiker as an HTTP site on port 80.

Note on GeoLocation API:
- Most browsers require a “secure context” for `navigator.geolocation` (HTTPS or `localhost`).
- If you need geolocation in the browser while keeping Hitchhiker simple, common options are:
    - Use an SSH tunnel and access via `http://localhost:PORT` (secure-context exception for localhost).
    - Temporarily allow an insecure origin in your browser for development/testing.
        - Switch Hitchhiker to HTTPS with a locally-trusted certificate (more setup; not the default).

Enabling automatic HTTPS (HITCHHIKER_HOST)
----------------------------------------

Hitchhiker keeps TLS disabled by default to avoid accidental ACME requests for non-public names. The installer sets a sensible default hostname of `hitchhiker` for local reference, but Caddy will only attempt automatic HTTPS when you explicitly provide a public hostname via the `HITCHHIKER_HOST` environment variable.

Examples:

- Download and run the installer interactively (recommended) and enable TLS by setting `HITCHHIKER_HOST` when invoking the script with `sudo`:

```sh
curl -fsSL -o install.sh https://unvt.github.io/hitchhiker/install.sh
HITCHHIKER_HOST=example.com sudo sh install.sh
```

- Or, download first and inspect before running (safer):

```sh
curl -fsSL -o install.sh https://unvt.github.io/hitchhiker/install.sh
less install.sh    # verify contents
HITCHHIKER_HOST=example.com sudo sh install.sh
```

Important notes when enabling TLS:

- `example.com` must resolve to the device's public IP address (DNS A/AAAA record), and port 80/443 must be reachable for ACME (HTTP-01) validation.
- If the device is behind NAT or a carrier grade NAT, automatic certificate issuance will likely fail unless you configure port forwarding or use a publicly routable host.
- If you only need local HTTPS for development, consider creating a locally-trusted certificate or use a hostname mapped in `/etc/hosts` and import a local CA into your devices — automatic ACME issuance requires a publicly routable name.
- If you change `HITCHHIKER_HOST` later, re-run the installer to update the Caddy snippet (it is idempotent).

If you do not set `HITCHHIKER_HOST`, Hitchhiker remains an HTTP site on `:80` and the built-in default hostname `hitchhiker` is only useful as a local label (no certificates are requested).

Self-signed HTTPS (local testing)
---------------------------------

If you need HTTPS for local features like the Geolocation API but cannot use a public hostname, the installer can generate a self-signed certificate and configure Caddy to use it. This will enable HTTPS, but browsers will treat the certificate as untrusted until you import it into the client device's trust store.

- To enable self-signed cert generation at install time, set these environment variables when running the installer:

```sh
HITCHHIKER_HOST=hitchhiker.local HITCHHIKER_SELF_SIGN=1 sudo sh install.sh
```

- The installer will place the generated cert at `/etc/caddy/ssl/<HITCHHIKER_HOST>.crt` and key at `/etc/caddy/ssl/<HITCHHIKER_HOST>.key` and configure Caddy to use them.
- You must import the `.crt` into the client device's trust store (browser/OS) to avoid security warnings and to allow `navigator.geolocation` to work. On macOS, double-click the `.crt` and add it to the System keychain, then mark it as trusted for SSL. On Android/iOS you can import the cert into the device's trust store (procedures differ by OS/version).
- Note: self-signed certs are suitable for local testing and development. For public deployments prefer a real CA-signed certificate (set `HITCHHIKER_HOST` to a publicly resolvable name and allow Caddy to manage ACME certificates).

## PMTiles Extraction & Upload (macOS host)

If you want a small, device-friendly PMTiles file that covers Sierra Leone, perform the extraction on a more powerful machine (your macOS "mother ship") and upload the resulting files to a tunnel host so the Pi can download them during install.

Recommended bounding box (safe margin):

```
-13.5,6.5,-9.9,10.3
```

Example workflow (macOS, `pmtiles` binary installed):

1. Create an `extracts/` directory in the repository and run `pmtiles extract` against a planet build (adjust source URLs as needed):

```sh
pmtiles extract https://r2-public.protomaps.com/protomaps-sample-datasets/planet.pmtiles \
    extracts/protomaps-sl.pmtiles --bbox=-13.5,6.5,-9.9,10.3 --maxzoom=12

pmtiles extract https://download.mapterhorn.com/planet.pmtiles \
    extracts/mapterhorn-sl.pmtiles --bbox=-13.5,6.5,-9.9,10.3 --maxzoom=12
```

2. Upload the extracted files to your tunnel host. Use `rsync` with `--progress` to preserve/verify transfer and show progress:

```sh
rsync -av --progress extracts/protomaps-sl.pmtiles pod@pod.local:/home/pod/x-24b/data/
rsync -av --progress extracts/mapterhorn-sl.pmtiles pod@pod.local:/home/pod/x-24b/data/
```

After upload, example public URLs might be:

- https://tunnel.optgeo.org/protomaps-sl.pmtiles
- https://tunnel.optgeo.org/mapterhorn-sl.pmtiles

3. During `install.sh`, the installer will attempt to download those files into `/var/www/hitchhiker/pmtiles/` if they exist at the example URLs. This avoids heavy extraction on the Pi and keeps your microSD usage low.

Notes:
- `--maxzoom=12` is a reasonable compromise for country-level extracts; each additional zoom level roughly doubles the file size. Reduce `--maxzoom` to save space.
- Adjust the source URLs if you maintain your own mirror or use a different daily-build endpoint.
- The repository `.gitignore` is configured to exclude `extracts/*.pmtiles` to avoid checking large binary files into Git.

Offline style and assets
------------------------

The installer also attempts to install a local style and assets so the device can render maps offline. During `install.sh` the installer will:

- download pre-extracted PMTiles into `/var/www/hitchhiker/pmtiles/` (if found at the example tunnel URLs),
- install a local Protomaps "light" style into `/var/www/hitchhiker/style/protomaps-light/style.json` (prefers a bundled file in the repo), and
- leave sprites/glyphs references in the style.json pointing to local paths so the device does not require network access at runtime.

The included `style/protomaps-light-style.json` is a minimal, offline-friendly style that references the local `protomaps-sl.pmtiles` and `mapterhorn-sl.pmtiles` files. You can customize or replace it with a fuller Protomaps flavor before running the installer.

Verification & quick tests
-------------------------

After running `install.sh`, verify the site and assets with these best-effort checks (run on the device, or from a host that can reach it):

```sh
# Replace <IP> with the device IP shown by the installer, or use 127.0.0.1 on-device.
curl -fsS http://<IP>/ | sed -n '1,20p'
curl -fsI http://<IP>/vendor/pmtiles/pmtiles.js
curl -fsI http://<IP>/pmtiles/protomaps-sl.pmtiles
curl -fsI http://<IP>/pmtiles/mapterhorn-sl.pmtiles
# If Caddy appears down, restart and view logs:
sudo systemctl restart caddy
sudo journalctl -u caddy --no-pager -n 50
```

Open a browser to `http://<IP>/` to confirm the map loads. If the default style.json is missing assets, edit `/var/www/hitchhiker/style/protomaps-light/style.json` to point to locally-installed sprites/glyphs.

Caddy configuration strategy (conservative + uninstallable):
- A site snippet is written to `/etc/caddy/Caddyfile.d/hitchhiker.caddy`
- The main `/etc/caddy/Caddyfile` is updated only to add an `import Caddyfile.d/*.caddy` line if it is missing

This keeps Hitchhiker configuration isolated and easy to remove.

If you already have a custom Caddy configuration on `:80`, Hitchhiker will avoid making conflicting changes. In that case, you may need to manually point your existing `:80` site to `/var/www/hitchhiker`.

## MapLibre GL JS and pmtiles.js (How We Fetch “Latest”)

Hitchhiker installs MapLibre GL JS and pmtiles.js as static vendor assets so the device can serve everything locally.

Current approach:
- Download from UNPKG using the `@latest` tag
- Place files under `/var/www/hitchhiker/vendor/...`

Files fetched:
- `https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl-csp.js`
- `https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl-csp-worker.js`
- `https://unpkg.com/maplibre-gl@latest/dist/maplibre-gl.css`
- `https://unpkg.com/pmtiles@latest/dist/pmtiles.js`

Trade-offs:
- Pros: simple, no build step, always pulls a current stable release
- Cons: not perfectly reproducible over time (because “latest” moves)

If you need reproducibility, pin versions inside `install.sh` (e.g. `maplibre-gl@5.15.0`, `pmtiles@4.3.2`).

## Adding Your PMTiles

Copy your `.pmtiles` into:

```
/var/www/hitchhiker/pmtiles/
```

The default `index.html` is a minimal template intended to be edited for your own style and data.

## Relationship to UNVT Portable

UNVT Hitchhiker is a valid UNVT Portable-style implementation focused on:
- Static-by-default web maps
- Personal connectivity (hotspot) instead of infrastructure ownership
- Low-power operation

It intentionally does not:
- Run its own access point
- Provide heavyweight GIS backends
- Target high-availability production deployments

## License

CC0 1.0 Universal (Public Domain Dedication)
