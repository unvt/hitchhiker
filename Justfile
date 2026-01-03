# Justfile for UNVT Hitchhiker server operations
# Server-side tasks for tunnel management and local development

# Cloudflare Tunnel configuration
TUNNEL_NAME := "hitchhiker"
CLOUDFLARE_CREDS_DIR := "/root/.cloudflared"

# Default target: display help
default: help

help:
	@echo "UNVT Hitchhiker server tasks:"
	@echo "  just tunnel_setup              - Authenticate with Cloudflare and create tunnel (first-time only)"
	@echo "  just tunnel                    - Start the Cloudflare Tunnel (on-demand)"
	@echo "  just tunnel_stop               - Stop the Cloudflare Tunnel"
	@echo "  just tunnel_info               - Show tunnel configuration and status"
	@echo "  just tunnel_systemd_install    - (Optional) Install systemd service for persistent tunnel"
	@echo "  just tunnel_systemd_uninstall  - Remove systemd service"
	@echo "  just verify-local              - Verify local map server is running and assets are available"
	@echo "  just logs-caddy                - View Caddy web server logs"
	@echo "  just logs-tunnel               - View Cloudflare Tunnel logs (if running)"
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
	@echo "Generating config.yml..."
	@bash -lc 'TUNNEL_ID=$$(cloudflared tunnel list | grep "{{TUNNEL_NAME}}" | awk "{print \$$1}" | head -n1); \
		if [ -z "$$TUNNEL_ID" ]; then echo "ERROR: Could not find tunnel ID"; exit 1; fi; \
		mkdir -p {{CLOUDFLARE_CREDS_DIR}}; \
		cat > {{CLOUDFLARE_CREDS_DIR}}/config.yml <<EOF\n\
tunnel: $$TUNNEL_ID\n\
credentials-file: {{CLOUDFLARE_CREDS_DIR}}/$$TUNNEL_ID.json\n\
\n\
ingress:\n\
  - hostname: hitchhiker.optgeo.org\n\
    service: http://localhost:80\n\
  - service: http_status:404\n\
EOF\n\
		echo "config.yml created at {{CLOUDFLARE_CREDS_DIR}}/config.yml"; \
		echo ""; \
		echo "Tunnel ID: $$TUNNEL_ID"; \
		echo "Tunnel credentials: {{CLOUDFLARE_CREDS_DIR}}/$$TUNNEL_ID.json"; \
		echo ""; \
		echo "Next steps:"; \
		echo "1. Configure DNS in your Cloudflare dashboard:"; \
		echo "   - Go to your domain (optgeo.org) DNS settings"; \
		echo "   - Add a CNAME record:"; \
		echo "     Name: hitchhiker"; \
		echo "     Target: $$TUNNEL_ID.cfargotunnel.com"; \
		echo "     Proxy status: Proxied (orange cloud)"; \
		echo ""; \
		echo "2. Run \"just tunnel\" to start the tunnel"; \
		echo "3. Access your map at https://hitchhiker.optgeo.org"'

tunnel:
	@echo "Starting Cloudflare Tunnel '{{TUNNEL_NAME}}'..."
	@bash -lc 'if [ ! -f "{{CLOUDFLARE_CREDS_DIR}}/config.yml" ]; then echo "ERROR: config.yml not found. Run \"just tunnel_setup\" first."; exit 1; fi'
	@bash -lc 'cloudflared tunnel --config {{CLOUDFLARE_CREDS_DIR}}/config.yml run &' || echo "ERROR: Failed to start tunnel"
	@echo "Tunnel started in background. Your map should be accessible at:"
	@echo "  https://hitchhiker.optgeo.org"
	@echo ""
	@echo "Check tunnel status with:"
	@echo "  just logs-tunnel"

tunnel_stop:
	@echo "Stopping Cloudflare Tunnel..."
	@bash -lc 'pkill -f "cloudflared tunnel.*{{TUNNEL_NAME}}" && echo "Tunnel stopped." || echo "Tunnel process not found."'

tunnel_info:
	@echo "Cloudflare Tunnel Information:"
	@echo "=============================="
	@bash -lc 'if [ -f "{{CLOUDFLARE_CREDS_DIR}}/config.yml" ]; then \
		TUNNEL_ID=$$(grep "^tunnel:" {{CLOUDFLARE_CREDS_DIR}}/config.yml | awk "{print \$$2}"); \
		echo "Tunnel Name: {{TUNNEL_NAME}}"; \
		echo "Tunnel ID: $$TUNNEL_ID"; \
		echo "Public URL: https://hitchhiker.optgeo.org"; \
		echo "CNAME Target: $$TUNNEL_ID.cfargotunnel.com"; \
		echo "Config: {{CLOUDFLARE_CREDS_DIR}}/config.yml"; \
		echo "Credentials: {{CLOUDFLARE_CREDS_DIR}}/$$TUNNEL_ID.json"; \
		echo ""; \
		echo "Tunnel status:"; \
		pgrep -f "cloudflared tunnel" > /dev/null && echo "  ✓ Running" || echo "  ✗ Not running (use \"just tunnel\" to start)"; \
	else \
		echo "Tunnel not configured. Run \"just tunnel_setup\" to create."; \
	fi'

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

# Optional: Create systemd service for persistent tunnel (always-on)
tunnel_systemd_install:
	@echo "Creating systemd service for persistent Cloudflare Tunnel..."
	@bash -lc 'if [ ! -f "{{CLOUDFLARE_CREDS_DIR}}/config.yml" ]; then echo "ERROR: config.yml not found. Run \"just tunnel_setup\" first."; exit 1; fi'
	@sudo bash -c 'cat > /etc/systemd/system/cloudflared.service <<'\''EOF'\'' \
	[Unit] \
	Description=Cloudflare Tunnel \
	After=network.target \
	 \
	[Service] \
	Type=simple \
	ExecStart=/usr/bin/cloudflared tunnel --config {{CLOUDFLARE_CREDS_DIR}}/config.yml run \
	Restart=on-failure \
	RestartSec=5s \
	 \
	[Install] \
	WantedBy=multi-user.target \
	EOF'
	@sudo systemctl daemon-reload
	@sudo systemctl enable cloudflared
	@echo "Systemd service created. Start with:"
	@echo "  sudo systemctl start cloudflared"
	@echo "  sudo systemctl status cloudflared"

tunnel_systemd_uninstall:
	@echo "Removing systemd service for Cloudflare Tunnel..."
	@sudo systemctl stop cloudflared 2>/dev/null || true
	@sudo systemctl disable cloudflared 2>/dev/null || true
	@sudo rm -f /etc/systemd/system/cloudflared.service
	@sudo systemctl daemon-reload
	@echo "Systemd service removed."

