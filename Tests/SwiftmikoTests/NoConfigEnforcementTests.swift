// Tests/SwiftmikoTests/NoConfigEnforcementTests.swift
//
// Regression coverage for the NoConfig marker protocol: verified
// against real Netmiko's actual no_config.py, NoConfig is a trivial
// pass-through (check_config_mode->True, config_mode/
// exit_config_mode->""), not a hard throw. An earlier pass at this
// fix made every NoConfig-conforming class throw configModeNotSupported
// instead — backwards from real behavior for all but one real driver.
// CiscoFtdSSH is that one genuine exception: it explicitly
// re-overrides send_config_set (raises NotImplementedError) and
// check_config_mode (returns False) in real Netmiko, instead of using
// the plain mixin.
//
// Swift has no MRO, and a protocol extension default is NOT reachable
// here — confirmed empirically (see Sources/NoConfig.swift) — so every
// NoConfig-conforming class needs its own direct override of
// isInConfigMode()/enterConfigMode()/exitConfigMode(), delegating to
// NoConfigBehavior.

import Testing
@testable import Swiftmiko

@Suite("NoConfig enforcement")
struct NoConfigEnforcementTests {
    private func testProfile(deviceType: String) -> ConnectionProfile {
        ConnectionProfile(
            host: "203.0.113.1",
            deviceType: deviceType,
            username: "netadmin",
            auth: .none
        )
    }

    @Test("Representative NoConfig classes trivially succeed rather than throwing")
    func noConfigClassesSucceedTrivially() async throws {
        let classes: [BaseConnection] = [
            CheckPointGaiaSSH(profile: testProfile(deviceType: "checkpoint_gaia")),
            PluribusSSH(profile: testProfile(deviceType: "pluribus")),
            F5TmshSSH(profile: testProfile(deviceType: "f5_tmsh")),
            JuniperScreenOsSSH(profile: testProfile(deviceType: "juniper_screenos")),
            FortinetSSH(profile: testProfile(deviceType: "fortinet")),
            NetscalerSSH(profile: testProfile(deviceType: "netscaler")),
            SophosSfosSSH(profile: testProfile(deviceType: "sophos_sfos")),
            DigiTransportSSH(profile: testProfile(deviceType: "digi_transport")),
            BintecBossSSH(profile: testProfile(deviceType: "bintec_boss")),
            VertivMPHBase(profile: testProfile(deviceType: "vertiv_mph")),
        ]
        for connection in classes {
            #expect(try await connection.isInConfigMode() == true)
            #expect(try await connection.enterConfigMode() == "")
            #expect(try await connection.exitConfigMode() == "")
        }
    }

    @Test("CiscoFtdSSH is the one real exception: hard failure, not a no-op")
    func ciscoFtdHardFails() async throws {
        let ftd = CiscoFtdSSH(profile: testProfile(deviceType: "cisco_ftd"))
        #expect(ftd.supportsConfigMode == false)
        #expect(try await ftd.isInConfigMode() == false)
        await #expect(throws: (any Error).self) {
            try await ftd.enterConfigMode()
        }
    }

    @Test("A driver that doesn't conform to NoConfig keeps real config-mode behavior")
    func unrelatedDriverKeepsRealBehavior() {
        #expect(CiscoSSHConnection(profile: testProfile(deviceType: "cisco_ios")).supportsConfigMode == true)
    }

    @Test(
        "\"Soft\" NoConfig classes (own sendConfigSet override) are also trivial pass-throughs",
        arguments: [
            "cloudgenix_ion" as String,
            "zyxel",
            "adva_aos_fsp_150_f3",
        ]
    )
    func softNoConfigClassesAreTrivialPassThroughs(deviceType: String) async throws {
        let profile = testProfile(deviceType: deviceType)
        let connection: BaseConnection
        switch deviceType {
        case "cloudgenix_ion":
            connection = CloudGenixIonSSH(profile: profile)
        case "zyxel":
            connection = ZyxelSSH(profile: profile)
        default:
            connection = AdvaAosFsp150F3SSH(profile: profile)
        }
        #expect(connection.supportsConfigMode == true)
        #expect(try await connection.isInConfigMode() == true)
        #expect(try await connection.enterConfigMode() == "")
        #expect(try await connection.exitConfigMode() == "")
    }
}
