Swiftmiko Icon Set
===================

Contents:

AppIcon.appiconset/
  Drop this whole folder into your Xcode target's Assets.xcassets,
  replacing the existing empty AppIcon set. Xcode will recognize it
  automatically (10 sizes + Contents.json, per Apple's macOS icon spec).

AccentColor.colorset/
  Drop this whole folder into Assets.xcassets alongside AppIcon.
  Pre-filled with the sampled brand orange (#F9251? see below) —
  no manual color picking needed. SwiftUI picks this up automatically
  as the app's tint color.

favicon/
  For a future website. Contains favicon.ico (multi-res 16/32/48),
  standalone PNGs at several sizes, apple-touch-icon.png (iOS/Safari),
  android-chrome PNGs, and a site.webmanifest pre-filled with the
  brand color and app name. Drop the whole folder's contents at your
  site root and reference in <head>:

    <link rel="icon" href="/favicon.ico" sizes="any">
    <link rel="apple-touch-icon" href="/apple-touch-icon.png">
    <link rel="manifest" href="/site.webmanifest">

icon_master_1024.png
  The source 1024x1024 master (just the "W" mark, isolated from the
  wordmark, centered on white) — everything else was generated from
  this. Keep it around if you ever need to regenerate a size that's
  missing, or re-crop/re-color later.

Brand orange sampled directly from the logo's gradient: ~#F9251? range
(top of gradient lighter, ~#FB5725; bottom of gradient deeper,
~#F84025). AccentColor.colorset uses a representative mid-tone.
