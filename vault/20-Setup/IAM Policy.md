---
title: IAM Policy
tags: [setup, aws, iam, security]
project: Loft
created: 2026-04-23
---

# IAM Policy

Loft needs only a narrow set of S3 permissions scoped to a single bucket. This page provides a copy-pasteable minimal IAM policy, explains each statement, and shows how to create a dedicated IAM user with an access key.

> [!warning]
> Never use root account credentials in Loft. Root credentials have unlimited access to your entire AWS account. A compromised access key would be catastrophic. Use a dedicated IAM user with only the permissions listed here.

---

## Why not root credentials

AWS root credentials:
- Cannot be scoped — they have access to every service and every resource
- Cannot be rotated easily without disrupting everything
- Are the keys to your entire AWS account and billing

A dedicated IAM user with this policy can only touch one named bucket. If the key leaks, you delete the user and the damage is contained.

---

## Minimal IAM policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBucketDiscovery",
      "Effect": "Allow",
      "Action": [
        "s3:HeadBucket"
      ],
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME"
    },
    {
      "Sid": "AllowObjectUploadAndTag",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectTagging",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*"
    },
    {
      "Sid": "AllowPublicAclOnPubPrefix",
      "Effect": "Allow",
      "Action": [
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/pub/*"
    },
    {
      "Sid": "AllowDeleteForHistory",
      "Effect": "Allow",
      "Action": [
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*"
    }
  ]
}
```

Replace `YOUR-BUCKET-NAME` with your actual bucket name before applying.

---

## Statement-by-statement explanation

### `AllowBucketDiscovery` — `s3:HeadBucket` on the bucket ARN

Loft calls `HeadBucket` when you save credentials in Settings to verify the bucket exists and the credentials are valid. This action requires permission on the bucket ARN itself (no trailing `/*`).

### `AllowObjectUploadAndTag` — `s3:PutObject`, `s3:PutObjectTagging`, `s3:GetObject` on all objects

- **`PutObject`** — uploads files. Loft sends tags inline via `x-amz-tagging`; some SDK versions require a separate `PutObjectTagging` call.
- **`PutObjectTagging`** — adds or replaces the `app`, `ttl`, and `uploaded_at` tags after upload if needed.
- **`GetObject`** — required to generate presigned GET URLs for the Private pane. The URL is signed with the user's credentials; the recipient uses the URL to download the object without needing AWS credentials themselves.

### `AllowPublicAclOnPubPrefix` — `s3:PutObjectAcl` scoped to `pub/*`

The Public pane sets `x-amz-acl: public-read` on each upload. This permission is scoped to the `pub/` prefix so the user cannot accidentally make a private or temporary file public. If you use CloudFront OAC (recommended), you can omit this statement entirely — see [[CloudFront OAC]].

### `AllowDeleteForHistory` — `s3:DeleteObject` on all objects

The History panel lets you delete an uploaded file from S3. Scope this to `pub/*` only if you want to prevent deletion of private/temporary objects from the app.

---

## Creating the IAM user

### Step 1 — Create the user

```bash
aws iam create-user --user-name loft-uploader
```

### Step 2 — Create the policy document

Save the JSON above as `loft-policy.json` (with your bucket name substituted in), then create the managed policy:

```bash
aws iam create-policy \
  --policy-name LoftS3Policy \
  --policy-document file://loft-policy.json
```

The command outputs an ARN like `arn:aws:iam::123456789012:policy/LoftS3Policy`. Copy it.

### Step 3 — Attach the policy to the user

```bash
aws iam attach-user-policy \
  --user-name loft-uploader \
  --policy-arn arn:aws:iam::123456789012:policy/LoftS3Policy
```

### Step 4 — Generate an access key

```bash
aws iam create-access-key --user-name loft-uploader
```

The output includes `AccessKeyId` and `SecretAccessKey`. This is the **only time** the secret is shown — copy it immediately.

```json
{
  "AccessKey": {
    "UserName": "loft-uploader",
    "AccessKeyId": "AKIAIOSFODNN7EXAMPLE",
    "Status": "Active",
    "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    "CreateDate": "2026-04-23T00:00:00Z"
  }
}
```

### Step 5 — Enter credentials in Loft

Open Loft → **Settings (⌘,)** → **AWS** tab → paste the Access Key ID and Secret Access Key. Loft stores them in the macOS Keychain — they are never written to disk in plaintext.

---

## Rotating the access key

AWS recommends rotating access keys every 90 days.

```bash
# Create a new key first
aws iam create-access-key --user-name loft-uploader

# Update Loft Settings with the new key — verify it works

# Then deactivate and delete the old key
aws iam update-access-key \
  --user-name loft-uploader \
  --access-key-id OLDKEYID \
  --status Inactive

aws iam delete-access-key \
  --user-name loft-uploader \
  --access-key-id OLDKEYID
```

> [!tip]
> Never delete an old key before the new key is confirmed working in Loft.

---

## Revoking access immediately

If the key is compromised:

```bash
aws iam delete-access-key \
  --user-name loft-uploader \
  --access-key-id COMPROMISEDKEYID
```

This takes effect immediately. Uploads will fail until you generate and enter a new key.

---

## Related

- [[Bucket Setup]] — bucket creation, lifecycle rules, CORS, and bucket policy
- [[Custom Endpoints]] — IAM does not apply to R2/B2/MinIO — see provider-specific auth
- [[Loft Overview]]
