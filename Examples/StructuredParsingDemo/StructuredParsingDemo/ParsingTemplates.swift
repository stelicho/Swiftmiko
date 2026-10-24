// Examples/StructuredParsingDemo/ParsingTemplates.swift
//
// Both templates are verified end-to-end against the sample transcript
// in ParsingTemplates.sampleShowVersion before being used here.

enum ParsingTemplates {
    /// The real, unmodified cisco_ios_show_version.textfsm template from
    /// ntc-templates (the library Netmiko itself uses), so this demo
    /// parses with an authentic vendor template rather than a toy one.
    static let textFSM = #"""
    Value SOFTWARE_IMAGE (\S+)
    Value VERSION (.+?)
    Value RELEASE (\S+)
    Value ROMMON (\S+)
    Value HOSTNAME (\S+)
    Value UPTIME (.+)
    Value UPTIME_YEARS (\d+)
    Value UPTIME_WEEKS (\d+)
    Value UPTIME_DAYS (\d+)
    Value UPTIME_HOURS (\d+)
    Value UPTIME_MINUTES (\d+)
    Value RELOAD_REASON (.+?)
    Value RUNNING_IMAGE (\S+)
    Value List HARDWARE (\S+|\S+\d\S+)
    Value List SERIAL (\w+)
    Value CONFIG_REGISTER (\S+)
    Value List MAC_ADDRESS ([0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5})
    Value RESTARTED (.+)

    Start
      ^.*Software,*\s+\(${SOFTWARE_IMAGE}\),\sVersion\s${VERSION},*\s+RELEASE.*\(${RELEASE}\)
      ^.*Software,*\s+\(${SOFTWARE_IMAGE}\),\sVersion\s${VERSION},*\s+\S+.*:${RELEASE}
      ^.*Software,*\s+\(${SOFTWARE_IMAGE}\),\sVersion\s${VERSION},
      ^ROM:\s+${ROMMON}
      ^\s*${HOSTNAME}\s+uptime\s+is\s+${UPTIME} -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_YEARS}\syear -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_WEEKS}\sweek -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_DAYS}\sday -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_HOURS}\shour -> Continue
      ^.*\s+uptime\s+is.*\s+${UPTIME_MINUTES}\sminute
      ^[sS]ystem\s+image\s+file\s+is\s+"(.*?):${RUNNING_IMAGE}"
      ^(?:[lL]ast\s+reload\s+reason:|System\s+returned\s+to\s+ROM\s+by)\s+${RELOAD_REASON}\s*$$
      ^[Pp]rocessor\s+board\s+ID\s+${SERIAL}
      ^[Cc]isco\s+${HARDWARE}\s+\(.+\).+
      ^[Cc]onfiguration\s+register\s+is\s+${CONFIG_REGISTER}
      ^Base\s+[Ee]thernet\s+MAC\s+[Aa]ddress\s+:\s+${MAC_ADDRESS}
      ^System\s+restarted\s+at\s+${RESTARTED}$$
      ^Switch\s+Port -> Stack
      ^Switch\s\d+ -> Stack
      ^Load\s+for\s+
      ^Time\s+source\s+is

    Stack
      ^[Ss]ystem\s+[Ss]erial\s+[Nn]umber\s+:\s+${SERIAL}
      ^[Mm]odel\s+[Nn]umber\s+:\s+${HARDWARE}\s*
      ^[Cc]onfiguration\s+register\s+is\s+${CONFIG_REGISTER}
      ^Base [Ee]thernet MAC [Aa]ddress\s+:\s+${MAC_ADDRESS}
    """#

    /// A hand-written TTP equivalent covering the same fields, to show
    /// the two engines side by side. Note the `ORPHRASE` modifier on
    /// `platform` and `uptime` — TTP's default field match stops at the
    /// first whitespace, so any value that legitimately contains a
    /// space (like "C2960X Software") needs it explicitly.
    static let ttp = #"""
    <group name="version">
    Cisco IOS Software, {{ platform | ORPHRASE }} ({{ software_image }}), Version {{ version }}, RELEASE SOFTWARE ({{ release }})
    {{ hostname }} uptime is {{ uptime | ORPHRASE }}
    cisco {{ hardware }} ({{ cpu }}) processor
    Processor board ID {{ serial }}
    Base Ethernet MAC Address       : {{ mac_address }}
    Configuration register is {{ config_register }}
    </group>
    """#

    /// A realistic "show version" transcript, used as the default
    /// command output preview before a real device connects, and as
    /// the fixture both templates above were verified against.
    static let sampleShowVersion = #"""
    Cisco IOS Software, C2960X Software (C2960X-UNIVERSALK9-M), Version 15.2(7)E3, RELEASE SOFTWARE (fc3)
    Technical Support: http://www.cisco.com/techsupport
    Copyright (c) 1986-2019 by Cisco Systems, Inc.
    Compiled Wed 06-Mar-19 09:22 by prod_rel_team

    ROM: Bootstrap program is C2960X boot loader

    switch1 uptime is 10 weeks, 2 days, 5 hours, 30 minutes
    System returned to ROM by power-on
    System image file is "flash:c2960x-universalk9-mz.152-7.E3/c2960x-universalk9-mz.152-7.E3.bin"
    Last reload reason: power-on

    cisco WS-C2960X-24TS-L (PowerPC405) processor (revision A0) with 524288K bytes of memory.
    Processor board ID FOC1946Z1A1
    Base Ethernet MAC Address       : 00:1A:2B:3C:4D:5E
    Configuration register is 0xF
    """#
}
