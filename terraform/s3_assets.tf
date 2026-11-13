# s3_assets.tf - S3 Artifact Storage for Shared Web Assets
# Candidate: Ankit Gawade <ankitgawade1234@gmail.com>
# Role: DevOps Engineer | Itvedant Education Pvt. Ltd.

resource "random_id" "assets_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "app_assets" {
  bucket        = "devops-asg-app-assets-${random_id.assets_suffix.hex}"
  force_destroy = true

  tags = {
    Name      = "devops-asg-app-assets"
    Project   = "ALB-ASG-AutoHealing"
    ManagedBy = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload website files into S3
locals {
  mime_types = {
    "html" = "text/html"
    "css"  = "text/css"
    "js"   = "application/javascript"
    "jpg"  = "image/jpeg"
    "jpeg" = "image/jpeg"
    "png"  = "image/png"
    "svg"  = "image/svg+xml"
    "json" = "application/json"
    "txt"  = "text/plain"
  }
}

resource "aws_s3_object" "website_files" {
  for_each = fileset("${path.module}/../website", "**/*")

  bucket = aws_s3_bucket.app_assets.id
  key    = "website/${each.value}"
  source = "${path.module}/../website/${each.value}"
  etag   = filemd5("${path.module}/../website/${each.value}")

  content_type = lookup(
    local.mime_types,
    regex("[^.]+$", each.value),
    "application/octet-stream"
  )
}

# IAM Policy allowing EC2 instances to read from this bucket
resource "aws_iam_role_policy" "s3_read_assets" {
  name = "devops-ec2-s3-assets-read"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app_assets.arn,
          "${aws_s3_bucket.app_assets.arn}/*"
        ]
      }
    ]
  })
}

output "assets_bucket_name" {
  description = "S3 Assets Bucket Name"
  value       = aws_s3_bucket.app_assets.id
}
