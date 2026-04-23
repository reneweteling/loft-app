---
title: Custom Endpoints
tags: [setup, s3, r2, b2, minio, spaces, compatibility]
project: Loft
created: 2026-04-23
---

# Custom Endpoints

Loft supports any S3-compatible storage provider by letting you set a custom endpoint URL in **Settings → S3**. The AWS SDK for Swift sends all requests to that endpoint instead of `s3.amazonaws.com`.

The IAM policy in [[IAM Policy]] is AWS-specific. Each provider below has its own access key/secret mechanism — see the provider's documentation for creating API credentials.

---

## How to configure in Loft

1. Open **Settings (⌘,)** → **S3** tab
2. Set **Access Key ID** and **Secret Access Key** to your provider's credentials
3. Set **Region** to the value specified per provider below
4. Paste the **Custom Endpoint URL** from the relevant section below
5. Enable **Force Path-Style** if the provider requires it (noted per provider)
6. Optionally set a **CDN Base URL** in the **Public URL** section of the S3 tab to rewrite public URLs

---

## Cloudflare R2

Cloudflare R2 is an S3-compatible object store with zero egress fees. It is an excellent choice for the Public pane.

**Endpoint URL format:**

```
https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

Find your Account ID in the Cloudflare dashboard under **R2 → Overview**.

**Settings:**

| Setting | Value |
|---------|-------|
| Endpoint URL | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |
| Region | `auto` |
| Force Path-Style | No (virtual-hosted-style works) |

**Credentials:** Create an R2 API token in the Cloudflare dashboard under **R2 → Manage R2 API Tokens**. Select **Object Read & Write** permissions scoped to your bucket.

**CDN notes:** R2 supports a custom domain on each bucket (set in the Cloudflare dashboard). Once configured, set that domain as the CDN Base URL in Loft so public URLs use your domain instead of the R2 endpoint. R2 also integrates with Cloudflare's global CDN automatically when a custom domain is attached.

> [!tip]
> R2 does not charge for egress bandwidth. If you share many large files publicly, R2 is significantly cheaper than AWS S3.

**Lifecycle rules:** R2 supports S3-compatible lifecycle rules. Apply the same `lifecycle.json` from [[Bucket Setup]] using the R2 endpoint:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket YOUR-BUCKET-NAME \
  --endpoint-url https://<ACCOUNT_ID>.r2.cloudflarestorage.com \
  --lifecycle-configuration file://lifecycle.json
```

---

## Backblaze B2

Backblaze B2 offers S3-compatible access via its S3-compatible API. Egress is free when served via Cloudflare (the Bandwidth Alliance partnership).

**Endpoint URL format:**

```
https://s3.<REGION>.backblazeb2.com
```

Common regions: `us-west-004`, `eu-central-003`. Find your bucket's region in the B2 dashboard under **Buckets → Bucket Details**.

**Settings:**

| Setting | Value |
|---------|-------|
| Endpoint URL | `https://s3.<REGION>.backblazeb2.com` |
| Region | Same as the region in the endpoint (e.g. `us-west-004`) |
| Force Path-Style | No |

**Credentials:** Create an Application Key in the B2 dashboard under **Account → Application Keys**. Select **Read and Write** access scoped to your bucket. The Key ID maps to Access Key ID; the Application Key maps to Secret Access Key.

**CDN notes:** B2 buckets can be fronted by Cloudflare for free egress. Set the Cloudflare-proxied hostname as your CDN Base URL. B2's own download URL (`f<NNN>.backblazeb2.com`) works too but incurs egress fees beyond the free tier.

> [!note]
> B2 lifecycle rules use a different format than AWS — tag-based expiry is not supported. You must use B2's "Lifecycle Settings" (days until hidden/deleted) in the dashboard, which applies to all objects, not per-tag. This means the 1-day and 30-day TTL panes will need manual cleanup or a separate bucket per TTL tier on B2.

---

## MinIO

MinIO is a self-hosted S3-compatible server. Common use cases: local development, on-prem NAS (Synology, QNAP), homelab.

**Endpoint URL format:**

MinIO does not use virtual-hosted-style by default. Use your server's base URL:

```
http://YOUR-MINIO-HOST:9000
```

or with TLS:

```
https://minio.internal.example.com
```

**Settings:**

| Setting | Value |
|---------|-------|
| Endpoint URL | `http://YOUR-MINIO-HOST:9000` (or HTTPS) |
| Region | `us-east-1` (MinIO accepts any value; use this as a safe default) |
| Force Path-Style | **Yes** — required for MinIO |

> [!warning]
> **Force Path-Style must be enabled for MinIO.** Without it, the SDK constructs URLs like `https://YOUR-BUCKET.YOUR-MINIO-HOST:9000/` which will not resolve on a self-hosted setup.

**Credentials:** Create an access key in the MinIO Console under **Identity → Service Accounts**, or via the CLI:

```bash
mc admin user add myminio loft-user SECRETPASSWORD
mc admin policy attach myminio readwrite --user loft-user
```

**CDN notes:** MinIO does not have a built-in CDN. For local use, direct URLs work fine. For remote access, put nginx or Caddy in front and set its base URL as the CDN URL in Loft.

**Lifecycle rules:** MinIO supports S3-compatible lifecycle rules. Apply `lifecycle.json` from [[Bucket Setup]] using your MinIO endpoint:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket YOUR-BUCKET-NAME \
  --endpoint-url http://YOUR-MINIO-HOST:9000 \
  --lifecycle-configuration file://lifecycle.json
```

> [!tip]
> For local development and CI testing, MinIO in Docker is the recommended setup. It gives you a real S3-compatible endpoint without incurring AWS costs. See the Verification section in the project plan for the integration test setup.

---

## DigitalOcean Spaces

DigitalOcean Spaces is an S3-compatible object store with a built-in CDN (Spaces CDN, powered by Cloudflare).

**Endpoint URL format:**

```
https://<REGION>.digitaloceanspaces.com
```

Available regions: `nyc3`, `sfo3`, `ams3`, `sgp1`, `fra1`.

**Settings:**

| Setting | Value |
|---------|-------|
| Endpoint URL | `https://<REGION>.digitaloceanspaces.com` |
| Region | Same region code (e.g. `nyc3`) |
| Force Path-Style | No |

**Credentials:** Generate a Spaces access key in the DigitalOcean dashboard under **API → Spaces Keys**. This is separate from your DO personal access token.

**CDN notes:** Each Space can have its CDN endpoint enabled in the dashboard. The CDN URL format is:

```
https://<BUCKET-NAME>.<REGION>.cdn.digitaloceanspaces.com
```

Set this as the CDN Base URL in Loft's S3 tab (Public URL section) so public files are served through the CDN.

**Lifecycle rules:** DigitalOcean Spaces supports S3-compatible lifecycle rules. Apply `lifecycle.json` from [[Bucket Setup]]:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket YOUR-BUCKET-NAME \
  --endpoint-url https://<REGION>.digitaloceanspaces.com \
  --lifecycle-configuration file://lifecycle.json
```

> [!note]
> Spaces does not support tag-based lifecycle filtering as of early 2026. Rules apply to prefixes only. If you need tag-based TTL on Spaces, use one Space per TTL tier and configure separate Loft buckets per pane.

---

## Provider comparison

| Provider | Tag-based lifecycle | Zero-egress CDN | Path-style required | Free tier |
|----------|-------------------|-----------------|--------------------|-----------| 
| AWS S3 | Yes | No (CloudFront extra) | No | 5 GB / 12 mo |
| Cloudflare R2 | Yes | Yes (Cloudflare) | No | 10 GB / mo |
| Backblaze B2 | No (prefix only) | Yes (via CF) | No | 10 GB |
| MinIO (self-hosted) | Yes | No (DIY) | **Yes** | Free |
| DigitalOcean Spaces | No (prefix only) | Yes (built-in) | No | 250 GB / mo |

---

## Related

- [[Bucket Setup]] — lifecycle.json and CORS that apply to any provider
- [[IAM Policy]] — AWS-specific; each provider has its own credential system
- [[CloudFront OAC]] — AWS S3 + CloudFront CDN setup
- [[Loft Overview]]
