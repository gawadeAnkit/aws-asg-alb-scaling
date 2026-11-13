#!/bin/bash
set -euxo pipefail

# Install Apache HTTP server and stress tool for CPU scaling tests
dnf update -y
dnf install -y httpd stress-ng

# Fetch instance metadata securely via IMDSv2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# Create health check endpoint for ALB Target Group
echo "OK" > /var/www/html/health

# Create dynamic landing page displaying instance identity
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="refresh" content="5" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>AWS ALB + ASG Auto-Healing &amp; Scaling Cluster</title>
  <style>
    :root {
      --bg: #0b0f19;
      --card-bg: #111827;
      --border: #1f2937;
      --text-main: #f9fafb;
      --text-muted: #9ca3af;
      --accent-blue: #38bdf8;
      --accent-green: #10b981;
      --accent-purple: #818cf8;
    }
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: var(--bg);
      color: var(--text-main);
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      margin: 0;
      padding: 20px;
    }
    .container {
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 36px;
      max-width: 640px;
      width: 100%;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
    }
    .badge-bar {
      display: flex;
      gap: 10px;
      margin-bottom: 20px;
      flex-wrap: wrap;
    }
    .badge {
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      padding: 4px 10px;
      border-radius: 9999px;
      background: rgba(56, 189, 248, 0.15);
      color: var(--accent-blue);
      border: 1px solid rgba(56, 189, 248, 0.3);
    }
    .badge-healthy {
      background: rgba(16, 185, 129, 0.15);
      color: var(--accent-green);
      border-color: rgba(16, 185, 129, 0.3);
    }
    h1 {
      font-size: 24px;
      margin: 0 0 8px 0;
      color: var(--text-main);
      font-weight: 800;
    }
    .subtitle {
      color: var(--text-muted);
      font-size: 13px;
      margin-bottom: 24px;
      line-height: 1.5;
    }
    .callout {
      background: rgba(129, 140, 248, 0.08);
      border-left: 4px solid var(--accent-purple);
      padding: 12px 16px;
      border-radius: 6px;
      font-size: 12.5px;
      color: #c7d2fe;
      margin-bottom: 24px;
      line-height: 1.4;
    }
    .matrix {
      display: flex;
      flex-direction: column;
      gap: 12px;
      margin-bottom: 24px;
    }
    .row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 16px;
      background: #1e293b;
      border: 1px solid #334155;
      border-radius: 8px;
    }
    .label {
      font-size: 12.5px;
      color: var(--text-muted);
      font-weight: 500;
    }
    .val {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 13px;
      font-weight: 700;
      color: var(--accent-green);
    }
    .footer {
      border-top: 1px solid var(--border);
      padding-top: 16px;
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 11.5px;
      color: var(--text-muted);
    }
    .pulse-dot {
      display: inline-block;
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--accent-green);
      margin-right: 6px;
      box-shadow: 0 0 10px var(--accent-green);
      animation: pulse 2s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.4; transform: scale(0.85); }
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="badge-bar">
      <span class="badge">AWS ALB + ASG</span>
      <span class="badge badge-healthy"><span class="pulse-dot"></span>Target Group: Healthy (200 OK)</span>
      <span class="badge">CPU Scaling: &gt; 70%</span>
    </div>
    <h1>High-Availability Web Cluster</h1>
    <div class="subtitle">
      Automated Elastic Auto Scaling Group behind Application Load Balancer with IMDSv2 security and self-healing replacement.
    </div>
    <div class="callout">
      <strong>DevOps Architecture:</strong> Inbound traffic dynamically routed through Multi-AZ ALB listener (:80) to Auto Scaling Group. Health check endpoint verified on <code>/health</code> every 10 seconds.
    </div>
    <div class="matrix">
      <div class="row"><span class="label">Serving EC2 Instance ID</span><span class="val">${INSTANCE_ID}</span></div>
      <div class="row"><span class="label">Availability Zone</span><span class="val">${AZ}</span></div>
      <div class="row"><span class="label">Private IPv4 Address</span><span class="val">${PRIVATE_IP}</span></div>
      <div class="row"><span class="label">Target Tracking Metric</span><span class="val">ASGAverageCPUUtilization &gt; 70%</span></div>
      <div class="row"><span class="label">Health Check Strategy</span><span class="val">ELB (Automatic Self-Healing)</span></div>
    </div>
    <div class="footer">
      <span>Candidate: <strong>Ankit Gawade</strong> (DevOps Engineer)</span>
      <span>Auto-refreshes every 5s</span>
    </div>
  </div>
</body>
</html>
EOF

systemctl enable httpd
systemctl start httpd
