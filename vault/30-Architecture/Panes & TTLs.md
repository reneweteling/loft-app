---
title: Panes & TTLs
tags: [architecture, panes, ttl, s3, lifecycle]
project: Loft
created: 2026-04-23
---

# Panes & TTLs

Loft's popover presents a row of "panes" — named drop targets that each encode a visibility policy and a time-to-live for the uploaded object. The pane model is user-configurable in [[Settings]], but four panes are seeded on first launch.

## The four default panes

### Private

Files dropped onto Private are uploaded to a private prefix with no public access. The result URL is a **SigV4 presigned GET URL** valid for 7 days — the maximum allowed by the AWS SigV4 specification (see [[Presigned URL Notes]]). After expiry the URL returns HTTP 403; the file itself remains in the bucket indefinitely unless the user deletes it. Use this pane for files you want to share briefly with a specific person without ever making them publicly accessible.

- TTL: none (object persists until manual deletion)
- URL type: presigned GET, 7-day expiry
- ACL: bucket default (private)
- Tag: `ttl=none`

### 1 Day

Files dropped onto 1 Day are tagged `ttl=1d`. A bucket lifecycle rule matches that tag and schedules deletion 1 day after object creation. Because AWS runs lifecycle evaluation once per day, actual deletion can lag by up to ~24 hours past the nominal expiry — communicate this to users so they do not expect minute-accurate deletion.

- TTL: ~24 hours (lifecycle-managed)
- URL type: raw S3 URL or CDN URL if configured
- ACL: depends on pane visibility setting (can be public-read or kept private with a CDN)
- Tag: `ttl=1d`

### 30 Days

Files dropped onto 30 Days are tagged `ttl=30d`. A second lifecycle rule matches that tag and schedules deletion 30 days after creation. Same lag caveat as 1 Day. Useful for sharing build artifacts, design files, or other temporary-but-not-ephemeral content.

- TTL: ~30 days (lifecycle-managed)
- URL type: raw S3 URL or CDN URL if configured
- ACL: depends on pane visibility setting
- Tag: `ttl=30d`

### Public

Files dropped onto Public get the `public-read` ACL (or CloudFront-OAC if a CDN base URL is configured) and no TTL. The result URL is a permanent raw S3 URL or CDN URL. Use this pane for assets you want to host indefinitely and reference from a web page or share broadly.

- TTL: none (object persists until manual deletion)
- URL type: raw S3 URL (`https://{bucket}.s3.{region}.amazonaws.com/{key}`) or CDN URL
- ACL: `public-read` on the S3 object, or bucket-private with CloudFront OAC
- Tag: `ttl=none`

> [!warning] Public bucket access
> To serve files with `public-read` ACL, the bucket's Block Public Access settings must have "Block public and cross-account access to buckets and objects through any public bucket or access point policies" disabled. The recommended alternative is to keep the bucket private and front it with a CloudFront distribution using Origin Access Control (OAC) — the URL is still publicly accessible but the bucket itself stays locked. Both paths are documented in the Setup section.

## How TTL is enforced

TTL enforcement is handled entirely by **native S3 lifecycle rules** — no Lambda sweeper, no CDK stack, no cron job.

Every uploaded object receives three tags:

| Tag key | Example value | Purpose |
|---|---|---|
| `app` | `loft` | Identifies uploads from this app |
| `ttl` | `1d`, `30d`, `none` | Lifecycle rule filter key |
| `uploaded_at` | `1745000000` | Unix epoch seconds, for auditability |

The bucket is configured with two lifecycle rules:

```
Rule 1:
  Filter: tag key=ttl, value=1d
  Action: Expire objects after 1 day

Rule 2:
  Filter: tag key=ttl, value=30d
  Action: Expire objects after 30 days
```

Objects tagged `ttl=none` match neither rule and persist indefinitely.

> [!info] Lifecycle evaluation timing
> AWS evaluates lifecycle rules approximately once per day. An object uploaded at 14:00 with `ttl=1d` may not be deleted until 38+ hours later depending on when the next evaluation window runs. This is an AWS platform constraint, not a bug.

## The `Pane` Swift struct

```swift
struct Pane: Codable, Identifiable {
    let id: UUID
    var name: String              // "Private", "1 Day", etc.
    var iconName: String
    var ttl: TTL                  // .none | .minutes(Int) | .days(Int)
    var visibility: Visibility    // .private | .public
    var bucket: String?           // override default bucket
    var keyPrefix: String         // e.g. "private/", "pub/", "tmp30d/"
    var order: Int                // display order
    var enabled: Bool
}
```

The `TTL` enum's `.days(Int)` case covers both 1-day and 30-day panes. The app writes the tag value as `"\(n)d"` and the lifecycle rules filter on the exact string values `1d` and `30d`. If the user adds a custom pane with a different day count, they must also add a matching lifecycle rule to the bucket manually (or via the AWS CLI one-liners in the Setup section).

`Pane` values are stored as JSON in `UserDefaults` (non-sensitive — no credentials). `AppConfig` owns the array and is the single source of truth for the popover layout. Changes in [[Settings]] → Panes tab are reflected immediately.

## Why the 30-minute pane was dropped

An earlier design included a 30-minute ephemeral pane. It was cut from v1 because S3 lifecycle rules operate on a per-day granularity — there is no native mechanism to expire objects in minutes. Implementing sub-day TTL correctly requires either:

- A **Lambda sweeper** triggered by EventBridge Scheduler (adds IAM, Lambda, scheduler cost and deployment complexity), or
- A **presigned URL** approach where the object is private and the URL itself expires in 30 minutes (the object lingers in the bucket).

Neither path is "one lifecycle rule". Rather than ship a pane that silently deletes files hours late or requires a CDK/Terraform stack, the decision was to drop it entirely for v1. The `TTL` enum retains `.minutes(Int)` so a 30-minute pane can be added in a future milestone once a sweeper strategy is chosen.

## URL type per pane

| Pane | CDN configured | URL returned |
|---|---|---|
| Private | any | Presigned GET, 7-day SigV4 expiry |
| 1 Day | no | Raw S3 URL |
| 1 Day | yes | CDN base URL + key |
| 30 Days | no | Raw S3 URL |
| 30 Days | yes | CDN base URL + key |
| Public | no | Raw S3 URL |
| Public | yes | CDN base URL + key |

`URLBuilder` in `Loft/Upload/URLBuilder.swift` encapsulates all branching logic. See [[Presigned URL Notes]] for signing details and [[Architecture Overview]] for where `URLBuilder` sits in the pipeline.

## Related

- [[Architecture Overview]]
- [[Upload Pipeline]]
- [[Settings]]
- [[Presigned URL Notes]]
- [[S3 Multipart Notes]]
- [[SigV4 Signing]]
- [[Loft Overview]]
