//
//  ┌───────────────────────────────────────────────────────┐
//  │                   S W I F T M I K O                   │
//  │  Swift-Native Multi-Vendor Network Device Automation  │
//  └───────────────────────────────────────────────────────┘
//
//  Author & Maintainer: K.K. Campbell
//  Created with the assistance of Claude Sonnet 5 (Anthropic),
//  via Claude Code.
//
//
//  NoEnable.swift
//  Swiftmiko
//
//  Port of netmiko/no_enable.py.
//
//  Real Netmiko's NoEnable is a Python mixin: check_enable_mode()
//  returns True unconditionally ("the standard default privileges
//  already allow configuration changes"), enable() and
//  exit_enable_mode() both return "" — a trivial success. Python's
//  MRO (NoEnable listed before the real connection class) makes these
//  win over whatever the real class would otherwise provide.
//
//  The previous version of this file tried to express that with a
//  protocol extension (`extension NoEnable where Self: BaseConnection
//  { func enterEnableMode(secret:) ... }`), which looked right but was
//  never actually reachable: BaseConnection already declares
//  `enterEnableMode(secret:command:pattern:enablePattern:checkState:
//  caseInsensitive:defaultUsername:) -> String`, and Swift always
//  resolves a call through a concrete class to that inherited member
//  over a protocol extension default with a different signature — even
//  though the extension's signature is also callable with just
//  `secret:`. Confirmed empirically with a minimal reproduction (the
//  class's own method ran, not the extension's), not assumed. The
//  same issue applies to isInEnableMode()/exitEnableMode(). So each
//  NoEnable-conforming class needs its own direct `override` of the
//  three methods, delegating to NoEnableBehavior below.
//
//  No real driver in the ported set explicitly re-overrides
//  check_enable_mode/enable/exit_enable_mode beyond the plain mixin —
//  verified against all ~39 real Netmiko classes this protocol maps
//  to. One Swift-side exception: Sources/Supermicro/SmciSwitchSmis.swift
//  deliberately overrides isInEnableMode() to do a real prompt check
//  instead, because (per its own comment) SMCI's prompt genuinely
//  distinguishes "#" from ">" — left as-is, not routed through
//  NoEnableBehavior.

public protocol NoEnable: AnyObject {}

/// Shared implementation for NoEnable-conforming classes' three
/// overridden methods — see the file comment above for why each
/// class needs its own override rather than relying on a protocol
/// extension default.
public enum NoEnableBehavior {
    public static func isInEnableMode() -> Bool { true }
    public static func enter() -> String { "" }
    public static func exit() -> String { "" }
}
