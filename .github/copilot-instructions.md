# Copilot instructions for UNVT Hitchhiker

This repository provides a minimal, pipe-to-shell installer/uninstaller for a static web map server on Raspberry Pi OS (Debian-based).

## Goals

- Keep the project simple and auditable (shell scripts + README).
- Prefer safe, conservative changes (do not overwrite unrelated system configuration).
- Ensure `install.sh` and `uninstall.sh` remain symmetric and predictable.

## Hard requirements

- Repository language is **English** for all documentation and user-facing output.
- Default document root is `/var/www/hitchhiker`.
- Default web serving is **HTTP on port 80**.
- Vendor assets are installed locally under `/var/www/hitchhiker/vendor/`.
- MapLibre GL JS and pmtiles.js are fetched using UNPKG `@latest` unless explicitly changed.
- Installer must require root (expect users to run via `sudo`).

## Installer (`install.sh`) rules

- Must be **idempotent**: safe to run multiple times.
- Must be **conservative** with Caddy:
  - Write only a dedicated snippet to `/etc/caddy/Caddyfile.d/hitchhiker.caddy`.
  - Add `import Caddyfile.d/*.caddy` to `/etc/caddy/Caddyfile` only if missing.
  - Do not delete or rewrite unrelated Caddy configuration.
- Use Debian package manager (`apt-get`) and minimal dependencies.
- Use `curl -fsSL` for downloads; fail hard on errors.
- Keep paths and filenames stable to preserve uninstall symmetry.

## Uninstaller (`uninstall.sh`) rules

- Must reverse `install.sh` actions and be safe:
  - Remove only `/etc/caddy/Caddyfile.d/hitchhiker.caddy`.
  - Remove only `/var/www/hitchhiker` (document clearly that this deletes local content).
  - Never remove `/var/www` itself.
  - Never remove Caddy or unrelated packages/config.
- Should restart Caddy if present.

## Documentation (`README.md`) rules

- Keep instructions realistic:
  - Use GitHub Pages URLs (`https://unvt.github.io/hitchhiker/...`).
  - Mention `sudo` requirement.
  - Explain the trade-off of `@latest` vs pinned versions.
  - Explain GeoLocation API secure-context limitation and pragmatic workarounds.

## Style and safety

- Shell must be POSIX `sh` compatible; avoid Bash-only features.
- Keep scripts readable and small; no unnecessary abstractions.
- Avoid adding extra features (TLS automation, AP setup, complex UI) unless explicitly requested.
- When changing behavior, update README and keep install/uninstall in sync.
