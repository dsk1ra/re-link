#!/bin/bash
set -e

# Ensure aws is in path
export PATH="$HOME/.local/bin:$PATH"

# Configuration
REGION="eu-north-1" 
SG_ECS_NAME="p2p-ecs-sg"
SG_REDIS_NAME="p2p-redis-sg"

# 1. Set VPC ID (Default VPC in eu-north-1)
VPC_ID="vpc-04babfc66a6feab23"
echo "Using VPC: $VPC_ID"

# Function to get or create Security Group
get_or_create_sg() {
    local sg_name=$1
    local sg_desc=$2
    
    # Try to find existing SG
    local sg_id=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$sg_name Name=vpc-id,Values=$VPC_ID --query "SecurityGroups[0].GroupId" --output text --region $REGION)
    
    if [ "$sg_id" == "None" ] || [ -z "$sg_id" ]; then
        echo "Creating $sg_name..."
        sg_id=$(aws ec2 create-security-group \
            --group-name $sg_name \
            --description "$sg_desc" \
            --vpc-id $VPC_ID \
            --query 'GroupId' \
            --output text \
            --region $REGION)
    else
        echo "Found existing $sg_name: $sg_id"
    fi
    echo $sg_id
}

# 2. Get/Create ECS Security Group
ECS_SG_ID=$(get_or_create_sg "$SG_ECS_NAME" "Security group for P2P Signaling Server (ECS)")

# Allow Port 8080 from Anywhere (idempotent call)
echo "Authorizing ingress for ECS SG..."
aws ec2 authorize-security-group-ingress \
    --group-id $ECS_SG_ID \
    --protocol tcp \
    --port 8080 \
    --cidr 0.0.0.0/0 \
    --region $REGION 2>/dev/null || echo "  Rule likely already exists."

# 3. Get/Create Redis Security Group
REDIS_SG_ID=$(get_or_create_sg "$SG_REDIS_NAME" "Security group for Redis (ElastiCache)")

# Allow Port 6379 ONLY from ECS Security Group
echo "Authorizing ingress for Redis SG..."
aws ec2 authorize-security-group-ingress \
    --group-id $REDIS_SG_ID \
    --protocol tcp \
    --port 6379 \
    --source-group $ECS_SG_ID \
    --region $REGION 2>/dev/null || echo "  Rule likely already exists."

echo ""
echo "--------------------------------------------------"
echo "✅ Setup Complete!"
echo "--------------------------------------------------"
echo "1. VPC ID:             $VPC_ID"
echo "2. ECS Security Group: $ECS_SG_ID"
echo "3. Redis Security Group: $REDIS_SG_ID"
echo "--------------------------------------------------"
echo "Save these IDs. You will need them for the next steps."