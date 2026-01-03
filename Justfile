# Justfile for UNVT Hitchhiker server operations
# Server-side tasks for tunnel management and local development

# Cloudflare Tunnel configuration
TUNNEL_NAME := "hitchhiker"
CLOUDFLARE_CREDS_DIR := "/root/.cloudflared"

# Default target: display help
default: help

help:
	@echo "UNVT Hitchhiker server tasks:"
	@echo "  just tunnel_setup    - Authenticate with Cloudflare and create tunnel (first-time only)"
	@echo "  just tunnel          - Start the Cloudflare Tunnel (on-demand)"
	@echo "  just tunnel_stop     - Stop the Cloudflare Tunnel"
	@echo "  just verify-local    - Verify local map server is running and assets are available"
	@echo "  just logs-caddy      - View Caddy web server logs"
	@echo "  just logs-tunnel     - View Cloudflare Tunnel logs (if running)"
	@echo ""
	@echo "Note: Requires root or sudo for tunnel operations."

tunnel_setup:
	@echo "Setting up Cloudflare Tunnel for {{TUNNEL_NAME}}..."
	@echo ""
	@echo "This command will guide you through authenticating with Cloudflare and creating a tunnel."
	@echo "You will need:"
	@echo "  - A Cloudflare account (free tier is sufficient)"
	@echo "  - Access to your Cloudflare dashboard to configure DNS"
	@echo ""
	@read -p "Press Enter to continue, or Ctrl+C to cancel: " dummy
	@bash -lc 'cloudflared tunnel login' || echo "ERROR: cloudflared tunnel login failed. Is cloudflared installed?"
	@echo ""
	@echo "Creating tunnel '{{TUNNEL_NAME}}'..."
	@bash -lc 'cloudflared tunnel create {{TUNNEL_NAME}}' || echo "Tunnel may already exist."
	@echo ""
	@echo "Tunnel setup complete! Next steps:"
	@echo ""
	@echo "1. Get your tunnel credentials file:"
	@bash -lc 'ls -la {{CLOUDFLARE_CREDS_DIR}}/{{TUNNEL_NAME}}.json 2>/dev/null || echo "ERROR: Credentials not found"'
	@echo ""
	@echo "2. Run 'just tunnel' to start the tunnel"
	@echo ""
	@echo "3. Configure DNS in your Cloudflare dashboard:"
	@echo "   - Go to your domain settings"
	@echo "   - Add a CNAME record: hitchhiker.yourdomain.com CNAME <tunnel-id>.cfargotunnel.com"
	@echo "   - (The tunnel ID will be shown by 'just tunnel')"

tunnel:
	@echo "Starting Cloudflare Tunnel '{{TUNNEL_NAME}}'..."
	@bash -lc 'if [ ! -f "{{CLOUDFLARE_CREDS_DIR}}/{{TUNNEL_NAME}}.json" ]; then echo "ERROR: Tunnel credentials not found. Run \"just tunnel_setup\" first."; exit 1; fi'
	@bash -lc 'cloudflared tunnel run {{TUNNEL_NAME}} &' || echo "ERROR: Failed to start tunnel"
	@echo "Tunnel should now be running. Check status with:"
	@echo "  sudo journalctl -u cloudflared --no-pager -n 20"

tunnel_stop:
	@echo "Stopping Cloudflare Tunnel..."
	@bash -lc 'pkill -f "cloudflared tunnel run {{TUNNEL_NAME}}" && echo "Tunnel stopped." || echo "Tunnel process not found."'

# Local development: verify that map server is running
verify-local:
	@echo "Verifying local map server..."
	@curl -fsS http://127.0.0.1/ > /dev/null && echo "✓ Server responding at http://127.0.0.1/" || echo "✗ Server not responding"
	@curl -fsI http://127.0.0.1/vendor/pmtiles/pmtiles.js > /dev/null && echo "✓ PMTiles JS available" || echo "✗ PMTiles JS not found"
	@curl -fsI http://127.0.0.1/pmtiles/protomaps-sl.pmtiles > /dev/null && echo "✓ Protomaps PMTiles available" || echo "✗ Protomaps PMTiles not found"
	@curl -fsI http://127.0.0.1/pmtiles/mapterhorn-sl.pmtiles > /dev/null && echo "✓ Mapterhorn PMTiles available" || echo "✗ Mapterhorn PMTiles not found"

# View Caddy logs
logs-caddy:
	@sudo journalctl -u caddy --no-pager -n 50

# View cloudflared logs (if applicable)
logs-tunnel:
	@sudo journalctl -u cloudflared --no-pager -n 50 2>/dev/null || echo "cloudflared service not found; tunnel may be running in foreground"
