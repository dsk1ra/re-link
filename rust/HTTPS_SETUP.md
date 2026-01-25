# Setting up HTTPS for P2P Signaling

To secure the transport layer (HTTP -> HTTPS), you need a custom domain name and an SSL/TLS certificate. AWS does not issue certificates for default `*.elb.amazonaws.com` addresses.

## Prerequisites
1.  **A Domain Name**: You must own a domain (e.g., `my-p2p-app.com`).
    -   You can buy one via AWS Route53 or any other registrar (Namecheap, GoDaddy, etc.).

## Step 1: Request a Certificate (AWS ACM)
1.  Go to **AWS Console > ACM (Certificate Manager)**.
2.  **Request a certificate**.
3.  Enter your domain name (e.g., `signaling.my-p2p-app.com`).
4.  Select **DNS Validation**.
5.  **Important**: You must add the CNAME record provided by ACM to your domain's DNS settings to prove ownership.
    -   If using Route53, there's a button to "Create records in Route53".
    -   If using external DNS, copy the CNAME name and value to your registrar's dashboard.
6.  Wait for the status to change from "Pending validation" to "Issued".

## Step 2: Configure Load Balancer (ALB)
1.  Go to **EC2 > Load Balancers**.
2.  Select `p2p-signaling-alb`.
3.  **Listeners** tab > **Add listener**.
4.  **Protocol**: HTTPS.
5.  **Port**: 443.
6.  **Default actions**: Forward to `p2p-signaling-tg`.
7.  **Secure listener settings**: Select the certificate you created in Step 1.
8.  Click **Add**.

## Step 3: Redirect HTTP to HTTPS (Optional but Recommended)
1.  Edit the existing **HTTP:80** listener.
2.  Change "Default actions" from "Forward to..." to **Redirect**.
3.  **Protocol**: HTTPS.
4.  **Port**: 443.
5.  Save.

## Step 4: Point Domain to ALB
1.  Go to your DNS provider (Route53 or external).
2.  Create a **CNAME** record for `signaling.my-p2p-app.com`.
3.  Value: The DNS name of your ALB (e.g., `p2p-signaling-alb-xxxx.eu-north-1.elb.amazonaws.com`).

## Step 5: Update Application
1.  Update your Flutter app's `SIGNALING_URL` to the new HTTPS URL:
    ```bash
    flutter run --dart-define=SIGNALING_URL=https://signaling.my-p2p-app.com
    ```
2.  Update the `SIGNALING_PUBLIC_URL` environment variable in your ECS Task Definition to `https://signaling.my-p2p-app.com` (so the server generates correct invitation links).
