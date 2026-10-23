#!/bin/bash
# EC2 user-data: paste this into "Advanced details -> User data" when launching
# an instance (Amazon Linux 2023 or Ubuntu). It installs the app, runs it with
# gunicorn under systemd, and puts nginx in front on port 80.
set -euxo pipefail

APP_DIR=/opt/webapp

if command -v dnf >/dev/null; then
  dnf install -y python3 python3-pip nginx
  APP_USER=ec2-user
else
  apt-get update -y
  apt-get install -y python3 python3-venv python3-pip nginx
  APP_USER=ubuntu
fi

mkdir -p "$APP_DIR"

# ---- app code (keep in sync with app.py / requirements.txt) ----
cat > "$APP_DIR/requirements.txt" <<'EOF'
flask==3.0.3
gunicorn==22.0.0
EOF

cat > "$APP_DIR/app.py" <<'EOF'
"""Simple web server for EC2. Shows which instance served the request."""
import os
import socket
import urllib.request

from flask import Flask, jsonify

app = Flask(__name__)
IMDS = "http://169.254.169.254/latest"


def instance_metadata(path):
    """Read EC2 instance metadata (IMDSv2). Returns 'n/a' when not on EC2."""
    try:
        token_req = urllib.request.Request(
            f"{IMDS}/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        )
        token = urllib.request.urlopen(token_req, timeout=1).read().decode()
        req = urllib.request.Request(
            f"{IMDS}/meta-data/{path}",
            headers={"X-aws-ec2-metadata-token": token},
        )
        return urllib.request.urlopen(req, timeout=1).read().decode()
    except Exception:
        return "n/a"


@app.route("/")
def index():
    instance_id = instance_metadata("instance-id")
    az = instance_metadata("placement/availability-zone")
    return f"""<!doctype html>
<html>
<head><title>EC2 Web App</title>
<style>
  body {{ font-family: system-ui, sans-serif; background:#0f172a; color:#e2e8f0;
         display:flex; align-items:center; justify-content:center; height:100vh; margin:0; }}
  .card {{ background:#1e293b; padding:2rem 3rem; border-radius:12px; }}
  h1 {{ color:#f59e0b; margin-top:0; }}
  td {{ padding:4px 12px 4px 0; }}
</style></head>
<body><div class="card">
  <h1>Hello from EC2 🚀</h1>
  <table>
    <tr><td>Hostname</td><td>{socket.gethostname()}</td></tr>
    <tr><td>Instance ID</td><td>{instance_id}</td></tr>
    <tr><td>Availability Zone</td><td>{az}</td></tr>
    <tr><td>Environment</td><td>{os.getenv("APP_ENV", "dev")}</td></tr>
  </table>
</div></body></html>"""


@app.route("/health")
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 8080)))
EOF
# ----------------------------------------------------------------

python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

cat > /etc/systemd/system/webapp.service <<EOF
[Unit]
Description=Simple Flask web app
After=network.target

[Service]
User=$APP_USER
WorkingDirectory=$APP_DIR
Environment=APP_ENV=production
ExecStart=$APP_DIR/venv/bin/gunicorn --workers 2 --bind 127.0.0.1:8080 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/nginx/conf.d/webapp.conf <<'EOF'
server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF
# Remove distro default sites so ours is the default_server
rm -f /etc/nginx/sites-enabled/default
sed -i 's/listen\s*80 default_server;/listen 80;/; s/listen\s*\[::\]:80 default_server;/listen [::]:80;/' /etc/nginx/nginx.conf || true

systemctl daemon-reload
systemctl enable --now webapp
nginx -t
systemctl enable nginx
systemctl restart nginx
