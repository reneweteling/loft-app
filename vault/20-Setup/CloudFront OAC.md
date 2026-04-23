---
title: CloudFront OAC
tags: [setup, aws, cloudfront, cdn, security]
project: Loft
created: 2026-04-23
---

# CloudFront OAC

This page describes the recommended setup for the Public pane: keep the S3 bucket **fully private**, and serve files through a CloudFront distribution using **Origin Access Control (OAC)**. This replaces the older Origin Access Identity (OAI) method.

Benefits:
- The bucket never has a public access policy — you cannot accidentally expose private or temporary files
- CloudFront provides caching, compression, and a global CDN for free-tier-eligible distributions
- You get a clean `cloudfront.net` domain (or your own custom domain)
- `s3:PutObjectAcl` is not needed — you can remove that statement from [[IAM Policy]]

> [!note]
> OAC is an AWS-only feature. For other providers, see [[Custom Endpoints]].

---

## Overview

```
Browser → CloudFront distribution → OAC signs request → S3 bucket (private)
Loft    → PutObject directly to S3 (private, no ACL)
```

Loft uploads files directly to S3 using its IAM credentials. CloudFront signs requests to S3 using OAC — no public S3 URLs needed.

---

## Step 1 — Ensure the bucket is fully private

If you haven't already, apply the full public access block:

```bash
aws s3api put-public-access-block \
  --bucket YOUR-BUCKET-NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

Remove any existing public bucket policy:

```bash
aws s3api delete-bucket-policy --bucket YOUR-BUCKET-NAME
```

---

## Step 2 — Create the CloudFront Origin Access Control

```bash
aws cloudfront create-origin-access-control \
  --origin-access-control-config '{
    "Name": "loft-oac",
    "Description": "OAC for Loft public pane",
    "SigningProtocol": "sigv4",
    "SigningBehavior": "always",
    "OriginAccessControlOriginType": "s3"
  }'
```

The response includes an `Id` field — copy it. You will need it in the next step.

```json
{
  "OriginAccessControl": {
    "Id": "EABCDEF1234567",
    "OriginAccessControlConfig": { ... }
  }
}
```

---

## Step 3 — Create the CloudFront distribution

This step is easier done in the AWS Console. The CLI equivalent is long; both approaches are shown.

### Console approach (recommended for first-time setup)

1. Go to **CloudFront → Distributions → Create distribution**
2. **Origin domain** — select your S3 bucket (it appears as `YOUR-BUCKET-NAME.s3.YOUR-REGION.amazonaws.com`)
3. **Origin access** — choose **Origin access control settings (recommended)**
4. **Origin access control** — select the OAC you created (`loft-oac`) or create a new one here
5. **Default cache behavior**:
   - Viewer protocol policy: **Redirect HTTP to HTTPS**
   - Cache policy: **CachingOptimized**
   - Origin request policy: **CORS-S3Origin** (if you enabled CORS in [[Bucket Setup]])
6. **Web Application Firewall** — disable for personal use
7. Click **Create distribution**

CloudFront will show a yellow banner: **"The S3 bucket policy needs to be updated."** Click **Copy policy** — you will apply it in step 4.

### CLI approach

```bash
aws cloudfront create-distribution \
  --distribution-config '{
    "CallerReference": "loft-pub-'$(date +%s)'",
    "Origins": {
      "Quantity": 1,
      "Items": [{
        "Id": "loft-s3-origin",
        "DomainName": "YOUR-BUCKET-NAME.s3.YOUR-REGION.amazonaws.com",
        "S3OriginConfig": {"OriginAccessIdentity": ""},
        "OriginAccessControlId": "EABCDEF1234567"
      }]
    },
    "DefaultCacheBehavior": {
      "TargetOriginId": "loft-s3-origin",
      "ViewerProtocolPolicy": "redirect-to-https",
      "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
      "AllowedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"],
        "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]}
      },
      "Compress": true,
      "ForwardedValues": {
        "QueryString": false,
        "Cookies": {"Forward": "none"}
      },
      "MinTTL": 0
    },
    "Comment": "Loft public pane",
    "Enabled": true,
    "HttpVersion": "http2and3",
    "PriceClass": "PriceClass_100"
  }'
```

> [!note]
> `CachePolicyId` `658327ea-f89d-4fab-a63d-7e88639e58f6` is the AWS-managed **CachingOptimized** policy. `PriceClass_100` covers US, Canada, and Europe edge locations — cheapest option.

The response includes a `DomainName` like `d1234abcd.cloudfront.net` and a `Distribution.Id`. Copy both.

---

## Step 4 — Update the S3 bucket policy to allow CloudFront

Replace `YOUR-BUCKET-NAME`, `YOUR-ACCOUNT-ID`, and `YOUR-DISTRIBUTION-ID`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontOAC",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/pub/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::YOUR-ACCOUNT-ID:distribution/YOUR-DISTRIBUTION-ID"
        }
      }
    }
  ]
}
```

Save as `cf-bucket-policy.json`, then apply:

```bash
aws s3api put-bucket-policy \
  --bucket YOUR-BUCKET-NAME \
  --policy file://cf-bucket-policy.json
```

The policy scopes CloudFront access to `pub/*` only. Objects in `private/`, `tmp1d/`, and `tmp30d/` cannot be served by CloudFront even if someone guesses the key.

---

## Step 5 — Configure Loft

1. Open **Settings (⌘,)** → **CDN** tab
2. Set **CDN Base URL** to `https://d1234abcd.cloudfront.net` (your distribution domain)
3. Optionally configure a custom domain (step 6) and use that instead

Loft will now build public pane URLs as `https://d1234abcd.cloudfront.net/pub/...` instead of direct S3 URLs.

---

## Step 6 — Custom domain (optional)

To use `cdn.yourdomain.com` instead of `d1234abcd.cloudfront.net`:

1. **Request or import an ACM certificate** for `cdn.yourdomain.com` in **us-east-1** (CloudFront requires us-east-1 regardless of your bucket region)
2. In the CloudFront distribution → **Edit** → **Alternate domain names (CNAMEs)** → add `cdn.yourdomain.com`
3. Set the **Custom SSL certificate** to your ACM certificate
4. Add a **CNAME record** in your DNS pointing `cdn.yourdomain.com` to `d1234abcd.cloudfront.net`
5. Update the CDN Base URL in Loft to `https://cdn.yourdomain.com`

---

## Verifying the setup

Upload a test file to the Public pane. The URL returned should start with your CloudFront domain. Check that:

```bash
# Should return 200 and the file content
curl -I https://d1234abcd.cloudfront.net/pub/YOUR-TEST-KEY

# Should return 403 (CloudFront blocks direct S3 access)
curl -I https://YOUR-BUCKET-NAME.s3.YOUR-REGION.amazonaws.com/pub/YOUR-TEST-KEY
```

> [!tip]
> CloudFront distributions take 5–15 minutes to fully deploy after creation. If you get errors immediately after setup, wait a few minutes and try again.

---

## Removing `s3:PutObjectAcl` from the IAM policy

With OAC in place, Loft no longer needs to set `public-read` ACLs. Remove the `AllowPublicAclOnPubPrefix` statement from the IAM policy in [[IAM Policy]] and update the attached policy version in AWS.

---

## Related

- [[Bucket Setup]] — bucket creation and lifecycle rules
- [[IAM Policy]] — adjust after removing PutObjectAcl requirement
- [[Custom Endpoints]] — non-AWS providers with their own CDN options
- [[Loft Overview]]
