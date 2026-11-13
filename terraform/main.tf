# main.tf - AWS High Availability Auto-Scaling & Load Balanced Web Cluster
# Candidate: Ankit Gawade <ankitgawade1234@gmail.com>
# Role: DevOps Engineer | Itvedant Education Pvt. Ltd.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "ALB-ASG-AutoHealing"
      Candidate = "Ankit Gawade"
      Role      = "DevOps Engineer"
      ManagedBy = "Terraform"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }
}

# Lookup Pre-Baked Production Golden AMI
data "aws_ami" "golden_ami" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["devops-golden-ami-al2023-v1"]
  }
}

# ========================================================
# 1. IAM Role for SSM Session Manager & EFS Client Access
# ========================================================
resource "aws_iam_role" "ec2_ssm" {
  name = "asg-alb-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "efs_client" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonElasticFileSystemClientReadWriteAccess"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "asg-alb-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# ========================================================
# 2. Security Groups (Least Privilege: EC2 accepts HTTP strictly from ALB)
# ========================================================
resource "aws_security_group" "alb" {
  name        = "devops-alb-sg"
  description = "Allow HTTP inbound traffic to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "devops-asg-ec2-sg"
  description = "Allow HTTP only from ALB Security Group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "HTTP from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ========================================================
# 3. Application Load Balancer + Target Group + Listener
# ========================================================
resource "aws_lb" "app" {
  name               = "devops-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids

  tags = {
    Name = "devops-app-alb"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "devops-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
    matcher             = "200"
  }

  deregistration_delay = 15

  tags = {
    Name = "devops-app-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ========================================================
# 4. Launch Template (Golden AMI + IMDSv2 + Detailed Monitoring)
# ========================================================
resource "aws_launch_template" "app" {
  name_prefix   = "devops-app-lt-"
  image_id      = data.aws_ami.golden_ami.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm.name
  }

  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    efs_id        = aws_efs_file_system.shared_web.id
    assets_bucket = aws_s3_bucket.app_assets.id
    aws_region    = var.aws_region
  }))

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "devops-asg-web-instance"
      Role      = "DevOps Engineer"
      Candidate = "Ankit Gawade"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ========================================================
# 5. Auto Scaling Group (ELB Health Check + CPU > 70% Policy)
# ========================================================
resource "aws_autoscaling_group" "app" {
  name                      = "devops-app-asg"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  vpc_zone_identifier       = data.aws_subnets.public.ids
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 90

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 60
    }
    triggers = ["tag"]
  }

  depends_on = [
    aws_efs_mount_target.subnets,
    aws_s3_object.website_files
  ]

  tag {
    key                 = "Name"
    value               = "devops-asg-web-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "DevOps Engineer"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_70" {
  name                   = "cpu-utilization-target-70"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ========================================================
# Outputs
# ========================================================
output "alb_dns_name" {
  value = "http://${aws_lb.app.dns_name}"
}

output "golden_ami_id" {
  description = "Custom Pre-baked Golden AMI ID"
  value       = data.aws_ami.golden_ami.id
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}
