# Copilot instructions for UNVT Hitchhiker

This repository provides a minimal, pipe-to-shell installer/uninstaller for a static web map server on Raspberry Pi OS (Debian-based).

## Goals

- Keep the project simple and auditable (shell scripts + README).
- Prefer safe, conservative changes (do not overwrite unrelated system configuration).
- Ensure `install.sh` and `uninstall.sh` remain symmetric and predictable.

## Hard requirements

- Repository language is **English** for all documentation and user-facing output.
- **Git commit messages must be in English** for consistency and global accessibility.
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
- Use `curl -z` (timestamp-based conditional download) when re-running to optimize bandwidth.
- Keep paths and filenames stable to preserve uninstall symmetry.
- When PMTiles files are added or modified:
  - Update the download loop in `download_remote_pmtiles()`.
  - Update verification mentions in the README and Justfile `verify-local` task.

## Uninstaller (`uninstall.sh`) rules

- Must reverse `install.sh` actions and be safe:
  - Remove only `/etc/caddy/Caddyfile.d/hitchhiker.caddy`.
  - Remove only `/var/www/hitchhiker` (document clearly that this deletes local content).
  - Never remove `/var/www` itself.
  - Never remove Caddy or unrelated packages/config.
  - Clean up any old/conflicting repository configurations.
  - Clean up associated GPG keys when removing software that requires them.
- Should restart Caddy if present.
- Must remain symmetric with `install.sh` when behavior changes.

## Justfile (`Justfile`) rules

- Use standard `just` syntax; no Bash-specific features.
- **Escape sequences**: Justfile does **not** support `\n` in strings. Use actual line breaks in heredocs:
  - ✅ Correct: Use `bash -c '...<ACTUAL_NEWLINE>...'` with actual newlines
  - ❌ Wrong: `bash -lc '...\n\...'` (will fail with "not a valid escape sequence")
- Prefix task descriptions with `#` comments on the line immediately before the task name for auto-listing with `just --list`.
- Keep task output user-friendly; provide clear guidance for next steps.

## Map style (`style/protomaps-light-style.json`) rules

- All sprite and glyph references should use local paths (`/vendor/basemaps-assets/...`).
- Runtime transformation must be applied via `transformStyle` function to:
  - Absolutize relative URLs (e.g., `/vendor/basemaps-assets/sprites/...` → full URL).
  - Preserve glyph token placeholders (`{fontstack}`, `{range}`, etc.).
  - Wrap numeric expressions with `["coalesce", expr, default]` to prevent "expected number but found null" errors.
- For raster imagery layers, use zoom-based opacity interpolation for smooth fade transitions (see freetown and maxar-2020-freetown layers as examples).
- When adding new PMTiles layers:
  - Add source definition in `sources` object.
  - Add layer definition in `layers` array with appropriate `minzoom`, `paint`, and `raster-opacity` settings.
  - Update `install.sh` download loop to include the new PMTiles file.

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
