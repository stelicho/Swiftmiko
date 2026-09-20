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
//  SSHDispatcher.swift
//  Swiftmiko
//
//  Port of netmiko/ssh_dispatcher.py
//

import Foundation

/// Creates a driver from a connection profile.
public typealias ConnectionFactory = @Sendable (
    _ profile: ConnectionProfile
) -> BaseConnection

/// Creates a transfer handler for a connection.
public typealias FileTransferFactory = @Sendable (
    _ connection: BaseConnection,
    _ sourceFile: String,
    _ destinationFile: String,
    _ fileSystem: String?,
    _ direction: SCPTransferDirection,
    _ scpClient: SCPClient?
) async throws -> SCPHandler

/// Mutable registry for device drivers.
///
/// Python's dispatcher relies on module-level dictionaries and dynamic class
/// lookup. An actor provides the same extensibility with safe concurrent access.
public actor DispatcherRegistry {
    public static let shared = DispatcherRegistry()

    private var connectionFactories: [String: ConnectionFactory]
    private var fileTransferFactories: [String: FileTransferFactory]

    public init(
        connectionFactories: [String: ConnectionFactory] = [:],
        fileTransferFactories: [String: FileTransferFactory] = [:]
    ) {
        self.connectionFactories = connectionFactories
        self.fileTransferFactories = fileTransferFactories
    }

    public func registerConnection(
        _ deviceType: String,
        factory: @escaping ConnectionFactory
    ) {
        connectionFactories[deviceType] = factory
    }

    public func registerFileTransfer(
        _ deviceType: String,
        factory: @escaping FileTransferFactory
    ) {
        fileTransferFactories[deviceType] = factory
    }

    public func connectionFactory(
        for deviceType: String
    ) -> ConnectionFactory? {
        connectionFactories[deviceType]
    }

    public func fileTransferFactory(
        for deviceType: String
    ) -> FileTransferFactory? {
        fileTransferFactories[deviceType]
    }

    public func supportedConnectionTypes() -> [String] {
        connectionFactories.keys.sorted()
    }

    public func supportedFileTransferTypes() -> [String] {
        fileTransferFactories.keys.sorted()
    }
}

/// Default Swiftmiko dispatcher entries.
///
/// Covers every vendor driver ported under `Sources/` (see `PLATFORMS.md`),
/// not just the Cisco family that was originally wired up here. A small
/// number of `deviceType` strings from `PLATFORMS.md` are intentionally
/// left unregistered below because no corresponding Swift class exists
/// yet (e.g. `huawei_olt`, `fiberstore_fsosv2`, `brocade_vyos`) — that's a
/// missing driver, not a missing registration, and forcing a guess would
/// be worse than leaving it absent. A handful of others are registered
/// as a *best-effort alias* to the closest existing driver where Netmiko
/// itself is known to alias multiple `deviceType` strings to one class
/// (rebrand/acquisition pairs like Avaya/Extreme, HP/Aruba ProCurve,
/// Alcatel/Nokia SR OS); those are called out inline.
///
/// Every vendor leaf class below accepts `channelProvider` (forwarded
/// from its custom `init(profile:...)` through to `BaseConnection`, the
/// same pattern `DigiTransportBase` originally established) — so every
/// entry works equally well through `connectHandler` and through
/// `sshDispatcher(deviceType:)` followed by a direct `.connect()`.
public enum SSHDispatcher {
    public static let defaultConnectionFactories: [String: ConnectionFactory] = [
        // MARK: Cisco family
        //
        // IOS entries route to CiscoIOSSSH/Telnet/Serial (not the bare
        // CiscoSSHConnection/CiscoBaseConnection) because CiscoIOSBase is
        // the class that actually overrides sessionPreparation() with
        // IOS's real prep sequence (terminal width 511, then disable
        // paging, then find the prompt). CiscoBaseConnection has no
        // sessionPreparation() override of its own, so it falls back to
        // BaseConnection's generic `disablePaging(); setBasePrompt()` —
        // and since BaseConnection.disablePaging's own declared default
        // for `command` is "" (Swift resolves default parameter values
        // against the statically declared call site, not virtually
        // through the override), that call silently sends an empty
        // command instead of "terminal length 0".
        "cisco_ios": { CiscoIOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_ios_ssh": { CiscoIOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_ios_telnet": { CiscoIOSTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "cisco_ios_serial": { CiscoIOSSerial(profile: $0, channelProvider: serialChannelProvider) },
        "cisco_xe": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_xe_ssh": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_xe_telnet": { CiscoSSHConnection(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "cisco_nxos": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_nxos_ssh": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_nxos_telnet": { CiscoSSHConnection(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "cisco_asa": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_asa_ssh": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_viptela": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_viptela_ssh": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_wlc": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_wlc_ssh": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_xr": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_xr_ssh": { CiscoSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_xr_telnet": { CiscoSSHConnection(profile: $0, channelProvider: nioTelnetChannelProvider) },
        // Not in PLATFORMS.md's static table yet, but a real driver exists
        // and is used by SSHAutodetectMapper's own "cisco_ap" rule.
        "cisco_ap": { CiscoAPSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_apic": { CiscoAPICSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_ftd": { CiscoFtdSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_s200": { CiscoS200SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_s200_telnet": { CiscoS200Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "cisco_s300": { CiscoS300SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cisco_s300_telnet": { CiscoS300Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "cisco_tp": { CiscoTpTcCeSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: A10 / Accedian
        "a10": { A10SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "accedian": { AccedianSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Adtran / Adva
        "adtran_os": { AdtranOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "adtran_os_telnet": { AdtranOSTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "adva_fsp150f2": { AdvaAosFsp150F2SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "adva_fsp150f3": { AdvaAosFsp150F3SSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Alaxala / Alcatel / Allied Telesis
        // No dedicated AX26S class exists; AX26S/AX36S share one driver.
        "alaxala_ax26s": { AlaxalaAx36sSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "alaxala_ax36s": { AlaxalaAx36sSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "alcatel_aos": { AlcatelAosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        // Alcatel-Lucent SR OS is Nokia SR OS pre-rebrand — same driver.
        "alcatel_sros": { NokiaSrosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "allied_telesis_awplus": { AlliedTelesisAwplusSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Apc / Apresia / Arista / Arris
        "apc_aos": { ApcAosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "apresia_aeos": { ApresiaAeosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "apresia_aeos_telnet": { ApresiaAeosTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "arista_eos": { AristaSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "arista_eos_telnet": { AristaTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "arris_cer": { ArrisCERSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Aruba
        "aruba_aoscx": { ArubaCxSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "aruba_os": { ArubaOsSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        // Aruba OS-Switch and Aruba ProCurve are both the rebranded HP
        // ProCurve line — reuse the ProCurve driver.
        "aruba_osswitch": { HPProcurveSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "aruba_procurve": { HPProcurveSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "aruba_procurve_telnet": { HPProcurveTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Asterfusion / Audiocode / Avara / Aviat
        "asterfusion_asternos": { AsterfusionAsterNOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "audiocode_66": { Audiocode66SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "audiocode_66_telnet": { Audiocode66Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "audiocode_72": { Audiocode72SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "audiocode_72_telnet": { Audiocode72Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "audiocode_shell": { AudiocodeShellSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "audiocode_shell_telnet": { AudiocodeShellTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "avara_aos": { AvaraAosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "aviat_wtm": { AviatWTMSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Bintec / Broadcom / Brocade
        "bintec_boss": { BintecBossSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "bintec_boss_telnet": { BintecBossTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "broadcom_icos": { BroadcomIcosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "brocade_fos": { BrocadeFOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        // Ruckus acquired Brocade's FastIron line — one driver, two names.
        "brocade_fastiron": { RuckusFastironSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "brocade_fastiron_telnet": { RuckusFastironTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        // Brocade NetIron/MLX is now sold as Extreme NetIron/MLX.
        "brocade_netiron": { ExtremeNetironSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "brocade_netiron_telnet": { ExtremeNetironTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        // Brocade Network OS (VDX hardware) is now sold as Extreme NOS/VDX.
        "brocade_nos": { ExtremeNosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "brocade_vdx": { ExtremeNosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Calix / Casa / Cdot / Centec
        "calix_b6": { CalixB6SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "calix_b6_telnet": { CalixB6Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        // Not in PLATFORMS.md's static table yet, but the driver exists.
        "calix_exa": { CalixExaSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "calix_exa_telnet": { CalixExaTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "casa_cmts": { CasaCMTSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cdot_cros": { CdotCrosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "centec_os": { CentecOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "centec_os_telnet": { CentecOSTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Checkpoint / Ciena / Citrix / Cloudgenix
        "checkpoint_gaia": { CheckPointGaiaSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ciena_saos": { CienaSaosBase(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ciena_saos_telnet": { CienaSaosTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "ciena_saos10": { CienaSaos10SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ciena_waveserver": { CienaWaveserverSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "netscaler": { NetscalerSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cloudgenix_ion": { CloudGenixIonSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Corelight / Coriant / Cumulus
        "corelight_linux": { CorelightLinuxSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "coriant": { CoriantSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "cumulus_linux": { CumulusLinuxSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Dell
        // Force10, OS9, and DNOS9 are all names for the same FTOS9 driver.
        "dell_force10": { DellForce10SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "dell_dnos9": { DellForce10SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "dell_os9": { DellForce10SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "dell_isilon": { DellIsilonSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "dell_os10": { DellOS10SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "dell_os6": { DellDNOS6SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "dell_dnos6_telnet": { DellDNOS6Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "dell_powerconnect": { DellPowerConnectSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "dell_powerconnect_telnet": { DellPowerConnectTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "dell_sonic": { DellSonicSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Digi / Dlink
        "digi_transport": { DigiTransportSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "dlink_ds": { DlinkDSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "dlink_ds_telnet": { DlinkDSTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Edgecore / Ekinops / Eltex / Endace / Enterasys
        "edgecore_sonic": { EdgecoreSonicSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ekinops_ek360": { EkinopsEk360SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "eltex": { EltexSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "eltex_esr": { EltexEsrSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "endace": { EndaceSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "enterasys": { EnterasysSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Ericsson
        "ericsson_ipos": { EricssonIposSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ericsson_mltn63": { EricssonMinilink63SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ericsson_mltn66": { EricssonMinilink66SSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Extreme / Avaya
        // Netmiko itself aliases the Avaya-branded names to the Extreme
        // drivers that inherited these product lines.
        "extreme_ers": { ExtremeErsSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "avaya_ers": { ExtremeErsSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "extreme_vsp": { ExtremeVspSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "avaya_vsp": { ExtremeVspSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "extreme_exos": { ExtremeExosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "extreme_exos_telnet": { ExtremeExosTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "extreme_netiron": { ExtremeNetironSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "extreme_netiron_telnet": { ExtremeNetironTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "extreme_nos": { ExtremeNosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "extreme_vdx": { ExtremeNosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "extreme_slx": { ExtremeSlxSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "extreme_tierra": { ExtremeTierraSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "extreme_wing": { ExtremeWingSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        // Bare "extreme"/"extreme_telnet" have no dedicated class of their
        // own in this port; best-effort alias to the oldest/most generic
        // Extreme lineage (ERS). Verify against real hardware before
        // relying on this for anything but the original ERS switches.
        "extreme": { ExtremeErsSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "extreme_telnet": { ExtremeErsSSH(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: F5
        "f5_linux": { F5LinuxSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "f5_tmsh": { F5TmshSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        // f5_ltm is Netmiko's alias for the tmsh-managed LTM module.
        "f5_ltm": { F5TmshSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Fiberstore / Flexvnf / Fortinet / Fujitsu / Furukawa
        "fiberstore_fsos": { FiberstoreFsosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "fiberstore_networkos": { FiberstoreNetworkOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "flexvnf": { FlexvnfSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "fortinet": { FortinetSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "fujitsu_sir": { FujitsuSirSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "furukawa_fitelnet": { FurukawaFitelnetSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "furukawa_fitelnet_telnet": { FurukawaFitelnetTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        // Not in PLATFORMS.md's static table yet, but the driver exists.
        "furukawa_fitelnet_serial": { FurukawaFitelnetSerial(profile: $0, channelProvider: serialChannelProvider) },

        // MARK: Garderos / Genexis
        "garderos_grs": { GarderosGrsSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "genexis_solt33_telnet": { GenexisSOLT33Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Generic / terminal server
        // Netmiko's "generic" is the bare driver with no vendor
        // customization at all — that's exactly what BaseConnection is.
        "generic": { BaseConnection(profile: $0, channelProvider: nioSSHChannelProvider) },
        "generic_telnet": { BaseConnection(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "generic_termserver": { TerminalServerSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "generic_termserver_telnet": { TerminalServerTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: HP / H3C / Hillstone / Hioso / Hirschmann
        "hp_comware": { HPComwareSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "hp_comware_telnet": { HPComwareTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        // H3C is the original brand HP's Comware switches were OEM'd from.
        "h3c_comware": { HPComwareSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "hp_procurve": { HPProcurveSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "hp_procurve_telnet": { HPProcurveTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "hillstone_stoneos": { HillstoneStoneosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "hioso_olt_telnet": { HiosoOLTTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "hirschmann_hios": { HirschmannHiOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Huawei
        "huawei": { HuaweiSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "huawei_telnet": { HuaweiTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "huawei_vrp": { HuaweiSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "huawei_vrpv8": { HuaweiVrpv8SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "huawei_ont": { HuaweiONTSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "huawei_ont_telnet": { HuaweiONTTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "huawei_smartax": { HuaweiSmartAXSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "huawei_smartaxmmi": { HuaweiSmartAXSSHMMI(profile: $0, channelProvider: nioSSHChannelProvider) },
        // huawei_olt has no ported driver yet — genuinely missing, not
        // just unregistered (see PLATFORMS.md).

        // MARK: Iij / Infinera / Ipinfusion
        "iij_seilos": { IIJSeilosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "iij_seilos_telnet": { IIJSeilosTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "infinera_packet": { InfineraPacketSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "infinera_packet_telnet": { InfineraPacketTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "ipinfusion_ocnos": { IpInfusionOcNOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ipinfusion_ocnos_telnet": { IpInfusionOcNOSTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Juniper
        "juniper": { JuniperSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "juniper_junos": { JuniperSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "juniper_junos_telnet": { JuniperTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "juniper_screenos": { JuniperScreenOsSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Keymile / Lancom / Linux
        "keymile": { KeymileSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "keymile_nos": { KeymileNOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "lancom_lcossx4": { LancomLCOSSX4SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "lancom_lcossx5": { LancomLCOSSX5SSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "linux": { LinuxSSHConnection(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Maipu / Mellanox / Mikrotik / Moxa / Mrv
        "maipu": { MaipuSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "maipu_telnet": { MaipuTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "mellanox": { MellanoxMlnxosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "mellanox_mlnxos": { MellanoxMlnxosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "mikrotik_routeros": { MikrotikRouterOsSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "mikrotik_switchos": { MikrotikSwitchOsSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "moxa_nos": { MoxaNosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "mrv_lx": { MrvLxSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "mrv_optiswitch": { MrvOptiswitchSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Nec / Netapp / Netgear / Nokia
        "nec_ix": { NecIxSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "nec_ix_telnet": { NecIxTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "netapp_cdot": { NetAppCdotSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "netgear_prosafe": { NetgearProSafeSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "nokia_srl": { NokiaSrlSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "nokia_sros": { NokiaSrosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "nokia_sros_telnet": { NokiaSrosTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Oneaccess / Optilink / Ovs
        "oneaccess_oneos": { OneaccessOneOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "oneaccess_oneos_telnet": { OneaccessOneOSTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "optilink_eolt11444_telnet": { OptilinkEOLT11444Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "optilink_eolt9702_telnet": { OptilinkEOLT9702Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        // Not in PLATFORMS.md's static table yet, but the driver exists.
        "optilink_golt924_telnet": { OptilinkGOLT924Telnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "ovs_linux": { OvsLinuxSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Paloalto / Perle / Pluribus
        "paloalto_panos": { PaloAltoPanosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "paloalto_panos_telnet": { PaloAltoPanosTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        // Not in PLATFORMS.md's static table yet, but the driver exists.
        "perle_iolan": { PerleIolanSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "pluribus": { PluribusSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Quanta / Rad / Raisecom
        "quanta_mesh": { QuantaMeshSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "rad_etx": { RadETXSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "rad_etx_telnet": { RadETXTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "raisecom_roap": { RaisecomRoapSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        // Bare "raisecom_telnet" is the ROAP telnet variant — there's no
        // separate "raisecom_roap_telnet" string in PLATFORMS.md.
        "raisecom_telnet": { RaisecomRoapTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "raisecom_ros": { RaisecomRosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "raisecom_ros_telnet": { RaisecomRosTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Ruckus / Ruijie
        "ruckus_fastiron": { RuckusFastironSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ruckus_fastiron_telnet": { RuckusFastironTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "ruijie_os": { RuijieOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ruijie_os_telnet": { RuijieOSTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Silverpeak / Sixwind / Sophos / Supermicro
        "silverpeak_vxoa": { SilverPeakVXOASSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "sixwind_os": { SixwindOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "sophos_sfos": { SophosSfosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "supermicro_smis": { SmciSwitchSmisSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "supermicro_smis_telnet": { SmciSwitchSmisTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Telcosystems / Teldat / Tplink
        "telcosystems_binos": { TelcoSystemsBinosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "telcosystems_binos_telnet": { TelcoSystemsBinosTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "teldat_cit": { TeldatCITSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "teldat_cit_telnet": { TeldatCITTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "tplink_jetstream": { TPLinkJetStreamSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "tplink_jetstream_telnet": { TPLinkJetStreamTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Ubiquiti / Vyos
        "ubiquiti_edge": { UbiquitiEdgeSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ubiquiti_edgeswitch": { UbiquitiEdgeSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ubiquiti_edgerouter": { UbiquitiEdgeRouterSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "ubiquiti_unifiswitch": { UbiquitiUnifiSwitchSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "vyos": { VyOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "vyatta_vyos": { VyOSSSH(profile: $0, channelProvider: nioSSHChannelProvider) },

        // MARK: Vertiv / Watchguard / Yamaha
        "vertiv_mph": { VertivMPHSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "watchguard_fireware": { WatchguardFirewareSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "yamaha": { YamahaSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        // No dedicated Telnet subclass exists; the base class works fine —
        // connectHandler picks NIOTelnetChannel from the "_telnet" suffix.
        "yamaha_telnet": { YamahaBase(profile: $0, channelProvider: nioTelnetChannelProvider) },

        // MARK: Zpe / Zte / Zyxel
        "zpe_nodegrid": { ZpeNodegridSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "zte_zxros": { ZteZxrosSSH(profile: $0, channelProvider: nioSSHChannelProvider) },
        "zte_zxros_telnet": { ZteZxrosTelnet(profile: $0, channelProvider: nioTelnetChannelProvider) },
        "zyxel_os": { ZyxelSSH(profile: $0, channelProvider: nioSSHChannelProvider) }
    ]

    public static let defaultFileTransferFactories: [String: FileTransferFactory] = [
        "cisco_ios": standardTransferFactory,
        "cisco_ios_ssh": standardTransferFactory,
        "cisco_xe": standardTransferFactory,
        "cisco_xe_ssh": standardTransferFactory,
        "cisco_nxos": standardTransferFactory,
        "cisco_nxos_ssh": standardTransferFactory,
        "cisco_asa": standardTransferFactory,
        "cisco_asa_ssh": standardTransferFactory,
        "cisco_xr": standardTransferFactory,
        "cisco_xr_ssh": standardTransferFactory,
        // No dedicated FileTransfer subclass exists for these two —
        // the generic FileTransfer/SCPHandler works over any BaseConnection.
        "ciena_saos": standardTransferFactory,
        "ubiquiti_edgerouter": standardTransferFactory,
        "arista_eos": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            try await AristaFileTransfer(
                connection: connection,
                sourceFile: sourceFile,
                destFile: destinationFile,
                fileSystem: fileSystem ?? "/mnt/flash",
                direction: direction
            )
        },
        "aruba_os": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            try await ArubaOsFileTransfer(
                connection: connection,
                sourceFile: sourceFile,
                destinationFile: destinationFile,
                fileSystem: fileSystem ?? "/mm/mynode",
                direction: direction
            )
        },
        "dell_os10": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            try await DellOS10FileTransfer(
                connection: connection,
                sourceFile: sourceFile,
                destFile: destinationFile,
                fileSystem: fileSystem ?? "/home/admin",
                direction: direction
            )
        },
        "dell_sonic": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            guard let dellConnection = connection as? DellSonicSSH else {
                throw SwiftmikoError.connectionFailed(
                    "dell_sonic file transfer requires a DellSonicSSH connection"
                )
            }
            return try await DellSonicFileTransfer(
                connection: dellConnection,
                sourceFile: sourceFile,
                destFile: destinationFile,
                fileSystem: fileSystem ?? "/home/admin",
                direction: direction
            )
        },
        "extreme_exos": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            try await ExtremeExosFileTransfer(
                connection: connection,
                sourceFile: sourceFile,
                destFile: destinationFile,
                fileSystem: fileSystem ?? "/usr/local/cfg",
                direction: direction
            )
        },
        "juniper_junos": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            try await JuniperFileTransfer(
                connection: connection,
                sourceFile: sourceFile,
                destFile: destinationFile,
                fileSystem: fileSystem ?? "/var/tmp",
                direction: direction
            )
        },
        "linux": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            try await LinuxFileTransfer(
                connection: connection,
                sourceFile: sourceFile,
                destinationFile: destinationFile,
                fileSystem: fileSystem ?? "/var/tmp",
                direction: direction
            )
        },
        "mikrotik_routeros": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            try await MikrotikRouterOsFileTransfer(
                connection: connection,
                sourceFile: sourceFile,
                destinationFile: destinationFile,
                fileSystem: fileSystem ?? "flash",
                direction: direction
            )
        },
        "nokia_sros": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            guard let nokiaConnection = connection as? NokiaSros else {
                throw SwiftmikoError.connectionFailed(
                    "nokia_sros file transfer requires a NokiaSros connection"
                )
            }
            return try await NokiaSrosFileTransfer(
                connection: nokiaConnection,
                sourceFile: sourceFile,
                destinationFile: destinationFile,
                fileSystem: fileSystem,
                direction: direction
            )
        },
        "zpe_nodegrid": { connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
            guard let zpeConnection = connection as? ZpeNodegridSSH else {
                throw SwiftmikoError.connectionFailed(
                    "zpe_nodegrid file transfer requires a ZpeNodegridSSH connection"
                )
            }
            return try await ZpeNodegridFileTransfer(
                connection: zpeConnection,
                sourceFile: sourceFile,
                destFile: destinationFile,
                fileSystem: fileSystem ?? "/var/tmp",
                direction: direction
            )
        }
    ]

    /// Register the currently available drivers in the shared registry.
    public static func installDefaults() async {
        for (type, factory) in defaultConnectionFactories {
            await DispatcherRegistry.shared.registerConnection(type, factory: factory)
        }
        for (type, factory) in defaultFileTransferFactories {
            await DispatcherRegistry.shared.registerFileTransfer(type, factory: factory)
        }
    }

    /// Swift equivalent of Netmiko's `ConnectHandler`.
    public static func connectHandler(
        profile: ConnectionProfile,
        autoConnect: Bool = true
    ) async throws -> BaseConnection {
        let factory = await DispatcherRegistry.shared.connectionFactory(
            for: profile.deviceType
        ) ?? defaultConnectionFactories[profile.deviceType]

        guard let factory else {
            throw SwiftmikoError.connectionFailed(
                unsupportedDeviceMessage(for: profile.deviceType)
            )
        }

        let connection = factory(profile)
        // Inject a transport channel if the factory did not already configure one.
        // Device type suffix determines which transport to use:
        //   _telnet → NIOTelnetChannel (TCP + IAC negotiation)
        //   _serial → SerialChannel (POSIX termios; Darwin/macOS only)
        //   all others → NIOSSHChannel
        if connection.channel == nil {
            let dt = profile.deviceType
            if dt.hasSuffix("_telnet") {
                connection.setChannel(NIOTelnetChannel(profile: profile))
            } else if dt.hasSuffix("_serial") {
                connection.setChannel(SerialChannel(profile: profile))
            } else {
                connection.setChannel(NIOSSHChannel(profile: profile))
            }
        }
        if autoConnect {
            try await connection.connect()
        }
        return connection
    }

    /// Swift equivalent of Netmiko's `ssh_dispatcher`.
    public static func sshDispatcher(
        deviceType: String
    ) async throws -> ConnectionFactory {
        if let registered = await DispatcherRegistry.shared.connectionFactory(
            for: deviceType
        ) {
            return registered
        }
        guard let factory = defaultConnectionFactories[deviceType] else {
            throw SwiftmikoError.connectionFailed(
                unsupportedDeviceMessage(for: deviceType)
            )
        }
        return factory
    }

    /// Swift equivalent of Netmiko's SCP `FileTransfer` dispatcher.
    public static func makeFileTransfer(
        connection: BaseConnection,
        sourceFile: String,
        destinationFile: String,
        fileSystem: String? = nil,
        direction: SCPTransferDirection = .put,
        scpClient: SCPClient? = nil
    ) async throws -> SCPHandler {
        let deviceType = connection.profile.deviceType
        let factory = await DispatcherRegistry.shared.fileTransferFactory(
            for: deviceType
        ) ?? defaultFileTransferFactories[deviceType]

        guard let factory else {
            throw SwiftmikoError.connectionFailed(
                "Unsupported SCP device type: \(deviceType)"
            )
        }

        // The standard factory accepts the transport through the common
        // handler initializer. A registered vendor factory can choose its
        // own transfer subtype.
        return try await factory(
            connection,
            sourceFile,
            destinationFile,
            fileSystem,
            direction,
            scpClient
        )
    }

    /// Recreate a connection using a different driver, reusing the
    /// existing connection's already-open, already-authenticated channel.
    ///
    /// Python's `redispatch()` reassigns `obj.__class__` in place, which
    /// keeps the same socket alive — that's what lets Netmiko bounce
    /// through an intermediate device (a terminal server, a jump switch)
    /// without reconnecting. Swift can't reassign an object's class at
    /// runtime, so this instead constructs a new driver instance for
    /// `deviceType` and transplants the *existing* connection's channel
    /// onto it via `setChannel`, rather than opening a new one — that's
    /// the part of Netmiko's behavior that actually matters here. Only
    /// `sessionPreparation()` runs on the new driver (matching Python's
    /// `session_prep=True` default); there's no re-authentication, since
    /// the underlying transport is already authenticated.
    ///
    /// The connection passed in should not be used again afterward — its
    /// channel is now owned by the returned connection.
    public static func redispatch(
        _ connection: BaseConnection,
        deviceType: String,
        sessionPreparation: Bool = true
    ) async throws -> BaseConnection {
        let factory = await DispatcherRegistry.shared.connectionFactory(
            for: deviceType
        ) ?? defaultConnectionFactories[deviceType]

        guard let factory else {
            throw SwiftmikoError.connectionFailed(
                unsupportedDeviceMessage(for: deviceType)
            )
        }

        var updatedProfile = connection.profile
        updatedProfile.deviceType = deviceType
        let newConnection = factory(updatedProfile)

        if let channel = connection.channel {
            newConnection.setChannel(channel)
        }

        if sessionPreparation {
            try await newConnection.sessionPreparation()
        }
        return newConnection
    }

    /// Try SSH first and fall back to the corresponding Telnet driver.
    public static func telnetFallback(
        profile: ConnectionProfile
    ) async throws -> BaseConnection {
        do {
            return try await connectHandler(profile: profile)
        } catch let error as SwiftmikoError {
            switch error {
            case .timeout, .connectionFailed:
                let telnetType = profile.deviceType.hasSuffix("_ssh")
                    ? profile.deviceType.replacingOccurrences(
                        of: "_ssh",
                        with: "_telnet"
                    )
                    : profile.deviceType + "_telnet"
                var telnetProfile = profile
                telnetProfile.deviceType = telnetType
                return try await connectHandler(profile: telnetProfile)
            default:
                throw error
            }
        } catch {
            throw error
        }
    }

    /// Connect while converting connection errors into one unified error.
    public static func connUnify(
        profile: ConnectionProfile
    ) async throws -> BaseConnection {
        do {
            return try await connectHandler(profile: profile)
        } catch {
            throw SwiftmikoError.connectionFailed(
                "Connection failure to \(profile.host):\(profile.port) " +
                "(\(profile.deviceType)): \(error)"
            )
        }
    }

    /// Best-effort connection helper analogous to Netmiko's `ConnLogOnly`.
    public static func connLogOnly(
        profile: ConnectionProfile,
        logger: ((String) -> Void)? = nil
    ) async -> BaseConnection? {
        do {
            let connection = try await connectHandler(
                profile: profile,
                autoConnect: false
            )
            try await connection.connect()
            logger?(
                "Connection successful to \(profile.host):\(profile.port)"
            )
            return connection
        } catch {
            logger?(
                "Connection failed to \(profile.host):\(profile.port): \(error)"
            )
            return nil
        }
    }

    public static var platforms: [String] {
        Array(Set(defaultConnectionFactories.keys)).sorted()
    }

    public static var scpPlatforms: [String] {
        Array(Set(defaultFileTransferFactories.keys)).sorted()
    }

    private static let standardTransferFactory: FileTransferFactory = {
        connection, sourceFile, destinationFile, fileSystem, direction, scpClient in
        try await FileTransfer(
            connection: connection,
            sourceFile: sourceFile,
            destinationFile: destinationFile,
            fileSystem: fileSystem,
            direction: direction,
            scpClient: scpClient
        )
    }

    private static func unsupportedDeviceMessage(
        for deviceType: String
    ) -> String {
        let available = platforms.joined(separator: "\n")
        return "Unsupported device type '\(deviceType)'. " +
            "Currently supported platforms are:\n\(available)"
    }
}
