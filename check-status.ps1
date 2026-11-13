# check-status.ps1 - Instant Dashboard of Cluster Health, Alarms, and ASG Scaling
Write-Host "================ CLUSTER EC2 INSTANCES ================" -ForegroundColor Cyan
aws ec2 describe-instances --region us-east-1 --filters "Name=tag:aws:autoscaling:groupName,Values=devops-app-asg" "Name=instance-state-name,Values=running,pending" --query "Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone,PrivateIpAddress,PublicIpAddress,State.Name]" --output table

Write-Host "`n================ TARGET GROUP HEALTH (/health) ================" -ForegroundColor Cyan
aws elbv2 describe-target-health --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:851706351853:targetgroup/devops-app-tg/1dabfbabe348fa69" --region us-east-1 --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output table

Write-Host "`n================ CLOUDWATCH 70% CPU ALARMS ================" -ForegroundColor Cyan
aws cloudwatch describe-alarms --alarm-name-prefix "TargetTracking-devops-app-asg" --region us-east-1 --query "MetricAlarms[].[AlarmName,StateValue,Threshold]" --output table

Write-Host "`n================ RECENT SCALING ACTIVITIES ================" -ForegroundColor Cyan
aws autoscaling describe-scaling-activities --auto-scaling-group-name devops-app-asg --region us-east-1 --max-items 2 --query "Activities[].[StartTime,StatusCode,Description]" --output table
