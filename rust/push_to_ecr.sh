#!/bin/bash
set -e

# Ensure local bin is in PATH for AWS CLI
export PATH="$HOME/.local/bin:$PATH"

# Configuration
AWS_REGION="eu-north-1" # Change this to your region
REPO_NAME="p2p-signaling-server"
IMAGE_TAG="latest"

# 1. Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com

# 2. Create Repository (if not exists)
echo "Ensuring repository exists..."
aws ecr describe-repositories --repository-names $REPO_NAME --region $AWS_REGION > /dev/null 2>&1 || \
    aws ecr create-repository --repository-name $REPO_NAME --region $AWS_REGION

# 3. Build Docker Image
echo "Building Docker image..."
# Get the absolute path to the directory containing this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Build using the script's directory as the context
docker build -t $REPO_NAME "$SCRIPT_DIR"

# 4. Tag Image
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_NAME:$IMAGE_TAG"
docker tag $REPO_NAME:latest $ECR_URI

# 5. Push Image
echo "Pushing image to ECR..."
docker push $ECR_URI

echo "Success! Image pushed to: $ECR_URI"
