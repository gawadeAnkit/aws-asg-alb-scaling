#!/bin/bash
set -euxo pipefail

# DevOps Web Cluster Bootstrap Script
# Candidate: Ankit Gawade (DevOps Engineer)
# Multi-AZ EFS Shared Storage + Custom Golden AMI + Dynamic Telemetry

echo "=== Initializing Cluster Node ==="

# 1. Fetch IMDSv2 metadata securely
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

EFS_FS_ID="${efs_id}"
ASSETS_BUCKET="${assets_bucket}"
REGION="${aws_region}"

echo "Node Identity: $INSTANCE_ID | AZ: $AZ | IP: $PRIVATE_IP | EFS: $EFS_FS_ID"

# 2. Mount Amazon EFS Shared Storage to /var/www/html
mkdir -p /var/www/html

MOUNTED=0
for i in {1..30}; do
  if mountpoint -q /var/www/html; then
    echo "EFS already mounted at /var/www/html"
    MOUNTED=1
    break
  fi
  
  echo "Attempting EFS mount (attempt $i/30)..."
  if mount -t efs -o tls,iam $EFS_FS_ID:/ /var/www/html; then
    echo "Successfully mounted EFS with TLS and IAM auth."
    MOUNTED=1
    break
  elif mount -t efs -o tls $EFS_FS_ID:/ /var/www/html; then
    echo "Successfully mounted EFS with TLS."
    MOUNTED=1
    break
  fi
  sleep 4
done

if [ $MOUNTED -eq 0 ]; then
  echo "WARNING: EFS mount timed out, falling back to local storage"
fi

# 3. Synchronize Web Assets to Shared Storage (First node populates, shared to all)
if [ ! -f /var/www/html/index.html ]; then
  echo "Seeding shared website assets from S3 bucket: $ASSETS_BUCKET..."
  aws s3 sync s3://$ASSETS_BUCKET/website/ /var/www/html/ --region $REGION
fi

# Ensure health check endpoint exists
echo "OK" > /var/www/html/health
chmod -R 755 /var/www/html

# 4. Configure Instance-Specific Node Telemetry via Apache Alias
mkdir -p /var/www/node
cat <<EOF > /var/www/node/node-info.json
{
  "instance_id": "$INSTANCE_ID",
  "az": "$AZ",
  "availability_zone": "$AZ",
  "private_ip": "$PRIVATE_IP",
  "efs_id": "$EFS_FS_ID",
  "status": "Healthy (Auto-Healing Enabled)",
  "scaling_policy": "Target Tracking CPU > 70%",
  "storage_type": "Amazon EFS Multi-AZ Shared NFS (/var/www/html)",
  "ami_type": "DevOps Golden AMI AL2023",
  "candidate": "Ankit Gawade",
  "role": "DevOps Engineer"
}
EOF
chmod 644 /var/www/node/node-info.json

# 5. Apache Alias Configuration for Node Telemetry
cat <<'EOF' > /etc/httpd/conf.d/node-telemetry.conf
Alias /node-info.json /var/www/node/node-info.json
<Directory /var/www/node>
    Options None
    AllowOverride None
    Require all granted
</Directory>
EOF

# 6. Ensure Apache is started and enabled
systemctl restart httpd
systemctl enable httpd
echo "Cluster Node Initialization Complete!"
