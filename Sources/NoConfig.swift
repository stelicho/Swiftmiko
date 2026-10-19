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
//  NoConfig.swift
//  Swiftmiko
//
//  Port of netmiko/no_config.py.
//
//  Real Netmiko's NoConfig is a Python mixin: check_config_mode()
//  returns True unconditionally ("you're always considered in config
//  mode, so configuration commands can be executed directly"),
//  config_mode() and exit_config_mode() both return "" — a trivial
//  success, not an error. Python's MRO (NoConfig listed before the
//  real connection class in each driver's inheritance list) makes
//  these win over whatever the real class would otherwise provide.
//
//  Swift has no MRO — a protocol extension default is NOT reachable
//  here, since every conforming class already inherits a same-named,
//  non-throwing method from BaseConnection (or a more specific
//  ancestor like CiscoBaseConnection with real wire I/O), and Swift
//  always resolves a call through a concrete class to the class's own
//  inherited member over a protocol extension default — confirmed
//  empirically, not assumed. So each NoConfig-conforming class needs
//  its own direct `override` of the three methods below, delegating
//  to NoConfigBehavior so the actual logic lives in one place.
//
//  The one real exception found in the real driver set is
//  CiscoFtdSSH, which explicitly re-overrides send_config_set (raises
//  NotImplementedError) and check_config_mode (returns False) instead
//  of using the plain mixin — preserved as its own hard failure in
//  Sources/Cisco/CiscoFTD.swift, not routed through NoConfigBehavior.

public protocol NoConfig: AnyObject {}

/// Shared implementation for NoConfig-conforming classes' three
/// overridden methods — see the file comment above for why each
/// class needs its own override rather than relying on a protocol
/// extension default.
public enum NoConfigBehavior {
    public static func isInConfigMode() -> Bool { true }
    public static func enter() -> String { "" }
    public static func exit() -> String { "" }
}
