# efs.tf - Production-Grade Multi-AZ Amazon Elastic File System (EFS)
# Candidate: Ankit Gawade <ankitgawade1234@gmail.com>
# Role: DevOps Engineer | Itvedant Education Pvt. Ltd.

resource "aws_efs_file_system" "shared_web" {
  creation_token   = "devops-asg-shared-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name      = "devops-asg-shared-efs"
    Project   = "ALB-ASG-AutoHealing"
    ManagedBy = "Terraform"
  }
}

resource "aws_security_group" "efs" {
  name        = "devops-efs-sg"
  description = "Allow NFS 2049 inbound strictly from EC2 ASG instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "NFS from EC2 instances"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "devops-efs-sg"
    ManagedBy = "Terraform"
  }
}

resource "aws_efs_mount_target" "subnets" {
  for_each        = toset(data.aws_subnets.public.ids)
  file_system_id  = aws_efs_file_system.shared_web.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

output "efs_id" {
  description = "Amazon EFS File System ID"
  value       = aws_efs_file_system.shared_web.id
}

output "efs_dns_name" {
  description = "Amazon EFS File System DNS Name"
  value       = aws_efs_file_system.shared_web.dns_name
}

