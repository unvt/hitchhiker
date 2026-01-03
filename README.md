# UNVT Hitchhiker

A portable, low-power web map server that “hitches a ride” on your personal hotspot.

UNVT Hitchhiker is a lightweight UNVT Portable-style setup for serving static web maps (HTML/CSS/JS + PMTiles) from small devices such as Raspberry Pi Zero-class hardware.

This repository is intentionally simple:
- A shell installer served via GitHub Pages
- A matching uninstaller
- A static document root under `/var/www/hitchhiker`
## Table of Contents

- [Status](#status)
- [Supported Environment](#supported-environment)
- [Install](#install)
- [Terrain / DEM Requirements](#terrain--dem-requirements)
- [Uninstall](#uninstall)
- [What Gets Installed](#what-gets-installed-filesystem)
- [Web Server (Caddy)](#web-server-caddy)
  - [Enabling Automatic HTTPS](#enabling-automatic-https-hitchhiker_host)
  - [Self-signed HTTPS](#self-signed-https-local-testing)
- [Cloudflare Tunnel (Internet Exposure)](#cloudflare-tunnel-internet-exposure-via-tunneloptgeoorg)
- [PMTiles Extraction & Upload](#pmtiles-extraction--upload-macos-host)
- [Offline Style and Assets](#offline-style-and-assets)
- [Verification & Quick Tests](#verification--quick-tests)
- [MapLibre GL JS and pmtiles.js](#maplibre-gl-js-and-pmtilesjs-how-we-fetch-latest)
- [Adding Your PMTiles](#adding-your-pmtiles)
- [Architecture & Philosophy](#architecture--philosophy-distributed-and-forward-deployed-web-maps)
- [Relationship to UNVT Portable](#relationship-to-unvt-portable)
- [Acknowledgments](#acknowledgments)
- [License](#license)
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

**Basic installation (local HTTP server only):**

```sh
curl -fsSL https://unvt.github.io/hitchhiker/install.sh | sudo sh
```

**With Cloudflare Tunnel support (optional, for internet exposure):**

```sh
curl -fsSL https://unvt.github.io/hitchhiker/install.sh | \
  sudo HITCHHIKER_CLOUDFLARE=1 sh
```

This installs `cloudflared` and the management `Justfile` for tunnel operations. See [Cloudflare Tunnel](#cloudflare-tunnel-internet-exposure) section below for setup instructions.

**Notes:**
- `sudo` is required.
- If you do not trust pipe-to-shell, inspect first:

```sh
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

Server management:

```
/home/hitchhiker/
├── Justfile          # Tasks for tunnel management, verification, and logs
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

Cloudflare Tunnel (Internet Exposure via tunnel.optgeo.org)
-----------------------------------------------------------

Hitchhiker can optionally expose your map server to the internet via Cloudflare Tunnel (`cloudflared`). This is useful for:
- Sharing your maps with remote collaborators
- Testing geolocation and HTTPS-dependent browser features
- Accessing your device without port forwarding or DNS setup

**How it works:**
1. `cloudflared` creates an authenticated tunnel from your device to Cloudflare's edge network
2. A public CNAME record (e.g., `hitchhiker.optgeo.org`) points to the tunnel
3. Cloudflare handles HTTPS and certificate management automatically
4. Your device remains offline-capable; the tunnel is optional and can be stopped at any time

**Setup and usage:**

1. **First time only:** Create a tunnel identity and authenticate:

```sh
cd /home/hitchhiker
just tunnel_setup
```

This command will:
- Prompt you for your Cloudflare account credentials (or token)
- Guide you through creating a tunnel named `hitchhiker`
- Auto-generate `/root/.cloudflared/config.yml` with ingress rules (maps `hitchhiker.optgeo.org` → `http://localhost:80`)
- Display detailed DNS CNAME setup instructions (copy-paste ready)

2. **Configure DNS CNAME (in Cloudflare dashboard):**

After running `tunnel_setup`, you'll see output like:

```
Add this DNS record in Cloudflare:
  Type: CNAME
  Name: hitchhiker
  Target: abc123-xyz.cfargotunnel.com
```

Go to your Cloudflare domain's DNS settings and create the CNAME record. This maps your public URL (`hitchhiker.optgeo.org`) to the tunnel.

3. **Start the tunnel (on-demand):**

```sh
cd /home/hitchhiker
just tunnel
```

This runs `cloudflared tunnel --config /root/.cloudflared/config.yml run` in the background, exposing your device at `https://hitchhiker.optgeo.org`.

4. **Check tunnel status:**

```sh
cd /home/hitchhiker
just tunnel_info
```

This displays tunnel ID, public URL, CNAME target, and whether the tunnel is currently running.

5. **Stop the tunnel:**

```sh
cd /home/hitchhiker
just tunnel_stop
```

6. **(Optional) Make tunnel persistent with systemd:**

For always-on tunneling across reboots:

```sh
cd /home/hitchhiker
just tunnel_systemd_install
sudo systemctl start cloudflared
sudo systemctl status cloudflared
```

To remove the systemd service:

```sh
cd /home/hitchhiker
just tunnel_systemd_uninstall
```

7. **View available tasks:**

```sh
cd /home/hitchhiker
just
# or
just --list
```

**Configuration:**
- Tunnel credentials and config are stored under `/root/.cloudflared/` and are persistent across reboots.
- The tunnel name is fixed as `hitchhiker` for simplicity.
- `config.yml` is auto-generated by `tunnel_setup` with ingress rules mapping your public URL to `localhost:80`.

**Important notes:**
- The tunnel is **optional**: your device works perfectly offline even if you never set it up.
- Tunneling adds a small latency (routing through Cloudflare edge), but is ideal for remote testing and collaboration.
- By default, the tunnel runs on-demand (manual start/stop). Use `tunnel_systemd_install` for persistent operation.
- If you need to revoke the tunnel, delete `/root/.cloudflared/` and create a new one via `tunnel_setup`.

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
- https://tunnel.optgeo.org/freetown_2025-10-22_nearest.pmtiles (optional high-resolution imagery layer)

3. During `install.sh`, the installer will attempt to download those files into `/var/www/hitchhiker/pmtiles/` if they exist at the example URLs. This avoids heavy extraction on the Pi and keeps your microSD usage low. If a file is already present locally and the remote copy is not newer, the download is skipped (using `curl -z` timestamp comparison).

Notes:
- `--maxzoom=12` is a reasonable compromise for country-level extracts; each additional zoom level roughly doubles the file size. Reduce `--maxzoom` to save space.
- Adjust the source URLs if you maintain your own mirror or use a different daily-build endpoint.
- The repository `.gitignore` is configured to exclude `extracts/*.pmtiles` to avoid checking large binary files into Git.

## Offline Style and Assets

The installer also attempts to install a local style and assets so the device can render maps offline. During `install.sh` the installer will:

- download pre-extracted PMTiles into `/var/www/hitchhiker/pmtiles/` (if found at the example tunnel URLs),
- install a local Protomaps "light" style with terrain and optional high-resolution imagery layers, and
- leave sprites/glyphs references in the style.json pointing to local paths so the device does not require network access at runtime.

The included `style/protomaps-light-style.json` is an offline-friendly style that references:
- `protomaps-sl.pmtiles` (vector basemap)
- `mapterhorn-sl.pmtiles` (DEM raster with multidirectional hillshading)
- `freetown_2025-10-22_nearest.pmtiles` (optional: high-resolution imagery layer, fades in at zoom 13-15 while hillshade fades out)

You can customize or replace the style before running the installer.

## Verification & Quick Tests

After running `install.sh`, verify the site and assets with these best-effort checks (run on the device, or from a host that can reach it):

```sh
# Replace <IP> with the device IP shown by the installer, or use 127.0.0.1 on-device.
curl -fsS http://<IP>/ | sed -n '1,20p'
curl -fsI http://<IP>/vendor/pmtiles/pmtiles.js
curl -fsI http://<IP>/pmtiles/protomaps-sl.pmtiles
curl -fsI http://<IP>/pmtiles/mapterhorn-sl.pmtiles
curl -fsI http://<IP>/pmtiles/freetown_2025-10-22_nearest.pmtiles
# If Caddy appears down, restart and view logs:
sudo systemctl restart caddy
sudo journalctl -u caddy --no-pager -n 50
```

Open a browser to `http://<IP>/` to confirm the map loads. If the default style.json is missing assets, edit `/var/www/hitchhiker/style/protomaps-light/style.json` to point to locally-installed sprites/glyphs.

**Caddy configuration strategy (conservative + uninstallable):**
- A site snippet is written to `/etc/caddy/Caddyfile.d/hitchhiker.caddy`
- The main `/etc/caddy/Caddyfile` is updated only to add an `import Caddyfile.d/*.caddy` line if it is missing

This keeps Hitchhiker configuration isolated and easy to remove. If you already have a custom Caddy configuration on `:80`, Hitchhiker will avoid making conflicting changes. In that case, you may need to manually point your existing `:80` site to `/var/www/hitchhiker`.

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

## Architecture & Philosophy: Distributed and Forward-Deployed Web Maps

UNVT Hitchhiker represents a pragmatic step forward in distributed geospatial data serving, combining three key principles:

**1. Offline-first and local autonomy**
- Web maps do not require a central server or constant internet connectivity.
- All essential data (vector tiles, raster terrain, imagery, stylesheets, glyphs, sprites) are bundled and served locally.
- A device can operate independently from the internet after installation, supporting disconnected or intermittent connectivity scenarios.

**2. Low-power and low-footprint deployment**
- Designed for Raspberry Pi Zero and similar single-board computers (not just cloud VMs).
- No heavy GIS servers, databases, or processing pipelines.
- Minimal dependencies: shell scripts, static web assets, and a lightweight HTTP server (Caddy).

**3. Forward deployment (edge hosting)**
- Web maps can be served from the field, car, boat, or disaster site without relying on infrastructure.
- Data moves toward the edge rather than centralizing in a single cloud endpoint.
- Supports peer-to-peer or broadcast scenarios where a single device shares data with multiple clients via a personal hotspot.

**Why "Hitchhiker"?**
Hitchhiker implies *traveling light* and *moving fast*. A single small device carries everything needed and can deploy its own map server anywhere with a power supply and optional internet access for setup. The map "hitches a ride" on your hotspot, making it available to any client on the network.

This approach complements the UNVT Portable framework by enabling truly offline, low-power, and field-operable web map infrastructure.

## Relationship to UNVT Portable

UNVT Hitchhiker is a valid UNVT Portable-style implementation focused on:
- Static-by-default web maps
- Personal connectivity (hotspot) instead of infrastructure ownership
- Low-power operation

It intentionally does not:
- Run its own access point
- Provide heavyweight GIS backends
- Target high-availability production deployments

## Acknowledgments

This project is built on the shoulders of many open-source and open-data initiatives:

### Map Data and Tiles

- **[Protomaps Basemaps](https://github.com/protomaps/basemaps)** - Vector basemap tiles derived from [OpenStreetMap](https://www.openstreetmap.org/) data. © OpenStreetMap contributors. Map data licensed under [ODbL](https://opendatacommons.org/licenses/odbl/).

- **[Mapterhorn](https://mapterhorn.com/)** - Open terrain tiles project by [Leichter als Luft GmbH](https://leichteralsluft.ch/). Made possible through support from the NGI0 Core Fund, established by [NLnet](https://nlnet.nl/) with financial support from the European Commission's [Next Generation Internet](https://ngi.eu/) programme. Terrain data sources are documented at [mapterhorn.com/attribution](https://mapterhorn.com/attribution). Code: BSD-3 License.

- **[OpenAerialMap](https://openaerialmap.org/)** - Freetown high-resolution imagery (2025-10-22, 4cm resolution) provided by [DroneTM](https://dronetm.com/) via OpenAerialMap. Captured with DJI Mini 4 Pro. Licensed under [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/). Made with ♥ by [HOT](https://www.hotosm.org/) partners and community.

### Software and Libraries

- **[MapLibre GL JS](https://maplibre.org/)** - Open-source map rendering library (BSD-3 License)
- **[PMTiles](https://github.com/protomaps/PMTiles)** - Cloud-optimized tile archive format by Protomaps (BSD-3 License)
- **[Caddy](https://caddyserver.com/)** - Modern web server with automatic HTTPS (Apache 2.0 License)
- **[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/)** (cloudflared) - Secure tunnel service for internet exposure
- **[just](https://github.com/casey/just)** - Command runner for task automation (CC0 License)

### Data Hosting

- **tunnel.optgeo.org** - Tile hosting and distribution infrastructure provided by optgeo for example deployments and testing

### Foundation

Built on Debian-based [Raspberry Pi OS](https://www.raspberrypi.com/software/) for low-power, forward-deployed mapping infrastructure.

## License

CC0 1.0 Universal (Public Domain Dedication)
