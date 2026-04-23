---
title: Telemetry
tags: [architecture, telemetry, sentry, posthog, analytics, privacy]
project: Loft
created: 2026-04-23
---

# Telemetry

Loft runs two complementary observability stacks. Both share a **single user-facing opt-out toggle** in **Settings → General → Privacy** — flipping it off stops both at once.

| Stack | Wrapper | What it's for |
|---|---|---|
| [Sentry](https://sentry.io) | [`Telemetry`](../../Sources/Loft/Telemetry/Telemetry.swift) | Crashes, app hangs, handled errors, anonymous sessions |
| [PostHog](https://posthog.com) | [`Analytics`](../../Sources/Loft/Telemetry/Analytics.swift) | Product usage (launches, uploads, pane popularity, file-size distributions) |

Nothing identifying leaves the device — no file names, URLs, credentials, bucket names, or per-user identifiers in either stack. See [Privacy](#privacy) for the full non-collection list.

## Dashboards

| Stack | Dashboard | Ingest key (embedded) |
|---|---|---|
| Sentry | [felobo.sentry.io → loft-app](https://felobo.sentry.io/insights/projects/loft-app) | DSN `https://ec89cc6c55988f5bf280b53ecf98f654@o157871.ingest.us.sentry.io/4511268741644288` |
| PostHog | [us.posthog.com → project 394104](https://us.posthog.com/project/394104) | Project token `phc_mPXSh3Dk9gDnJ94YRwSt2LBdZVpfUDvCZczTnW9Xp9Kp` |

> [!info] These keys are public
> Both the Sentry DSN and the PostHog project token (prefix `phc_`) are **designed to be shipped in the client**. They identify the project, not the user, and have write-only scope (ingest events — can't read the dashboards). Never confuse them with management tokens (Sentry auth token, PostHog personal key prefix `phx_`), which ARE secrets and live in `.envrc`, not source.

## What Sentry collects

| Category | What | Source |
|---|---|---|
| Crashes | Mach exceptions, signals, Swift runtime errors | Sentry SDK auto-instrumentation |
| App hangs | Main-thread stalls > default threshold | `enableAppHangTracking = true` |
| Sessions | One heartbeat per app launch, auto-closed after 30s idle | `enableAutoSessionTracking = true` |
| Handled errors | Upload failures (with pane name, size, stage — no file name, no URL) | `Telemetry.capture(error:)` in `UploadQueue` |
| Usage breadcrumbs | `app.launched`, `upload.enqueued`, `upload.succeeded`, `upload.cancelled` | `Telemetry.event(_:)` from hot paths |

Breadcrumbs ride along with crash/error events — they never turn into standalone events, so they don't burn through the error quota.

## What PostHog collects

| Event | Properties | When |
|---|---|---|
| `app.launched` | `app_version`, `build_type` | `AppDelegate.applicationDidFinishLaunching` |
| `Application Installed` | auto | First run on this device (PostHog lifecycle) |
| `Application Opened` | auto | Every launch (PostHog lifecycle) |
| `Application Backgrounded` | auto | App moves to background (PostHog lifecycle) |
| `upload.enqueued` | `pane`, `ttl`, `visibility`, `sizeBytes` | File dropped on a pane |
| `upload.succeeded` | `pane`, `sizeBytes` | Upload completes OK |
| `upload.cancelled` | `pane` | User hits × during upload |
| `upload.failed` | `pane`, `sizeBytes`, `error` (Swift error type name) | Upload errors |

`app_version` and `build_type` (`debug`/`release`) are registered as super-properties so every event carries them automatically.

### Free-tier headroom

PostHog Cloud's free tier is **1 million events per month**. At a plausible 20 events/active user/day, Loft could hit ~1,600 DAU before brushing the ceiling. Quota usage lives in the [PostHog billing page](https://us.posthog.com/organization/billing).

## Privacy

What **neither** Sentry nor PostHog ever receives:

- File names, object keys, bucket names, endpoints
- Generated URLs (public or private)
- AWS credentials, Keychain contents
- Login, email, or identifying device UUIDs
- Clipboard contents, window titles, app chrome screenshots

Sentry strips the request IP from events via `sendDefaultPii = false`. PostHog receives only `app_version`, `build_type`, and the event properties listed above — `captureScreenViews` is **off** (nothing to capture in a menu-bar app) and session replay is disabled on macOS by default.

## Configuration

### Sentry — [`Telemetry.swift`](../../Sources/Loft/Telemetry/Telemetry.swift)

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

Releases are tagged as `loft@<CFBundleShortVersionString>` so the Sentry **Releases** view groups crashes per published version.

### PostHog — [`Analytics.swift`](../../Sources/Loft/Telemetry/Analytics.swift)

```swift
let config = PostHogConfig(apiKey: projectKey, host: "https://us.i.posthog.com")
config.captureApplicationLifecycleEvents = true    // Installed/Opened/Backgrounded
config.captureScreenViews = false                  // nothing to route in a menu-bar app
config.flushAt = 20
config.flushIntervalSeconds = 30
PostHogSDK.shared.setup(config)
PostHogSDK.shared.register([
    "app_version": appVersion,
    "build_type": buildType
])
```

The batch flushes either when 20 events queue up or every 30 seconds, whichever first. On app shutdown the SDK drains its queue before the process exits.

## Opt-out flow

The user can toggle everything off in **Settings → General → Privacy** ("Share anonymous crash reports and usage"):

1. `AppConfig.analyticsEnabled` flips to `false`
2. `Telemetry.startIfEnabled()` and `Analytics.startIfEnabled()` are both called
3. Each calls `SentrySDK.close()` / `PostHogSDK.shared.close()` and sets its local `started` flag to `false`
4. Subsequent event / capture calls become no-ops

No data is sent between the toggle flip and the next process launch. Any cached events written to disk by Sentry's envelope store or PostHog's queue are flushed on `close()`.

## Read the data

### Sentry

- [Issues](https://felobo.sentry.io/issues/?project=4511268741644288) — grouped crashes and handled errors
- [Performance](https://felobo.sentry.io/performance/?project=4511268741644288) — transaction traces (20% sampled)
- [Releases](https://felobo.sentry.io/releases/?project=4511268741644288) — per-version adoption, crash-free sessions, regressions
- [Discover](https://felobo.sentry.io/discover/?project=4511268741644288) — ad-hoc queries across events and breadcrumbs

### PostHog

- [Activity / Events feed](https://us.posthog.com/project/394104/activity/explore) — raw event stream
- [Insights](https://us.posthog.com/project/394104/insights) — custom charts (uploads per pane, DAU, retention)
- [Funnels](https://us.posthog.com/project/394104/insights) — e.g. `app.launched → upload.enqueued → upload.succeeded`
- [Replay](https://us.posthog.com/project/394104/replay) — disabled by config; no recordings are collected

## Adding new events

Any time you add a telemetry-worthy action, call BOTH stacks with the same event name and data. Sentry keeps it as context for future crashes; PostHog makes it queryable on its own.

```swift
let props: [String: Any] = ["pane": pane.name, "source": "menubar-drag"]
Telemetry.event("settings.changed", data: props)
Analytics.event("settings.changed", properties: props)
```

For handled errors, also call `Telemetry.capture(error, context:)` so Sentry sees them as grouped issues rather than anonymous failures:

```swift
Telemetry.capture(error, context: ["where": "bucket-probe"])
Analytics.event("bucket.probe.failed", properties: ["error": String(describing: type(of: error))])
```

Never pass file names, URLs, or credentials in properties — only enums, sizes, durations, pane names. If in doubt, leave it out.

## Related

- [[Architecture Overview]]
- [[Settings]]
- [[Upload Pipeline]]
