import urllib.request
import json
import time

alb_url = "http://devops-app-alb-890029008.us-east-1.elb.amazonaws.com"
print("=== Probing ALB Root ===")
req = urllib.request.Request(alb_url, headers={"User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(req) as resp:
    print("Status:", resp.status)
    content = resp.read().decode("utf-8")
    print("Content length:", len(content))
    print("Has Inner Peace:", "Inner Peace" in content)
    print("Has Ankit Gawade:", "Ankit Gawade" in content)
    print("Has Tooplate:", "tooplate" in content.lower())

print("\n=== Testing Multi-AZ Load Balancing (/node-info.json) ===")
nodes = {}
for i in range(8):
    req = urllib.request.Request(f"{alb_url}/node-info.json?t={time.time()}", headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        iid = data.get("instance_id")
        az = data.get("az")
        nodes[iid] = az
        print(f"Req {i+1}: Instance={iid} | AZ={az} | IP={data.get('private_ip')} | EFS={data.get('efs_id')} | Role={data.get('role')}")
    time.sleep(1)

print("\nSummary of Nodes Responding:")
for iid, az in nodes.items():
    print(f" - Node: {iid} in AZ: {az}")
