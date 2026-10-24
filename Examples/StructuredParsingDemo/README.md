# StructuredParsingDemo

Runs a "show version" transcript through both of Swiftmiko's native structured-parsing engines — **TextFSM** and **TTP** — and shows the results side by side.

## What it demonstrates

- `TextFSMTemplate(templateString:)` + `parseTextToDicts(_:)`, using the real, unmodified `cisco_ios_show_version.textfsm` template from [ntc-templates](https://github.com/networktocode/ntc-templates) (the same template library Netmiko itself uses).
- `NativeTTPParser().parse(rawOutput:template:)`, using a hand-written TTP template covering the same fields.
- A "Load Sample Output" button that parses a realistic sample transcript with no device connection required, so the demo is useful even without lab gear.

## A real API gap found while building this (now fixed)

Swiftmiko's `COMMON_ISSUES.md` showed a TTP usage example calling `TTPExecution.parse(template:rawText:)` directly. That type was never marked `public` — it was **not actually callable from outside the Swiftmiko package**. The only public, external-facing TTP entry point was `NativeTTPParser`, whose doc comment says plainly that its `template:` parameter is a **file path**, not inline template text — confirmed by trying to pass inline content directly, which throws `NativeTTPParserError.templateFileNotFound`.

Building this demo is what surfaced the gap. The fix: `TTPTemplate` (already public) gained a `public func parse(rawText:) -> [[String: Any]]` instance method, mirroring `TextFSMTemplate.parseTextToDicts(_:)`'s shape — see `Sources/TTP/TTPTemplate.swift`. `COMMON_ISSUES.md`'s example now calls that directly. This demo uses it too, rather than the file-based `NativeTTPParser` workaround an earlier version of this README described.

## A TTP quirk worth knowing

TTP's default field match stops at the first whitespace character (`\S+`-like). A value that legitimately contains a space — like the platform string `"C2960X Software"` in a real `show version` banner — won't be captured unless the field uses the `ORPHRASE` modifier (`{{ platform | ORPHRASE }}`). This isn't a bug, just TTP semantics that are easy to miss; see `ParsingTemplates.ttp`'s doc comment.
