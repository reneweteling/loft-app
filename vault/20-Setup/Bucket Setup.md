---
title: Bucket Setup
tags: [setup, s3, aws, lifecycle, cors]
project: Loft
created: 2026-04-23
---

# Bucket Setup

This page walks through creating and configuring the S3 bucket that Loft uses. All four panes (Private, 1 day, 30 days, Public) share one bucket, differentiated by key prefix and object tags.

> [!note]
> Loft validates the bucket on first launch via `HeadBucket`. The bucket must exist before you open Settings. The app does **not** create the bucket for you.

---

## 1. Create the bucket

Replace `YOUR-BUCKET-NAME` and `YOUR-REGION` throughout this page.

```bash
aws s3api create-bucket \
  --bucket YOUR-BUCKET-NAME \
  --region YOUR-REGION \
  --create-bucket-configuration LocationConstraint=YOUR-REGION
```

> [!warning]
> `us-east-1` does **not** accept `--create-bucket-configuration`. Omit that flag if your region is `us-east-1`.

Enable versioning only if you want it — Loft does not require it and lifecycle expiry works on non-versioned buckets:

```bash
# Optional
aws s3api put-bucket-versioning \
  --bucket YOUR-BUCKET-NAME \
  --versioning-configuration Status=Enabled
```

---

## 2. Block public access (selective)

Loft places public files under the `pub/` prefix. The recommended approach is to keep the bucket private and serve the `pub/` prefix through CloudFront (see [[CloudFront OAC]]). If you prefer direct S3 public access, you must partially unblock public access and apply a bucket policy (step 5).

**Recommended — keep bucket fully private, use CloudFront:**

```bash
aws s3api put-public-access-block \
  --bucket YOUR-BUCKET-NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

**Alternative — allow public ACL on `pub/` prefix only:**

```bash
aws s3api put-public-access-block \
  --bucket YOUR-BUCKET-NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
```

> [!warning]
> The "alternative" option makes the bucket capable of hosting public objects. You are responsible for ensuring no sensitive files are uploaded to the `pub/` prefix.

---

## 3. Lifecycle configuration

Loft tags every object with `ttl=1d`, `ttl=30d`, or `ttl=none`. Lifecycle rules filter on those tags and expire matching objects automatically.

> [!note]
> AWS evaluates lifecycle rules once per day, typically at midnight UTC. Actual deletion may lag up to ~24 hours past the nominal expiry time. This is expected behaviour — do not rely on S3 lifecycle for sub-hour precision.

### lifecycle.json

Save this file locally as `lifecycle.json`:

```json
{
  "Rules": [
    {
      "ID": "loft-expire-1d",
      "Status": "Enabled",
      "Filter": {
        "Tag": {
          "Key": "ttl",
          "Value": "1d"
        }
      },
      "Expiration": {
        "Days": 1
      }
    },
    {
      "ID": "loft-expire-30d",
      "Status": "Enabled",
      "Filter": {
        "Tag": {
          "Key": "ttl",
          "Value": "30d"
        }
      },
      "Expiration": {
        "Days": 30
      }
    }
  ]
}
```

### Apply the lifecycle configuration

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket YOUR-BUCKET-NAME \
  --lifecycle-configuration file://lifecycle.json
```

Verify it was applied:

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket YOUR-BUCKET-NAME
```

---

## 4. CORS configuration

CORS is not required for the uploader itself (uploads originate from a native app, not a browser). It is needed if you add in-app preview or build a web-based history page. Apply it now to avoid revisiting later.

### cors.json

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": ["*"],
      "AllowedMethods": ["GET", "PUT", "HEAD"],
      "AllowedHeaders": ["*"],
      "MaxAgeSeconds": 3000
    }
  ]
}
```

> [!tip]
> Tighten `AllowedOrigins` to your actual domain once you know it. Using `*` is fine for personal use.

```bash
aws s3api put-bucket-cors \
  --bucket YOUR-BUCKET-NAME \
  --cors-configuration file://cors.json
```

---

## 5. Bucket policy for public access (skip if using CloudFront)

If you chose the "alternative" public access block in step 2, apply this bucket policy to allow `GetObject` on the `pub/` prefix only:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadPubPrefix",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/pub/*"
    }
  ]
}
```

Save as `bucket-policy.json`, then apply:

```bash
aws s3api put-bucket-policy \
  --bucket YOUR-BUCKET-NAME \
  --policy file://bucket-policy.json
```

> [!warning]
> This makes every object under `pub/` publicly readable on the internet. Never upload private or sensitive files using the Public pane.

---

## 6. Object tag reference

Every object Loft uploads receives these three tags:

| Tag | Values | Purpose |
|-----|--------|---------|
| `app` | `loft` | Identify objects owned by this app |
| `ttl` | `1d`, `30d`, `none` | Drives lifecycle rules |
| `uploaded_at` | Unix epoch (seconds) | Audit trail |

The `ttl=none` tag is applied to Private and Public pane uploads. Those objects are never expired by the lifecycle rules above.

---

## 7. Key prefix layout

```
YOUR-BUCKET-NAME/
├── private/   ← Private pane (presigned GET URLs, 7-day expiry)
├── tmp1d/     ← 1-day pane (ttl=1d tag, lifecycle expires after 1 day)
├── tmp30d/    ← 30-day pane (ttl=30d tag, lifecycle expires after 30 days)
└── pub/       ← Public pane (public-read ACL or CloudFront)
```

Each pane prefix is configurable in **Settings → Panes**.

---

## Related

- [[IAM Policy]] — minimal IAM permissions and how to create a dedicated user
- [[Custom Endpoints]] — using this bucket setup with R2, B2, MinIO, or Spaces
- [[CloudFront OAC]] — recommended alternative to direct public S3 access
- [[Loft Overview]]
