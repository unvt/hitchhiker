# Justfile for UNVT Hitchhiker server operations
# Minimal tasks for local verification and logs

default:
	@just --list

# Verify local map server and PMTiles assets
verify-local:
	@echo "Verifying local map server..."
	@curl -fsS http://127.0.0.1/ > /dev/null && echo "✓ Server responding at http://127.0.0.1/" || echo "✗ Server not responding"
	@curl -fsI http://127.0.0.1/vendor/pmtiles/pmtiles.js > /dev/null && echo "✓ PMTiles JS available" || echo "✗ PMTiles JS not found"
	@curl -fsI http://127.0.0.1/pmtiles/protomaps-sl.pmtiles > /dev/null && echo "✓ Protomaps PMTiles available" || echo "✗ Protomaps PMTiles not found"
	@curl -fsI http://127.0.0.1/pmtiles/mapterhorn-sl.pmtiles > /dev/null && echo "✓ Mapterhorn PMTiles available" || echo "✗ Mapterhorn PMTiles not found"

# View Caddy web server logs
logs-caddy:
	@sudo journalctl -u caddy --no-pager -n 50

