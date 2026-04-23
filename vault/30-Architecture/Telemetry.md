---
title: Telemetry
tags: [architecture, telemetry, sentry, privacy]
project: Loft
created: 2026-04-23
---

# Telemetry

Loft uses [Sentry](https://sentry.io) for crash reporting and aggregated usage metrics. Everything is off-by-default opt-out — the user sees the toggle in **Settings → General → Privacy** and can flip it off at any time. Nothing identifying leaves the device.

## Dashboard

- **Project:** [loft-app on Sentry](https://felobo.sentry.io/insights/projects/loft-app)
- **DSN (embedded in the app):** `https://ec89cc6c55988f5bf280b53ecf98f654@o157871.ingest.us.sentry.io/4511268741644288`

> [!info] DSNs are public
> Sentry DSNs are designed to be shipped with client apps. They identify the project, not the user, and aren't secrets.

## What we collect

| Category | What | Source |
|---|---|---|
| Crashes | Mach exceptions, signals, Swift runtime errors | Sentry SDK auto-instrumentation |
| App hangs | Main-thread stalls > default threshold | `enableAppHangTracking = true` |
| Sessions | One heartbeat per app launch, auto-closed after 30s idle | `enableAutoSessionTracking = true` |
| Handled errors | Upload failures (with pane name, size, stage — no file name, no URL) | `Telemetry.capture(error:)` in `UploadQueue` |
| Usage breadcrumbs | `app.launched`, `upload.enqueued`, `upload.succeeded`, `upload.cancelled` | `Telemetry.event(_:)` from hot paths |

Breadcrumbs ride along with crash/error events — they never turn into standalone events, so they don't burn through the error quota.

## What we do NOT collect

- File names, object keys, bucket names, endpoints
- Generated URLs (public or private)
- AWS credentials or any keychain data
- IP address beyond what Sentry's ingest needs to route (Sentry strips it from events with `sendDefaultPii = false`)
- Any per-user identifier — no login, no device UUID tagging
- Clipboard contents

## Configuration

All telemetry is set up in [`Sources/Loft/Telemetry/Telemetry.swift`](../../Sources/Loft/Telemetry/Telemetry.swift):

```swift
SentrySDK.start { options in
    options.dsn = dsn
    options.releaseName = "loft@\(appVersion)"
    options.environment = "debug" | "release"
    options.enableAutoSessionTracking = true
    options.sendDefaultPii = false          // strips IPs, usernames
    options.tracesSampleRate = 0.2          // 20% transaction sampling
    options.enableAppHangTracking = true
    options.enableCrashHandler = true
    options.attachStacktrace = true
    options.maxBreadcrumbs = 50
}
```

Releases are tagged as `loft@<CFBundleShortVersionString>` so the Sentry **Releases** view groups crashes per published version. Debug vs release builds are tagged via the `build.type` / `environment` field — filter those out on the dashboard when you care only about production.

## Opt-out flow

The user can toggle telemetry off in **Settings → General → Privacy**:

1. `AppConfig.analyticsEnabled` flips to `false`
2. `Telemetry.startIfEnabled()` is called again
3. When currently running, it calls `SentrySDK.close()` and sets `started = false`
4. Subsequent `Telemetry.event` / `Telemetry.capture` calls become no-ops

No data is sent between the toggle flip and the next process launch. Any cached events written to disk by Sentry's envelope store are flushed on `close()`.

## Read the data

- [Issues](https://felobo.sentry.io/issues/?project=4511268741644288) — grouped crashes and handled errors
- [Performance](https://felobo.sentry.io/performance/?project=4511268741644288) — transaction traces (20% sampled)
- [Releases](https://felobo.sentry.io/releases/?project=4511268741644288) — per-version adoption, crash-free sessions, regressions
- [Discover](https://felobo.sentry.io/discover/?project=4511268741644288) — ad-hoc queries across events and breadcrumbs

For usage funnels, query breadcrumbs via Discover (`breadcrumb.category:usage`) or look at the **Releases → Session Health** view for "users" (anonymous sessions) and crash-free rates.

## Adding new events

Any time you add a new telemetry-worthy action, use the two helpers:

```swift
// Low-volume event, attached as context to any later crash in this session
Telemetry.event("settings.changed", data: ["field": "bucket"])

// Handled error you want to see on the dashboard
Telemetry.capture(error, context: ["where": "bucket-probe"])
```

Never pass file names, URLs, or credentials as breadcrumb data — only enums, sizes, durations, pane names. If in doubt, leave it out.

## Related

- [[Architecture Overview]]
- [[Settings]]
- [[Upload Pipeline]]
