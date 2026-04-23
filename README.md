# Loft

Drag a file to your menu bar. Get a link back.

![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange?logo=swift) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)

## What it does

- **Drag and drop** a file (or folder) onto the menu bar popover — folders are zipped on the fly
- **Four TTL panes** — Private, 1 Day, 30 Days, Public — each enforcing expiry via S3 lifecycle tags
- **Multipart upload** for large files (8 MB parts, 4 concurrent) so big transfers don't stall
- **Custom S3 endpoints** out of the box: Cloudflare R2, Backblaze B2, MinIO, DigitalOcean Spaces

## Install

```bash
git clone https://github.com/reneweteling/loft.git
cd loft
./scripts/build.sh
cp -R build/Loft.app /Applications/
```

First launch: **right-click `Loft.app` → Open** to clear Gatekeeper (required once — the app is ad-hoc signed, not notarized).

## Setup

1. **Create your bucket** — follow [`vault/20-Setup/Bucket Setup.md`](vault/20-Setup/Bucket%20Setup.md) for lifecycle rules and CORS.
2. **Create an IAM user** with the minimal policy in [`vault/20-Setup/IAM Policy.md`](vault/20-Setup/IAM%20Policy.md).
3. **Open Loft Settings** (`⌘,`) → **S3 tab** — enter Access Key ID, Secret Access Key, Region, Bucket, and (optionally) a custom endpoint.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools

```bash
xcode-select --install
```

## Project layout

```
Package.swift              SwiftPM manifest
Sources/Loft/              Application source (Swift 5.9 + SwiftUI)
scripts/
  build.sh                 Builds and ad-hoc signs Loft.app
build/
  Loft.app                 Output of build.sh (git-ignored)
vault/                     Obsidian vault — setup guides and architecture notes
docs/                      GitHub Pages site
```

## Documentation

The `vault/` folder is an Obsidian vault with complete setup guides and architecture notes. Open it with [Obsidian](https://obsidian.md) or read the Markdown files directly. The GitHub Pages site at [reneweteling.github.io/loft](https://reneweteling.github.io/loft) has a quick-start overview.

Key pages:

- `vault/20-Setup/Bucket Setup.md` — lifecycle rules and CORS
- `vault/20-Setup/IAM Policy.md` — minimal IAM policy JSON
- `vault/10-Architecture/` — design decisions and component overview

## Troubleshooting

**Gatekeeper blocks the app** — strip quarantine and reopen:

```bash
xattr -dr com.apple.quarantine /Applications/Loft.app
```

**Test Connection fails** — confirm the region matches the bucket, and that the IAM user has `s3:GetBucketLocation` and `s3:ListBucket` on the bucket ARN (not just objects).

**Uploads fail silently** — for multipart, the policy also needs `s3:CreateMultipartUpload`, `s3:UploadPart`, `s3:CompleteMultipartUpload`, and `s3:AbortMultipartUpload`. The policy template in `vault/20-Setup/IAM Policy.md` covers all of these.

## License

Copyright © 2026 Felobo B.V. All rights reserved.
