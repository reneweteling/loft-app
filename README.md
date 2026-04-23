# EasyUp

A native macOS menu bar app for uploading files to S3 — drag, drop, get a link.

## Features

- Menu bar popover with four upload panes: Private, 1 Day, 30 Days, Public
- Drag a file or folder onto a pane to upload; folders are zipped on the fly via `ditto`
- Files larger than 5 MB use multipart upload automatically (8 MB parts, 4 concurrent)
- TTL panes enforce expiry via S3 lifecycle rules on object tags (`ttl=1d`, `ttl=30d`)
- Click a success notification to copy the URL to the clipboard
- Upload history (last 100 entries) with re-copy, open-in-browser, and remove
- Custom S3 endpoints: Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces
- Launch at login toggle in Settings → General
- Built with Swift 5.9 + SwiftUI, requires no Xcode project — SwiftPM only

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools

```bash
xcode-select --install
```

## Quick Start

```bash
git clone <repo-url> easyup
cd easyup
./scripts/build.sh
cp -R build/EasyUp.app /Applications/
```

First launch: right-click `EasyUp.app` in `/Applications/` and choose **Open**. This is required once because the app is ad-hoc signed and not notarized.

## First-Run Setup

1. Click the EasyUp icon in the menu bar. A popover appears with a setup prompt.
2. Click **Open Settings** (or press `⌘,`).
3. Go to the **S3** tab.
4. Enter your **Access Key ID**, **Secret Access Key**, **Region**, and **Bucket** name.
5. Optionally enter a **Custom endpoint** if you are using an S3-compatible service (see [vault/20-Setup/Custom Endpoints.md](vault/20-Setup/Custom%20Endpoints.md)).
6. Click **Test Connection** to verify credentials.
7. Close Settings. The popover now shows the four upload panes.

## Uploading Files

Drag one or more files onto any of the four panes in the popover:

| Pane | Visibility | Expiry |
|---|---|---|
| Private | Private (signed URLs not generated) | None |
| 1 Day | Public | Deleted after 1 day via lifecycle rule |
| 30 Days | Public | Deleted after 30 days via lifecycle rule |
| Public | Public | No expiry |

Dropping a **folder** zips its contents with `/usr/bin/ditto` and uploads a single `.zip` archive.

Files over **5 MB** switch automatically to multipart upload (8 MB chunks, 4 concurrent parts).

On success, a system notification appears. **Click the notification** to copy the public URL to the clipboard.

## TTL Lifecycle Rules

The 1 Day and 30 Days panes rely on S3 lifecycle rules that expire objects tagged with `ttl=1d` or `ttl=30d`. These rules are not created automatically — you must configure them once in your bucket.

See `vault/20-Setup/Bucket Setup.md` for the exact AWS CLI one-liners.

## IAM Policy

EasyUp needs a narrow set of S3 permissions: `s3:PutObject`, `s3:DeleteObject`, `s3:GetBucketLocation`, and `s3:ListBucket` scoped to your bucket. It does not need account-wide access. Create a dedicated IAM user with a policy that grants only these actions on the specific bucket ARN and its objects. See `vault/20-Setup/IAM Policy.md` for the exact policy JSON and instructions for creating the user and generating access keys.

## Project Layout

```
Package.swift              SwiftPM manifest
Sources/EasyUp/            Application source (Swift)
scripts/
  build.sh                 Builds and ad-hoc signs EasyUp.app
build/
  EasyUp.app               Output of build.sh (git-ignored)
vault/                     Obsidian vault — setup guides and architecture notes
```

## Documentation (vault/)

The `vault/` folder is an Obsidian vault containing complete setup guides, architecture notes, and reference material. Open it with [Obsidian](https://obsidian.md) for the best reading experience, or read the Markdown files directly.

Key pages to read first:

- `vault/20-Setup/Bucket Setup.md` — S3 bucket configuration, lifecycle rules, and CORS
- `vault/20-Setup/IAM Policy.md` — minimal IAM policy JSON and user setup
- `vault/20-Setup/Custom Endpoints.md` — connecting to R2, B2, MinIO, and Spaces
- `vault/10-Architecture/` — design decisions and component overview

## Troubleshooting

### Gatekeeper "cannot be opened" error

If macOS refuses to open the app after copying it to `/Applications/`, strip the quarantine attribute:

```bash
xattr -dr com.apple.quarantine /Applications/EasyUp.app
```

Then double-click the app normally.

### Test Connection fails

- Double-check the region matches the bucket's actual region.
- Confirm the IAM user has `s3:GetBucketLocation` and `s3:ListBucket` on the bucket ARN (not just on objects).
- If using a custom endpoint, make sure the URL includes the scheme (`https://`) and no trailing slash.

### Uploads silently fail or hang

- Check that the bucket policy does not block the IAM user via an explicit Deny.
- For multipart uploads, the IAM policy also needs `s3:CreateMultipartUpload`, `s3:UploadPart`, `s3:CompleteMultipartUpload`, and `s3:AbortMultipartUpload`. The `vault/20-Setup/IAM Policy.md` policy includes all of these.

## License

Personal project — use at your own risk. Not distributed under any OSS license yet.
# loft-app
