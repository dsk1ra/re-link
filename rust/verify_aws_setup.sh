#!/bin/bash
set -e

# Ensure aws is in path
export PATH="$HOME/.local/bin:$PATH"

# Configuration
REGION="eu-north-1"
ALB_NAME="p2p-signaling-alb"
TG_NAME="p2p-signaling-tg"
CLUSTER_NAME="p2p-cluster"
SERVICE_NAME="p2p-service"

echo "========================================================"
echo "🔍 Starting AWS Infrastructure Verification"
echo "========================================================"

# 1. Get Load Balancer Details
echo "👉 Checking Load Balancer ($ALB_NAME)..."
ALB_JSON=$(aws elbv2 describe-load-balancers --names $ALB_NAME --region $REGION --output json)
ALB_ARN=$(echo $ALB_JSON | jq -r '.LoadBalancers[0].LoadBalancerArn')
ALB_DNS=$(echo $ALB_JSON | jq -r '.LoadBalancers[0].DNSName')
ALB_SGS=$(echo $ALB_JSON | jq -r '.LoadBalancers[0].SecurityGroups[]')

echo "   ✅ DNS Name: $ALB_DNS"
echo "   ℹ️  Security Groups: $ALB_SGS"

# 2. Check Security Group Rules for ALB
echo ""
echo "👉 Checking ALB Security Group Rules..."
for sg in $ALB_SGS; do
    echo "   Checking SG: $sg"
    aws ec2 describe-security-groups --group-ids $sg --region $REGION \
    --query "SecurityGroups[0].IpPermissions[*].{FromPort:FromPort, ToPort:ToPort, IpRanges:IpRanges[*].CidrIp}" --output table
done

# 3. Check Listeners (Ports 80 vs 8080)
echo ""
echo "👉 Checking Listeners..."
aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --region $REGION \
    --query "Listeners[*].{Port:Port, Protocol:Protocol, DefaultActions:DefaultActions[0].TargetGroupArn}" --output table

# 4. Check Target Group Health
echo ""
echo "👉 Checking Target Health..."
# Get TG ARN (assuming one TG linked to the listener, or by name)
TG_ARN=$(aws elbv2 describe-target-groups --names $TG_NAME --region $REGION --query "TargetGroups[0].TargetGroupArn" --output text)
HEALTH_JSON=$(aws elbv2 describe-target-health --target-group-arn $TG_ARN --region $REGION)
TARGET_COUNT=$(echo $HEALTH_JSON | jq '.TargetHealthDescriptions | length')

if [ "$TARGET_COUNT" -eq "0" ]; then
    echo "   ⚠️  No targets found! Is your ECS Service running and registered?"
else
    echo $HEALTH_JSON | jq -r '.TargetHealthDescriptions[] | "   Target: \(.Target.Id) - State: \(.TargetHealth.State) - Reason: \(.TargetHealth.Reason // "None")"'
fi

# 5. Check ECS Service State
echo ""
echo "👉 Checking ECS Service Status..."
aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION \
    --query "services[0].{Status:status, RunningCount:runningCount, PendingCount:pendingCount, DesiredCount:desiredCount, Events:events[0].message}" --output table

# 6. Connectivity Test
echo ""
echo "👉 Attempting Connection..."
echo "   Testing http://$ALB_DNS/health (Port 80)..."
CODE_80=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$ALB_DNS/health || echo "Fail")
echo "   HTTP 80 Response Code: $CODE_80"

echo "   Testing http://$ALB_DNS:8080/health (Port 8080)..."
CODE_8080=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://$ALB_DNS:8080/health || echo "Fail")
echo "   HTTP 8080 Response Code: $CODE_8080"

echo ""
echo "========================================================"
echo "📝 Diagnosis:"
if [ "$CODE_80" == "200" ]; then
    echo "✅ SUCCESS: Your server is accessible on Port 80!"
elif [ "$CODE_8080" == "200" ]; then
    echo "✅ SUCCESS: Your server is accessible on Port 8080!"
    echo "ℹ️  Recommendation: Change your ALB Listener to Port 80 for standard HTTP access."
else
    echo "❌ FAILURE: Could not access /health on Port 80 or 8080."
    echo "   Check the outputs above:"
    echo "   1. Does the Listener exist for the port you want?"
    echo "   2. Does the Security Group allow Inbound 0.0.0.0/0 on that port?"
    echo "   3. Is the Target Health 'healthy'?"
fi
echo "========================================================"
