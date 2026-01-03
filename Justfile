# Justfile for UNVT Hitchhiker server operations
# Server-side tasks for tunnel management and local development

# Cloudflare Tunnel configuration
TUNNEL_NAME := "hitchhiker"
CLOUDFLARE_CREDS_DIR := "/root/.cloudflared"

# Show available tasks
default:
	@just --list

# Authenticate with Cloudflare and create tunnel (first-time setup)
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
	TUNNEL_ID := `cloudflared tunnel list | grep "{{TUNNEL_NAME}}" | awk '{print $1}' | head -n1`
	@if [ -z "{{TUNNEL_ID}}" ]; then echo "ERROR: Could not find tunnel ID"; exit 1; fi
	@mkdir -p {{CLOUDFLARE_CREDS_DIR}}
	@cat > {{CLOUDFLARE_CREDS_DIR}}/config.yml <<EOF
tunnel: {{TUNNEL_ID}}
credentials-file: {{CLOUDFLARE_CREDS_DIR}}/{{TUNNEL_ID}}.json

ingress:
  - hostname: hitchhiker.optgeo.org
    service: http://localhost:80
  - service: http_status:404
EOF
	@echo "config.yml created at {{CLOUDFLARE_CREDS_DIR}}/config.yml"
	@echo ""
	@echo "Tunnel ID: {{TUNNEL_ID}}"
	@echo "Tunnel credentials: {{CLOUDFLARE_CREDS_DIR}}/{{TUNNEL_ID}}.json"
	@echo ""
	@echo "Next steps:"
	@echo "1. Configure DNS in your Cloudflare dashboard:"
	@echo "   - Go to your domain (optgeo.org) DNS settings"
	@echo "   - Add a CNAME record:"
	@echo "     Name: hitchhiker"
	@echo "     Target: {{TUNNEL_ID}}.cfargotunnel.com"
	@echo "     Proxy status: Proxied (orange cloud)"
	@echo ""
	@echo "2. Run \"just tunnel\" to start the tunnel"
	@echo "3. Access your map at https://hitchhiker.optgeo.org"
# Start Cloudflare Tunnel in background
tunnel:
	@echo "Starting Cloudflare Tunnel '{{TUNNEL_NAME}}'..."
	@bash -lc 'if [ ! -f "{{CLOUDFLARE_CREDS_DIR}}/config.yml" ]; then echo "ERROR: config.yml not found. Run \"just tunnel_setup\" first."; exit 1; fi'
	@bash -lc 'cloudflared tunnel --config {{CLOUDFLARE_CREDS_DIR}}/config.yml run &' || echo "ERROR: Failed to start tunnel"
	@echo "Tunnel started in background. Your map should be accessible at:"
	@echo "  https://hitchhiker.optgeo.org"
	@echo ""
	@echo "Check tunnel status with:"
	@echo "  just logs-tunnel"

# Stop running Cloudflare Tunnel
tunnel_stop:
	@echo "Stopping Cloudflare Tunnel..."
	@bash -lc 'pkill -f "cloudflared tunnel.*{{TUNNEL_NAME}}" && echo "Tunnel stopped." || echo "Tunnel process not found."'

# Show tunnel configuration and running status
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

# View Cloudflare Tunnel logs
logs-tunnel:
	@sudo journalctl -u cloudflared --no-pager -n 50 2>/dev/null || echo "cloudflared service not found; tunnel may be running in foreground"

# Install systemd service for persistent tunnel
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

# Remove systemd service for tunnel
tunnel_systemd_uninstall:
	@echo "Removing systemd service for Cloudflare Tunnel..."
	@sudo systemctl stop cloudflared 2>/dev/null || true
	@sudo systemctl disable cloudflared 2>/dev/null || true
	@sudo rm -f /etc/systemd/system/cloudflared.service
	@sudo systemctl daemon-reload
	@echo "Systemd service removed."

