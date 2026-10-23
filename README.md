# Simple EC2 Web App

A small Flask app that shows the hostname, instance ID and AZ of the EC2 instance that served the request. Behind a load balancer, each refresh can show a different instance.

| Path      | What it returns                      |
|-----------|--------------------------------------|
| `/`       | HTML page with instance details      |
| `/health` | `{"status":"ok"}` for ALB health checks |

## Run locally

```bash
pip install -r requirements.txt
python app.py        # http://localhost:8080
```

## Deploy to EC2 (user data)

1. EC2 → Launch instance → **Amazon Linux 2023** or **Ubuntu**, t2.micro/t3.micro.
2. Security group: allow inbound **HTTP (80)** from anywhere, and **SSH (22)** from your IP.
3. Advanced details → **User data**: paste the whole contents of `user-data.sh`.
4. Launch, wait 2–3 minutes, then open `http://<public-ip>/`.

The script installs Python and nginx, puts the app in `/opt/webapp`, runs it with gunicorn as a systemd service (`webapp`) on 127.0.0.1:8080, and has nginx forward port 80 to it.

## Useful commands on the instance

```bash
sudo systemctl status webapp
sudo journalctl -u webapp -f
sudo tail -f /var/log/cloud-init-output.log   # user-data output
```

## Multiple instances + load balancer

Put the same user data in a Launch Template, create an Auto Scaling Group with it, and attach an Application Load Balancer target group using health check path `/health`.
