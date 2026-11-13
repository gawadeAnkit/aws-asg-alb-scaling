"""
bake_golden_ami.py
Automates creation of the Production Pre-Baked Golden AMI on AWS Amazon Linux 2023
Candidate: Ankit Gawade (DevOps Engineer)
"""

import json
import subprocess
import time
import base64
import sys

REGION = "us-east-1"
BASE_AMI_PARAM = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
AMI_NAME = "devops-golden-ami-al2023-v1"
INSTANCE_TYPE = "t3.micro"
INSTANCE_PROFILE = "asg-alb-ec2-ssm-profile"

USER_DATA_SCRIPT = """#!/bin/bash
set -euxo pipefail
echo "Starting Golden AMI pre-bake..."
dnf update -y
dnf install -y httpd amazon-efs-utils stress-ng jq
systemctl enable httpd
mkdir -p /var/www/html
cat << 'EOF' > /etc/devops-golden-ami-release
DevOps Golden AMI AL2023
Role: DevOps Engineer
Candidate: Ankit Gawade
Pre-installed: httpd, amazon-efs-utils, stress-ng, jq
EOF
touch /var/log/ami-bake-complete
echo "Golden AMI pre-bake finished successfully!"
"""

def run_cmd(cmd_list):
    print(f"Executing: {' '.join(cmd_list)}")
    res = subprocess.run(cmd_list, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"ERROR: {res.stderr}")
        raise RuntimeError(f"Command failed with code {res.returncode}: {res.stderr}")
    return res.stdout.strip()

def get_existing_ami():
    out = run_cmd([
        "aws", "ec2", "describe-images",
        "--owners", "self",
        "--filters", f"Name=name,Values={AMI_NAME}", "Name=state,Values=available",
        "--region", REGION,
        "--output", "json"
    ])
    data = json.loads(out)
    images = data.get("Images", [])
    if images:
        return images[0]["ImageId"]
    return None

def main():
    print("=== Checking if Golden AMI already exists ===")
    existing_ami = get_existing_ami()
    if existing_ami:
        print(f"[FOUND] Existing Golden AMI: {existing_ami}")
        with open("golden_ami.json", "w") as f:
            json.dump({"ami_id": existing_ami, "name": AMI_NAME}, f, indent=2)
        return

    print("=== Step 1: Getting Base AL2023 AMI ===")
    base_ami = run_cmd([
        "aws", "ssm", "get-parameter",
        "--name", BASE_AMI_PARAM,
        "--region", REGION,
        "--query", "Parameter.Value",
        "--output", "text"
    ])
    print(f"Base AMI ID: {base_ami}")

    print("=== Step 2: Getting Subnet and SG ===")
    subnet_id = run_cmd([
        "aws", "ec2", "describe-subnets",
        "--region", REGION,
        "--filters", "Name=default-for-az,Values=true", "Name=availability-zone,Values=us-east-1a",
        "--query", "Subnets[0].SubnetId",
        "--output", "text"
    ])
    sg_id = run_cmd([
        "aws", "ec2", "describe-security-groups",
        "--region", REGION,
        "--filters", "Name=group-name,Values=default",
        "--query", "SecurityGroups[0].GroupId",
        "--output", "text"
    ])
    print(f"Subnet: {subnet_id}, SG: {sg_id}")

    print("=== Step 3: Launching Builder Instance ===")
    ud_b64 = base64.b64encode(USER_DATA_SCRIPT.encode("utf-8")).decode("utf-8")
    
    launch_out = run_cmd([
        "aws", "ec2", "run-instances",
        "--image-id", base_ami,
        "--instance-type", INSTANCE_TYPE,
        "--subnet-id", subnet_id,
        "--security-group-ids", sg_id,
        "--iam-instance-profile", f"Name={INSTANCE_PROFILE}",
        "--user-data", ud_b64,
        "--tag-specifications", "ResourceType=instance,Tags=[{Key=Name,Value=devops-ami-builder}]",
        "--region", REGION,
        "--output", "json"
    ])
    launch_data = json.loads(launch_out)
    builder_id = launch_data["Instances"][0]["InstanceId"]
    print(f"Builder Instance Launched: {builder_id}")

    try:
        print("=== Step 4: Waiting for instance to be running ===")
        run_cmd([
            "aws", "ec2", "wait", "instance-running",
            "--instance-ids", builder_id,
            "--region", REGION
        ])
        print("Instance is running. Waiting 75 seconds for user-data package installation to complete...")
        time.sleep(75)

        print("=== Step 5: Stopping Builder Instance for Consistent Snapshot ===")
        run_cmd([
            "aws", "ec2", "stop-instances",
            "--instance-ids", builder_id,
            "--region", REGION
        ])
        print("Waiting for instance to be stopped...")
        run_cmd([
            "aws", "ec2", "wait", "instance-stopped",
            "--instance-ids", builder_id,
            "--region", REGION
        ])
        print("Builder instance stopped successfully.")

        print("=== Step 6: Creating Golden AMI ===")
        img_out = run_cmd([
            "aws", "ec2", "create-image",
            "--instance-id", builder_id,
            "--name", AMI_NAME,
            "--description", "Production Pre-baked Golden AMI with Apache HTTPD, EFS Utils, and Stress Tools",
            "--region", REGION,
            "--output", "json"
        ])
        img_data = json.loads(img_out)
        ami_id = img_data["ImageId"]
        print(f"AMI creation initiated: {ami_id}")

        print("=== Step 7: Waiting for Golden AMI to become AVAILABLE ===")
        run_cmd([
            "aws", "ec2", "wait", "image-available",
            "--image-ids", ami_id,
            "--region", REGION
        ])
        print(f"SUCCESS: Golden AMI {ami_id} is now AVAILABLE!")

        with open("golden_ami.json", "w") as f:
            json.dump({"ami_id": ami_id, "name": AMI_NAME, "base_ami": base_ami}, f, indent=2)

    finally:
        print(f"=== Cleaning up builder instance {builder_id} ===")
        run_cmd([
            "aws", "ec2", "terminate-instances",
            "--instance-ids", builder_id,
            "--region", REGION
        ])
        print("Builder instance termination sent.")

if __name__ == "__main__":
    main()

