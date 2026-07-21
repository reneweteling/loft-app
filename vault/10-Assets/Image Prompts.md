---
title: Image Prompts
tags: [assets, prompts, openart, icons]
project: Loft
created: 2026-04-23
updated: 2026-04-23
status: ready
---

# Image Prompts

Copy-paste prompts for [OpenArt.ai](https://openart.ai) to generate every visual asset Loft needs. Each prompt is self-contained and tuned for the model defaults on OpenArt — tweak style weights if needed.

Links: [[Loft Overview]] · [[Asset Inventory]] · [[Brand & Palette]]

---

## 1. App Icon

> **Destination:** `Assets.xcassets/AppIcon.appiconset` — required sizes: 16, 32, 64, 128, 256, 512, 1024 (both @1x and @2x).

**Prompt:**

```
macOS app icon, squircle rounded-rectangle shape per Apple Human Interface Guidelines, flat 3D isometric perspective with soft ambient occlusion.
Subject: a stylized upward arrow emerging from a tilted open folder, with a subtle cloud silhouette in the background.
Color palette: vibrant gradient from electric blue (#2E7CF6) to violet (#8A3FFC), white arrow, soft shadow beneath the shape.
No text, no letters, no wordmarks. Clean, premium, Sequoia-era macOS aesthetic.
Rendered at 1024x1024, centered, 10% padding, transparent background, PNG.
```

**Negative prompt:** `text, letters, watermark, border, frame, realistic photo, grainy, noisy, 3D rendered cartoon`

**Variations to try:**
- Swap violet for pink (`#EC4899`) for a warmer feel
- Replace folder with a document stack for "file-centric" variant
- Try holographic / glassmorphism styling for a more playful version

---

## 2. Menu Bar Icon (Template)

> **Destination:** `Assets.xcassets/MenuBarIcon.imageset` — export at 16, 22, 44 px. Must be a **template image** (pure black on transparent) so macOS tints it to match menu bar theme.

**Prompt:**

```
Minimalist monochrome vector glyph for a macOS menu bar status item.
Subject: an upward arrow passing through a horizontal line, stylized as an upload/drop target.
Pure black #000 on fully transparent background, 2-pixel stroke weight, 22x22 pixel canvas, crisp pixel grid alignment,
no gradients, no shading, no text. Rendered as an SF Symbols-style template image.
Provide three versions: 16x16, 22x22, 44x44 pixels. PNG with alpha.
```

**Negative prompt:** `color, gradient, shadow, 3D, perspective, text, letters, background, fill`

**Notes:**
- Verify it reads at 16px — most menu bar icons fail here
- Flag as "Template Image" in `Contents.json` via `"template-rendering-intent": "template"`

---

## 3. Pane Icons (4 panes)

> **Destination:** `Assets.xcassets/PaneIcons/` — one imageset per pane, 1x + 2x + 3x (so 64, 128, 192 px). Shown in the popover drop grid.

**Shared system prompt:**

```
A set of 4 matching square icons for drop zones in a macOS uploader app.
Rounded-square background 64x64, soft gradient fill unique per icon,
single centered line-art glyph in white with 2px stroke, subtle inner highlight.
No text. Flat modern, Apple HIG-compliant.
Export each on transparent background, 3x retina (192x192).
```

**Per-pane variations:**

### 3a. Private

```
Base prompt above. Gradient: slate to gunmetal (#4B5563 to #1F2937).
Glyph: padlock, centered, symmetrical, closed shackle.
```

### 3b. 1 Day

```
Base prompt above. Gradient: teal to blue (#14B8A6 to #3B82F6).
Glyph: calendar page with the numeral "1" centered, thin line weight.
```

### 3c. 30 Days

```
Base prompt above. Gradient: indigo to purple (#6366F1 to #A855F7).
Glyph: calendar page with the numeral "30" centered, thin line weight.
```

### 3d. Public

```
Base prompt above. Gradient: green to emerald (#10B981 to #059669).
Glyph: globe with thin meridian lines, centered.
```

**Negative prompt (all panes):** `text beyond the numeral, watermark, logo, photo-realistic, noisy, busy background`

---

## 4. Onboarding Hero Illustration

> **Destination:** `Assets.xcassets/OnboardingHero.imageset` — shown on first-launch welcome screen. Optional for v1.

**Prompt:**

```
Isometric illustration for an onboarding screen of a macOS file upload app.
Scene: a laptop with its lid open, three floating files arcing upward from the screen
toward a stylized cloud with small icons inside (lock, calendar, globe).
Soft pastel palette, thin line outlines, subtle gradient background,
no text, no logos. 4:3 aspect, 1024x768, transparent or soft-cream background.
```

**Negative prompt:** `text, logos, realistic photo, cluttered, harsh shadows, dark theme`

**Variations:**
- Dark mode version with deep navy background and neon accents
- Cleaner "diagram-style" version for in-app help

---

## 5. Notification Sound (optional)

Not an image, but worth noting: macOS uses the app icon as the notification icon by default. No separate asset needed. If you want a custom sound, use a `.caf` file placed in the bundle and reference it via `UNNotificationSound(named:)`.

---

## 6. Mascot Logo (outline)

> **Destination:** brand mark for icon/website use. Bracket-style prompt reused from an earlier app, adapted to Loft. Generate at 1024x1024 and downscale.

**Prompt:**

```
[Subject]: Minimalist vector icon glyph, icon only, absolutely no text anywhere. A simple pointed roof gable line with a small hoisting hook at the peak, and a small square parcel hanging on a straight rope below the hook. Just these three elements, nothing else.
[Action]: The parcel hangs halfway up the rope, being hoisted toward the roof peak.
[Environment]: none, empty transparent background, no building body, no window, no street, no sky.
[Cinematography]: Centered composition, square framing, large simple shapes that stay readable when scaled down to 16x16 pixels.
[Lighting/Style]: Flat monochrome pictogram, single solid black outline, thick uniform stroke weight, style of an SF Symbols glyph or airport signage pictogram.
[Technical]: High contrast, clean crisp lines, pure black on fully transparent background, scalable, no fills, no detail smaller than one tenth of the canvas.
```

**Negative prompt:** `text, letters, typography, wordmark, the word Loft, caption, label, color, gradient, shadow, 3D, photorealistic, watermark, background, frame, full building, window, chimney, people, fine detail`

**Notes:**
- The app name must NEVER appear in the image; models love sneaking the name from the subject line into the artwork, so the name is deliberately left out of the subject description
- Test readability at 16px and 22px before exporting; if the parcel becomes a blob, drop the rope and hang the parcel directly under the hook
- For the menu bar template version: pure black #000, export 16/22/44 px, flag as template image in `Contents.json`

**Variations to try:**
- Gable + hook only, no parcel, as the most stripped-down menu bar glyph
- Modern penthouse silhouette (flat roof, big window) instead of the canal house gable, for the full-size app icon where more detail survives
- Filled single-colour silhouette instead of outline

---

## Export Checklist

- [ ] App icon at all 14 required sizes (macOS `AppIcon.appiconset`)
- [ ] Menu bar template at 16 / 22 / 44 px with `template-rendering-intent` flag
- [ ] 4 pane icons × 3 scales = 12 files
- [ ] (Optional) Onboarding hero at 1024x768 @1x and @2x
- [ ] All PNGs with alpha, no JPEG compression
- [ ] File naming: lowercase-kebab-case, e.g. `pane-private@3x.png`

---

## Related

- [[Brand & Palette]] — canonical colors
- [[Asset Inventory]] — full list of every file needed to ship
- [[Loft Overview]] — project context
