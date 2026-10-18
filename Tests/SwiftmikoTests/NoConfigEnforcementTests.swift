// Tests/SwiftmikoTests/NoConfigEnforcementTests.swift
//
// Regression coverage for the NoConfig marker protocol doing nothing:
// supportsConfigMode defaulted to true on BaseConnection, and only
// Digi/DigiTransport.swift overrode it, out of 28 classes conforming
// to NoConfig — every other one would silently proceed through
// sendConfigSet()/enterConfigMode() against hardware with no config
// mode, instead of throwing configModeNotSupported as documented.
//
// A handful of NoConfig classes (CloudGenixIonSSH, ZyxelSSH,
// AdvaAosFsp150F3SSH) are a deliberate exception: they override
// sendConfigSet() to still push raw commands (with enterConfigMode:
// false), so supportsConfigMode must stay at its inherited `true`
// default for them — otherwise sendConfigSet()'s own
// `guard supportsConfigMode else { throw }` would break their
// legitimately-working behavior. What needed fixing for those was
// enterConfigMode() itself being a genuine no-op, matching their
// "no real config-mode transition ever occurs" doc comments.

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

    @Test("Representative NoConfig classes report supportsConfigMode == false")
    func hardNoConfigClassesDisableConfigMode() {
        #expect(CheckPointGaiaSSH(profile: testProfile(deviceType: "checkpoint_gaia")).supportsConfigMode == false)
        #expect(PluribusSSH(profile: testProfile(deviceType: "pluribus")).supportsConfigMode == false)
        #expect(CiscoFtdSSH(profile: testProfile(deviceType: "cisco_ftd")).supportsConfigMode == false)
        #expect(F5TmshSSH(profile: testProfile(deviceType: "f5_tmsh")).supportsConfigMode == false)
        #expect(JuniperScreenOsSSH(profile: testProfile(deviceType: "juniper_screenos")).supportsConfigMode == false)
        #expect(FortinetSSH(profile: testProfile(deviceType: "fortinet")).supportsConfigMode == false)
        #expect(NetscalerSSH(profile: testProfile(deviceType: "netscaler")).supportsConfigMode == false)
        #expect(SophosSfosSSH(profile: testProfile(deviceType: "sophos_sfos")).supportsConfigMode == false)
    }

    @Test("DigiTransportBase (the one pre-existing correct override) is unchanged")
    func digiTransportStillDisablesConfigMode() {
        #expect(DigiTransportSSH(profile: testProfile(deviceType: "digi_transport")).supportsConfigMode == false)
    }

    @Test("A driver that doesn't conform to NoConfig keeps the default")
    func unrelatedDriverKeepsSupportsConfigModeTrue() {
        #expect(CiscoSSHConnection(profile: testProfile(deviceType: "cisco_ios")).supportsConfigMode == true)
    }

    @Test(
        "\"Soft\" NoConfig classes keep supportsConfigMode true (their sendConfigSet() depends on it)",
        arguments: [
            "cloudgenix_ion" as String,
            "zyxel",
            "adva_aos_fsp_150_f3",
        ]
    )
    func softNoConfigClassesKeepSupportsConfigModeTrue(deviceType: String) {
        let profile = testProfile(deviceType: deviceType)
        switch deviceType {
        case "cloudgenix_ion":
            #expect(CloudGenixIonSSH(profile: profile).supportsConfigMode == true)
        case "zyxel":
            #expect(ZyxelSSH(profile: profile).supportsConfigMode == true)
        default:
            #expect(AdvaAosFsp150F3SSH(profile: profile).supportsConfigMode == true)
        }
    }

    @Test("Soft NoConfig classes' enterConfigMode() is a genuine no-op, not a real transition")
    func softNoConfigEnterConfigModeIsANoOp() async throws {
        let cloudgenix = CloudGenixIonSSH(profile: testProfile(deviceType: "cloudgenix_ion"))
        #expect(try await cloudgenix.enterConfigMode() == "")

        let zyxel = ZyxelSSH(profile: testProfile(deviceType: "zyxel"))
        #expect(try await zyxel.enterConfigMode() == "")

        let advaF3 = AdvaAosFsp150F3SSH(profile: testProfile(deviceType: "adva_aos_fsp_150_f3"))
        #expect(try await advaF3.enterConfigMode() == "")
    }
}
