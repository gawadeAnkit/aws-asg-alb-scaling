# demo-menu.ps1 - Interactive One-Click Demonstration Control Center
$ErrorActionPreference = "Continue"

function Show-Header {
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "     AWS HIGH-AVAILABILITY CLUSTER DEMONSTRATION CONTROL CENTER           " -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "     Candidate: Ankit Gawade | Role: DevOps Engineer                      " -ForegroundColor White
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Open-DemoTabs {
    Write-Host "[*] Launching All Demonstration Tabs in your default browser..." -ForegroundColor Green
    Start-Process "http://devops-app-alb-890029008.us-east-1.elb.amazonaws.com"
    Start-Process "https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#AutoScalingGroupDetails:id=devops-app-asg"
    Start-Process "https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#TargetGroup:targetGroupArn=arn:aws:elasticloadbalancing:us-east-1:851706351853:targetgroup/devops-app-tg/1dabfbabe348fa69"
    Start-Process "https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarmsV2:search=devops-app-asg"
    Start-Process "https://us-east-1.console.aws.amazon.com/systems-manager/run-command/exec-history?region=us-east-1"
    Write-Host "[+] All 5 tabs opened successfully! Arrange your windows to begin recording." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to return to main menu..."
}

function Watch-LiveCluster {
    param([string]$Title = "LIVE CLUSTER MONITOR")
    Clear-Host
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "   $Title (Press Ctrl+C to stop watching)   " -ForegroundColor Yellow
    Write-Host "==========================================================================" -ForegroundColor Cyan
    
    for ($i = 1; $i -le 60; $i++) {
        Write-Host "`n--- Refresh #$i ($([DateTime]::Now.ToString('HH:mm:ss'))) ---" -ForegroundColor DarkGray
        
        # 1. EC2 Instances
        Write-Host "[1] Active EC2 Instances in ASG:" -ForegroundColor Cyan
        aws ec2 describe-instances --region us-east-1 --filters "Name=tag:aws:autoscaling:groupName,Values=devops-app-asg" "Name=instance-state-name,Values=running,pending" --query "Reservations[].Instances[].[InstanceId,Placement.AvailabilityZone,PrivateIpAddress,State.Name]" --output table
        
        # 2. Target Health
        Write-Host "`n[2] Target Group Health (/health):" -ForegroundColor Cyan
        aws elbv2 describe-target-health --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:851706351853:targetgroup/devops-app-tg/1dabfbabe348fa69" --region us-east-1 --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output table
        
        # 3. Alarms
        Write-Host "`n[3] CloudWatch 70% CPU Alarms:" -ForegroundColor Cyan
        aws cloudwatch describe-alarms --alarm-name-prefix "TargetTracking-devops-app-asg" --region us-east-1 --query "MetricAlarms[].[AlarmName,StateValue]" --output table
        
        # 4. Recent ASG Activity
        Write-Host "`n[4] Latest Auto Scaling Activity:" -ForegroundColor Cyan
        aws autoscaling describe-scaling-activities --auto-scaling-group-name devops-app-asg --region us-east-1 --max-items 1 --query "Activities[].[StartTime,StatusCode,Description]" --output table
        
        Write-Host "`nRefreshing in 10 seconds... (Press Ctrl+C to return to menu)" -ForegroundColor DarkYellow
        Start-Sleep -Seconds 10
    }
}

function Trigger-Scenario1 {
    Write-Host "`n================ SCENARIO 1: CPU SURGE AUTO-SCALING ================" -ForegroundColor Magenta
    Write-Host "[Step 1] Discovering running nodes in ASG..." -ForegroundColor Cyan
    $instances = (aws ec2 describe-instances --region us-east-1 --filters "Name=tag:aws:autoscaling:groupName,Values=devops-app-asg" "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text).Split("`t")
    Write-Host "[+] Target Nodes: $instances" -ForegroundColor Green
    
    Write-Host "`n[Step 2] Sending 100% CPU load via AWS Systems Manager (SSM)..." -ForegroundColor Cyan
    $cmd = aws ssm send-command --instance-ids $instances --document-name "AWS-RunShellScript" --parameters commands="stress-ng --cpu 2 --timeout 300s &" --region us-east-1 --output json | ConvertFrom-Json
    Write-Host "[+] SSM Command Sent! (CommandId: $($cmd.Command.CommandId))" -ForegroundColor Green
    Write-Host "[!] CPU will surge to 100%. CloudWatch AlarmHigh will trigger in 2-3 mins and scale 2 -> 3 instances." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Entering Live Cluster Watcher now..." -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    Watch-LiveCluster -Title "SCENARIO 1: WATCHING CPU SURGE & SCALE OUT (2 -> 3 NODES)"
}

function Trigger-Scenario2 {
    Write-Host "`n================ SCENARIO 2: WEB SERVER SELF-HEALING ================" -ForegroundColor Magenta
    Write-Host "[Step 1] Selecting one healthy node to simulate web crash..." -ForegroundColor Cyan
    $target = (aws ec2 describe-instances --region us-east-1 --filters "Name=tag:aws:autoscaling:groupName,Values=devops-app-asg" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
    Write-Host "[+] Selected Target Node to Crash: $target" -ForegroundColor Red
    
    Write-Host "`n[Step 2] Remotely stopping Apache (systemctl stop httpd) via SSM..." -ForegroundColor Cyan
    $cmd = aws ssm send-command --instance-ids $target --document-name "AWS-RunShellScript" --parameters commands="systemctl stop httpd" --region us-east-1 --output json | ConvertFrom-Json
    Write-Host "[+] Crash Command Sent! (CommandId: $($cmd.Command.CommandId))" -ForegroundColor Green
    Write-Host "[!] ALB Target Group will mark $target UNHEALTHY in ~20 seconds." -ForegroundColor Yellow
    Write-Host "[!] ASG will terminate $target and launch a fresh Golden AMI node in <10 seconds." -ForegroundColor Green
    Write-Host "[!] The website experiences ZERO DOWNTIME during this process!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Entering Live Cluster Watcher now..." -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    Watch-LiveCluster -Title "SCENARIO 2: WATCHING TARGET UNHEALTHY & SELF-HEALING"
}

# Main Loop
while ($true) {
    Show-Header
    Write-Host "Choose what you want to do:" -ForegroundColor White
    Write-Host "  [1] Open All Demonstration Browser Tabs (ALB Website + AWS Console)" -ForegroundColor Green
    Write-Host "  [2] Trigger Scenario 1: CPU Surge Auto-Scaling (2 -> 3 instances)" -ForegroundColor Yellow
    Write-Host "  [3] Trigger Scenario 2: Web Server Crash Self-Healing (Zero downtime)" -ForegroundColor Red
    Write-Host "  [4] View Live Cluster Dashboard (Status / Health / Alarms)" -ForegroundColor Cyan
    Write-Host "  [5] Exit" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "Enter your choice [1-5]"
    
    switch ($choice) {
        "1" { Open-DemoTabs }
        "2" { Trigger-Scenario1 }
        "3" { Trigger-Scenario2 }
        "4" { Watch-LiveCluster -Title "LIVE CLUSTER DASHBOARD" }
        "5" { Write-Host "Exiting. Good luck with your demonstration!" -ForegroundColor Green; exit }
        default { Write-Host "Invalid option. Please enter 1, 2, 3, 4, or 5." -ForegroundColor Red; Start-Sleep -Seconds 2 }
    }
}
