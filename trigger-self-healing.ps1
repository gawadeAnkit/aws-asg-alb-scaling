# trigger-self-healing.ps1 - Simulates web server failure on a node to trigger ELB Auto-Healing
Write-Host "=== Step 1: Selecting a Target Node to Crash ===" -ForegroundColor Cyan
$target = (aws ec2 describe-instances --region us-east-1 --filters "Name=tag:aws:autoscaling:groupName,Values=devops-app-asg" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
Write-Host "Selected Target Instance: $target" -ForegroundColor Red

Write-Host "`n=== Step 2: Remotely Stopping Apache (systemctl stop httpd) via SSM ===" -ForegroundColor Cyan
$cmd = aws ssm send-command --instance-ids $target --document-name "AWS-RunShellScript" --parameters commands="systemctl stop httpd" --region us-east-1 --output json | ConvertFrom-Json
Write-Host "Crash Command Sent! Command ID: $($cmd.Command.CommandId)" -ForegroundColor Green
Write-Host "Target Group will detect failure on /health in ~20s and mark it UNHEALTHY." -ForegroundColor Yellow
Write-Host "ASG will terminate $target and launch a fresh Golden AMI node in <10 seconds!" -ForegroundColor Green
