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

```sh
curl -fsSL https://unvt.github.io/hitchhiker/install.sh | less
```

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

Caddy configuration strategy (conservative + uninstallable):
- A site snippet is written to `/etc/caddy/Caddyfile.d/hitchhiker.caddy`
- The main `/etc/caddy/Caddyfile` is updated only to add an `import Caddyfile.d/*.caddy` line if it is missing

This keeps Hitchhiker configuration isolated and easy to remove.

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
