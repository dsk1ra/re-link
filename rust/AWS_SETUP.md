# AWS Hosting Setup for P2P Signaling Server

This guide describes how to host the Rust signaling server on AWS using **ECS Fargate** (Compute), **ElastiCache** (Redis), and an **Application Load Balancer** (ALB).

## Architecture
- **Compute**: ECS Fargate (Serverless containers).
- **Database**: Amazon ElastiCache for Redis (Stores session/mailbox state).
- **Load Balancer**: ALB (Handles WebSockets and HTTPS).
- **Registry**: AWS ECR (Stores Docker images).

---

## Step 1: Container Registry (ECR)
1.  Navigate to the `rust/` directory.
2.  Edit `push_to_ecr.sh` and set your desired `AWS_REGION` (e.g., `us-east-1`).
3.  Run the script to build and push the image:
    ```bash
    chmod +x push_to_ecr.sh
    ./push_to_ecr.sh
    ```
4.  Copy the **ECR URI** output at the end (e.g., `471112667566.dkr.ecr.eu-north-1.amazonaws.com/p2p-signaling-server:latest`).

## Step 2: Networking & Security Groups
1.  **VPC**: Use the default VPC or create a new one.
2.  **Security Group for Server (ECS)**:
    -   Allow **Inbound TCP 8080** from the Load Balancer Security Group (or `0.0.0.0/0` for testing).
3.  **Security Group for Redis**:
    -   Allow **Inbound TCP 6379** from the **Server Security Group**.

## Step 3: Redis (ElastiCache)
1.  Go to **Amazon ElastiCache** > **Redis Clusters**.
2.  Create a **Serverless Cache** (easiest) or **Design your own cache** (Node type `cache.t3.micro` for lowest cost).
3.  Ensure it is in the same VPC as your ECS tasks.
4.  **Important**: Enable **Encryption in Transit (TLS)** (The server config expects TLS by default).
5.  After creation, copy the **Primary Endpoint** (e.g., `rediss://clustering.xxx.use1.cache.amazonaws.com:6379`).

## Step 4: Load Balancer (ALB)
1.  Go to **EC2** > **Load Balancers** > **Create Load Balancer** (ALB).
2.  **Scheme**: Internet-facing.
3.  **Listeners**: HTTP Port 80 (and HTTPS 443 if you have a certificate).
4.  **Target Group**:
    -   **Target type**: IP addresses.
    -   **Protocol**: HTTP.
    -   **Port**: 8080.
    -   **Health check path**: `/health`.
5.  Complete creation.

## Step 5: ECS Fargate Deployment
1.  Go to **Amazon ECS** > **Task Definitions** > **Create new Task Definition**.
    -   **Launch type**: Fargate.
    -   **OS**: Linux.
    -   **CPU/Memory**: .25 vCPU / 0.5 GB (sufficient for starter).
    -   **Container Details**:
        -   **Image URI**: Paste the ECR URI from Step 1.
        -   **Port Mappings**: 8080 (TCP).
        -   **Environment Variables**:
            -   `SIGNALING_REDIS_URL`: `rediss://YOUR_REDIS_ENDPOINT:6379` (Note `rediss://` for TLS).
            -   `SIGNALING_PORT`: `8080`.
            -   `SIGNALING_ADDR`: `0.0.0.0`.
            -   `SIGNALING_REDIS_REQUIRE_TLS`: `true`.
2.  **Create Service**:
    -   Go to **Clusters** > Create Cluster (Fargate only) > Create Service.
    -   Select the Task Definition created above.
    -   **Public IP**: ENABLED (if in public subnet) or DISABLED (if in private subnet with NAT Gateway).
    -   **Load Balancer**: Select the ALB and Target Group created in Step 4.

## Verification
Visit `http://<ALB_DNS_NAME>/health`. You should see a JSON response.
Connect your Flutter app using the ALB DNS name as the signaling server URL.

## Step 6: Security & Rate Limiting (AWS WAF)
To protect your server from abuse and manage costs, attach an AWS WAF Web ACL to your Load Balancer.

1.  Go to **WAF & Shield** > **Web ACLs**.
2.  **Create Web ACL**:
    -   **Resource Type**: Regional resources (ALB).
    -   **Region**: Same as your ALB (e.g., us-east-1).
    -   **Associated Resources**: Select your ALB.
3.  **Add Rules**:
    -   **Add my own rules and rule groups** > **Rule builder** > **Rate-based rule**.
    -   **Rate limit**: e.g., **500** requests per **5 minutes** (approx 1.6 req/sec).
    -   **Action**: Block.
4.  **Default Action**: Allow.

This effectively blocks any IP that sends too many requests, protecting your ECS tasks and Redis.

## Step 7: Cost Management
1.  **AWS Budgets**: Go to **Billing Dashboard** > **Budgets** and create a "Cost Budget" (e.g., $10/month) to get emailed if you exceed it.
2.  **Service Quotas**: AWS automatically limits API usage. If your deployment script fails with "ThrottlingException", wait a few minutes and try again. The AWS CLI handles retries automatically.
