---
title: Loft Overview
tags: [moc, project, index]
project: Loft
created: 2026-04-23
---

# Loft Overview

Native macOS menu bar uploader for S3. Drag a file onto the menu bar icon → the popover opens with per-TTL drop panes → drop onto a pane → file is uploaded, URL copied on click of notification.

## Quick links

### Setup & running
- [[Bucket Setup]] — create the S3 bucket, lifecycle rules, IAM policy
- [[Gatekeeper Notes]] — installing the ad-hoc signed build

### Architecture
- [[Architecture Overview]]
- [[Panes & TTLs]]
- [[Upload Pipeline]]
- [[Settings]]
- [[Telemetry]] — Sentry crash reporting & anonymous usage

### Assets
- [[Image Prompts]] — OpenArt.ai prompts for all icons
- [[Brand & Palette]]
- [[Asset Inventory]]

### Reference
- [[S3 Multipart Notes]]
- [[Presigned URL Notes]]
- [[Glossary]]

## Status

- **Phase:** Pre-scaffold
- **Next milestone:** [M1 — Scaffold & menu bar presence](../../../.claude/plans/i-want-to-create-tidy-pretzel.md)
- **Platform:** macOS 14+, Swift 5.9 + SwiftUI

## Tags

#project/loft #macos #swiftui #s3
