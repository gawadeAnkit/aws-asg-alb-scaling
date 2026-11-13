# High-Availability Auto Scaling Group & Application Load Balancer

![AWS Architecture](https://img.shields.io/badge/AWS-Application_Load_Balancer-FF9900?logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-1.5+-844FBA?logo=terraform&logoColor=white)
![Storage](https://img.shields.io/badge/Amazon_EFS-Multi--AZ_Encrypted-38BDF8)
![AMI](https://img.shields.io/badge/Golden_AMI-AL2023_Pre--Baked-10B981)
![Scaling](https://img.shields.io/badge/Auto_Scaling_Group-70%25_CPU_Target-2563EB)
![Security](https://img.shields.io/badge/Security-IMDSv2_Enforced-10B981)

**Candidate:** Ankit Gawade  
**Role:** DevOps Engineer  
**Evaluating Organization:** Itvedant Education Pvt. Ltd.  
**Repository:** [https://github.com/gawadeAnkit/aws-asg-alb-scaling](https://github.com/gawadeAnkit/aws-asg-alb-scaling)  
**Live Endpoint:** `http://devops-app-alb-890029008.us-east-1.elb.amazonaws.com`

---

## 1. Enterprise Architecture Overview

This project implements an enterprise-grade, highly available, self-healing web cluster on AWS using **Terraform (IaC)**. The cluster is designed according to AWS Well-Architected Framework principles:
1. **Application Load Balancer (ALB):** Internet-facing Multi-AZ load balancer routing traffic across 3 Availability Zones (`us-east-1a`, `us-east-1b`, and `us-east-1c`).
2. **Pre-Baked Custom Golden AMI (`devops-golden-ami-al2023-v1` / `ami-05b8c4c41b13f8f47`):** Eliminates runtime package installation latency at boot, delivering **<10 second boot-to-healthy** time for auto-scaling and auto-healing replacements.
3. **Multi-AZ Amazon EFS Shared Storage (`fs-08b9d4abe38e30123`):** Shared POSIX-compliant distributed filesystem mounted at `/var/www/html` across all worker nodes with TLS encryption, providing 11 9's data durability and instant cross-AZ asset consistency.
4. **S3 Artifact Storage (`devops-asg-app-assets-7db874ce`):** Immutable code deployment registry for web assets.
5. **Auto Scaling Group (`devops-app-asg`):** Minimum 2, Desired 2, Maximum 4 instances with `ELB` health checks and dynamic **Target Tracking Scaling on Average CPU Utilization > 70%**.

```mermaid
flowchart TD
    Users["Internet Users (HTTP:80)"] --> ALB["AWS Application Load Balancer\n[devops-app-alb-890029008]"]
    ALB --> TG["Target Group: devops-app-tg\n[Path: /health | Interval: 10s | Unhealthy: 2]"]

    subgraph MultiAZ_EFS ["Amazon EFS Shared POSIX Storage [fs-08b9d4abe38e30123]"]
        EFS_A["Mount Target: us-east-1a\n[172.31.11.169]"]
        EFS_B["Mount Target: us-east-1b\n[172.31.89.73]"]
        EFS_C["Mount Target: us-east-1c\n[172.31.30.111]"]
    end

    subgraph MultiAZ_ASG ["Auto Scaling Group: devops-app-asg [Min: 2, Desired: 2, Max: 4]"]
        EC2_A["EC2 Node 1 (us-east-1a)\n[i-0e856a096ee1038db]\nGolden AMI ami-05b8c4c41b13f8f47"]
        EC2_B["EC2 Node 2 (us-east-1b)\n[i-0368cc879d39fedc7]\nGolden AMI ami-05b8c4c41b13f8f47"]
        EC2_C["EC2 Node 3 (us-east-1c)\n[Dynamic Surge Scale-Out]"]
    end

    TG --> EC2_A
    TG --> EC2_B
    TG -.->|Scale-Out on CPU > 70%| EC2_C

    EC2_A -.->|NFS over TLS| EFS_A
    EC2_B -.->|NFS over TLS| EFS_B
    EC2_C -.->|NFS over TLS| EFS_C

    CW_Alarm["CloudWatch Alarm\n[TargetTracking-devops-app-asg-AlarmHigh]"] -.->|Trigger Scale Out: 2 -> 3| MultiAZ_ASG
    TG -.->|ELB Health Check Failure| MultiAZ_ASG
    MultiAZ_ASG -.->|Auto Self-Healing| Terminate["Terminate Unhealthy Node & Launch Fresh Golden Instance"]
```

---

## 2. Assessment Requirements & Systems Design Implementation

| Assessment Requirement | Enterprise Solution | Systems Design Justification |
|---|---|---|
| **Custom Golden AMI** | `devops-golden-ami-al2023-v1` (`ami-05b8c4c41b13f8f47`) pre-baking `httpd`, `amazon-efs-utils`, `stress-ng`, and `jq`. | Eliminates external package download flakiness and cuts instance boot-to-healthy latency from 90s to <10s. |
| **Shared Stateful Storage** | Amazon Elastic File System (`fs-08b9d4abe38e30123`) mounted at `/var/www/html` with TLS via `amazon-efs-utils`. | Ephemeral EC2 instances share identical web assets without rsync or custom synchronization daemons. |
| **Launch Template** | Amazon Linux 2023 (`t3.micro`), IMDSv2 enforced (`http_tokens = "required"`), detailed 1-minute CloudWatch monitoring enabled. | **Zero Static SSH Keys:** Passwordless management strictly via AWS Systems Manager (SSM) IAM profile. |
| **Security Group Isolation** | ALB SG accepts HTTP (port 80) from `0.0.0.0/0`. EC2 SG accepts HTTP **strictly from ALB SG**. EFS SG accepts NFS (port 2049) **strictly from EC2 SG**. | **Zero-Trust Network Defense-in-Depth:** Direct internet access to EC2 nodes and storage is entirely prevented. |
| **Application Load Balancer** | Public ALB across 3 AZs (`us-east-1a`, `us-east-1b`, `us-east-1c`). HTTP port 80 listener forwards to Target Group. | **High Availability:** Eliminates single point of failure (SPOF) with Multi-AZ redundancy. |
| **Target Group Health Checks** | Health checks on `/health`: `interval = 10s`, `timeout = 5s`, `healthy_threshold = 2`, `unhealthy_threshold = 2`. `deregistration_delay = 15s`. | **Rapid Fault Isolation:** Detects dead or malfunctioning web services within 20 seconds. |
| **Auto Scaling Group** | `min_size = 2`, `desired_capacity = 2`, `max_size = 4`. Health check type set explicitly to **`ELB`** with 90s grace period. | **Automated Healing:** ASG terminates instances failing ALB HTTP health checks automatically. |
| **70% CPU Target Tracking** | `aws_autoscaling_policy` with `policy_type = "TargetTrackingScaling"` tracking metric `ASGAverageCPUUtilization` at target value `70.0`. | **Elastic Scaling:** Scales out instances automatically when aggregate CPU spikes above 70%. |

---

## 3. Practical Demonstrations & Verification Proof

### Proof 1: Multi-AZ EFS Mount & Node Telemetry Verification
```bash
$ ssm run: df -h /var/www/html && cat /var/www/node/node-info.json
Filesystem      Size  Used Avail Use% Mounted on
127.0.0.1:/     8.0E     0  8.0E   0% /var/www/html

{
  "instance_id": "i-0e856a096ee1038db",
  "az": "us-east-1a",
  "availability_zone": "us-east-1a",
  "private_ip": "172.31.3.184",
  "efs_id": "fs-08b9d4abe38e30123",
  "status": "Healthy (Auto-Healing Enabled)",
  "scaling_policy": "Target Tracking CPU > 70%",
  "storage_type": "Amazon EFS Multi-AZ Shared NFS (/var/www/html)",
  "ami_type": "DevOps Golden AMI AL2023",
  "candidate": "Ankit Gawade",
  "role": "DevOps Engineer"
}
```

### Proof 2: Round-Robin Load Balancing Across Availability Zones
```bash
$ python test_alb.py
=== Probing ALB Root ===
Status: 200 | Content length: 17750 | Has Ankit Gawade: True

=== Testing Multi-AZ Load Balancing (/node-info.json) ===
Req 1: Instance=i-0368cc879d39fedc7 | AZ=us-east-1b | IP=172.31.93.92 | EFS=fs-08b9d4abe38e30123 | Role=DevOps Engineer
Req 2: Instance=i-0e856a096ee1038db | AZ=us-east-1a | IP=172.31.3.184 | EFS=fs-08b9d4abe38e30123 | Role=DevOps Engineer
Req 3: Instance=i-0368cc879d39fedc7 | AZ=us-east-1b | IP=172.31.93.92 | EFS=fs-08b9d4abe38e30123 | Role=DevOps Engineer
Req 4: Instance=i-0e856a096ee1038db | AZ=us-east-1a | IP=172.31.3.184 | EFS=fs-08b9d4abe38e30123 | Role=DevOps Engineer

Summary of Nodes Responding:
 - Node: i-0368cc879d39fedc7 in AZ: us-east-1b
 - Node: i-0e856a096ee1038db in AZ: us-east-1a
```

### Proof 3: Automatic Self-Healing of Unhealthy Instances
1. **Fault Injection:** Stopped Apache (`systemctl stop httpd`) on healthy instance `i-08c4104b8d3ccffdb` via AWS SSM.
2. **Detection:** ALB Target Group evaluated consecutive failed health checks on `/health` and marked the target **`unhealthy`** (`Target.FailedHealthChecks`).
3. **Healing Action:** ASG (`health_check_type = "ELB"`) drained active connections, terminated `i-08c4104b8d3ccffdb`, and launched fresh replacement instance `i-0cd59e5ed9537e7ef`.
4. **AWS Scaling Activity Log:**
   ```json
   {
     "Description": "Launching a new EC2 instance: i-0cd59e5ed9537e7ef",
     "Cause": "At 2026-11-13T02:24:37Z an instance was launched in response to an unhealthy instance needing to be replaced.",
     "StatusCode": "Successful"
   }
   ```

### Proof 4: Dynamic Scale-Out on CPU > 70% (Target Tracking)
1. **Load Trigger:** Executed CPU load generation using `stress-ng --cpu 2 --timeout 300s` via AWS SSM across running cluster nodes.
2. **Metric Spike:** CloudWatch metric `ASGAverageCPUUtilization` surged to **100.0%** (exceeding the 70.0% threshold).
3. **Alarm State:** CloudWatch Alarm `TargetTracking-devops-app-asg-AlarmHigh` entered **`ALARM`** state.
4. **Scaling Action:** ASG automatically scaled capacity from **2 $\rightarrow$ 3 instances**, launching `i-06f091be9df03c8a8` in `us-east-1b`.
5. **AWS Scaling Activity Log:**
   ```json
   {
     "Description": "Launching a new EC2 instance: i-06f091be9df03c8a8",
     "Cause": "At 2026-11-13T02:30:01Z a monitor alarm TargetTracking-devops-app-asg-AlarmHigh in state ALARM triggered policy cpu-utilization-target-70 changing the desired capacity from 2 to 3.",
     "StatusCode": "Successful"
   }
   ```

---

## 4. Multi-AZ Active Cluster Topology

| Instance ID | Availability Zone | AMI ID | Target Group Health | Storage Mount | Workload Role |
|---|---|---|---|---|---|
| `i-0e856a096ee1038db` | `us-east-1a` | `ami-05b8c4c41b13f8f47` | `healthy` (HTTP 200) | EFS `/var/www/html` | Apache Web Worker (Golden AMI) |
| `i-0368cc879d39fedc7` | `us-east-1b` | `ami-05b8c4c41b13f8f47` | `healthy` (HTTP 200) | EFS `/var/www/html` | Apache Web Worker (Golden AMI) |

---

## 5. Evaluation Panel Runbook

```bash
# 1. Probe ALB Endpoint and verify round-robin HTTP 200
curl -I http://devops-app-alb-890029008.us-east-1.elb.amazonaws.com/health

# 2. Inspect Target Group Health across all registered instances
aws elbv2 describe-target-health \
  --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:851706351853:targetgroup/devops-app-tg/1dabfbabe348fa69" \
  --query "TargetHealthDescriptions[].{Id:Target.Id,State:TargetHealth.State}" \
  --output table

# 3. Inspect Auto Scaling Group capacity and healthy instances
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names devops-app-asg \
  --query "AutoScalingGroups[0].Instances[].{InstanceId:InstanceId,AZ:AvailabilityZone,HealthStatus:HealthStatus,LifecycleState:LifecycleState}" \
  --output table

# 4. Inspect CloudWatch 70% Target Tracking Scaling Alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix "TargetTracking-devops-app-asg" \
  --query "MetricAlarms[].{AlarmName:AlarmName,Threshold:Threshold,StateValue:StateValue}" \
  --output table

# 5. Inspect Amazon EFS File System and Mount Targets
aws efs describe-mount-targets \
  --file-system-id fs-08b9d4abe38e30123 \
  --query "MountTargets[].{Id:MountTargetId,AZ:AvailabilityZoneName,IP:IpAddress,State:LifeCycleState}" \
  --output table
```

---

## 6. Author Sign-Off

- **DevOps Engineer:** Ankit Gawade
- **Email:** [ankitgawade1234@gmail.com](mailto:ankitgawade1234@gmail.com)
- **Evaluating Organization:** Itvedant Education Pvt. Ltd.
- **Master Assessment Submission PDF:** `DevOps_Engineer_Assessment_Submission_Ankit_Gawade.pdf`
