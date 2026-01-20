#!/usr/bin/env python3
import subprocess
import json
import sys
import os
import time

# Ensure ~/.local/bin is in PATH for AWS CLI
os.environ["PATH"] += os.pathsep + os.path.expanduser("~/.local/bin")

REGION = "eu-north-1"
ALB_NAME = "p2p-signaling-alb"
TG_NAME = "p2p-signaling-tg"
CLUSTER_NAME = "p2p-cluster"
SERVICE_NAME = "p2p-service"

def run_aws_command(command):
    full_cmd = f"aws {command} --region {REGION} --output json"
    try:
        result = subprocess.run(full_cmd, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {full_cmd}")
        print(e.stderr)
        return None
    except json.JSONDecodeError:
        print("Failed to decode JSON response")
        return None

def main():
    print("========================================================")
    print("🔍 Starting AWS Infrastructure Verification (Python)")
    print("========================================================")

    # 1. Get Load Balancer Details
    print(f"👉 Checking Load Balancer ({ALB_NAME})...")
    alb_data = run_aws_command(f"elbv2 describe-load-balancers --names {ALB_NAME}")
    if not alb_data or not alb_data['LoadBalancers']:
        print("❌ Load Balancer not found!")
        sys.exit(1)
    
    alb = alb_data['LoadBalancers'][0]
    alb_arn = alb['LoadBalancerArn']
    alb_dns = alb['DNSName']
    alb_sgs = alb['SecurityGroups']

    print(f"   ✅ DNS Name: {alb_dns}")
    print(f"   ℹ️  Security Groups: {', '.join(alb_sgs)}")

    # 2. Check Security Group Rules
    print("\n👉 Checking ALB Security Group Rules...")
    for sg_id in alb_sgs:
        print(f"   Checking SG: {sg_id}")
        sg_data = run_aws_command(f"ec2 describe-security-groups --group-ids {sg_id}")
        if sg_data and sg_data['SecurityGroups']:
            perms = sg_data['SecurityGroups'][0]['IpPermissions']
            for p in perms:
                from_port = p.get('FromPort', 'All')
                to_port = p.get('ToPort', 'All')
                ip_ranges = [ip['CidrIp'] for ip in p.get('IpRanges', [])]
                print(f"      - Port {from_port}-{to_port} allowed from: {ip_ranges}")

    # 3. Check Listeners
    print("\n👉 Checking Listeners...")
    listeners_data = run_aws_command(f"elbv2 describe-listeners --load-balancer-arn {alb_arn}")
    if listeners_data:
        for l in listeners_data['Listeners']:
            print(f"   - Port: {l['Port']} ({l['Protocol']}) -> Target: {l['DefaultActions'][0].get('TargetGroupArn', 'Unknown')}")

    # 4. Check Target Group Health
    print("\n👉 Checking Target Health...")
    tg_data = run_aws_command(f"elbv2 describe-target-groups --names {TG_NAME}")
    if tg_data and tg_data['TargetGroups']:
        tg_arn = tg_data['TargetGroups'][0]['TargetGroupArn']
        health_data = run_aws_command(f"elbv2 describe-target-health --target-group-arn {tg_arn}")
        if health_data and health_data['TargetHealthDescriptions']:
            for target in health_data['TargetHealthDescriptions']:
                t_id = target['Target']['Id']
                state = target['TargetHealth']['State']
                reason = target['TargetHealth'].get('Reason', 'None')
                print(f"   Target: {t_id} - State: {state} - Reason: {reason}")
        else:
            print("   ⚠️  No targets found registered!")
    else:
        print("   ❌ Target Group not found!")

    # 5. Check ECS Service
    print("\n👉 Checking ECS Service Status...")
    svc_data = run_aws_command(f"ecs describe-services --cluster {CLUSTER_NAME} --services {SERVICE_NAME}")
    if svc_data and svc_data['services']:
        svc = svc_data['services'][0]
        print(f"   Status: {svc['status']}")
        print(f"   Running: {svc['runningCount']} | Pending: {svc['pendingCount']} | Desired: {svc['desiredCount']}")
        if svc.get('events'):
            print(f"   Latest Event: {svc['events'][0]['message']}")
    
    # 6. Connectivity Test
    print("\n👉 Attempting Connection...")
    
    def test_url(url):
        print(f"   Testing {url} ...")
        try:
            # Using curl via subprocess for simplicity
            res = subprocess.run(f"curl -s -o /dev/null -w '%{{http_code}}' --max-time 5 {url}", shell=True, stdout=subprocess.PIPE, text=True)
            code = res.stdout.strip()
            print(f"   Response Code: {code}")
            return code
        except Exception as e:
            print(f"   Test failed: {e}")
            return "000"

    code_80 = test_url(f"http://{alb_dns}/health")
    code_8080 = test_url(f"http://{alb_dns}:8080/health")

    print("\n========================================================")
    print("📝 Diagnosis:")
    if code_80 == "200":
        print("✅ SUCCESS: Your server is accessible on Port 80!")
    elif code_8080 == "200":
        print("✅ SUCCESS: Your server is accessible on Port 8080!")
        print("ℹ️  Recommendation: Change your ALB Listener to Port 80 for standard HTTP access.")
    else:
        print("❌ FAILURE: Could not access /health on Port 80 or 8080.")
        print("   Check the output above for Listener ports, Security Group rules, and Target Health.")
    print("========================================================")

if __name__ == "__main__":
    main()
