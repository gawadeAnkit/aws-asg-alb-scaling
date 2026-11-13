# trigger-cpu-stress.ps1 - Injects 100% CPU load across all active cluster nodes
Write-Host "=== Step 1: Discovering Running Cluster Nodes ===" -ForegroundColor Cyan
$instances = (aws ec2 describe-instances --region us-east-1 --filters "Name=tag:aws:autoscaling:groupName,Values=devops-app-asg" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text).Split("`t")
Write-Host "Found Running Instances: $instances" -ForegroundColor Green

Write-Host "`n=== Step 2: Injecting 100% CPU Load via AWS Systems Manager (SSM) ===" -ForegroundColor Cyan
$cmd = aws ssm send-command --instance-ids $instances --document-name "AWS-RunShellScript" --parameters commands="stress-ng --cpu 2 --timeout 300s &" --region us-east-1 --output json | ConvertFrom-Json
Write-Host "Stress Command Sent! Command ID: $($cmd.Command.CommandId)" -ForegroundColor Green
Write-Host "CPU will surge to 100%. CloudWatch AlarmHigh will trigger within 2-3 minutes, scaling from 2 -> 3 instances!" -ForegroundColor Yellow
