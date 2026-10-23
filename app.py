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
