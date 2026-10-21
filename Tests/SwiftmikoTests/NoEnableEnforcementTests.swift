// Tests/SwiftmikoTests/NoEnableEnforcementTests.swift
//
// Regression coverage for the NoEnable marker protocol's previous
// protocol-extension implementation being unreachable: BaseConnection
// already declares enterEnableMode(secret:command:pattern:
// enablePattern:checkState:caseInsensitive:defaultUsername:) -> String,
// and Swift always resolves a call through a concrete class to that
// inherited member over a protocol extension default — even though
// the extension's `func enterEnableMode(secret:)` signature was also
// callable with just `secret:`. Confirmed with a minimal reproduction
// (see Sources/NoEnable.swift's file comment for the exact repro):
// the class's own method ran, not the extension's.
//
// Real Netmiko's NoEnable is a trivial pass-through
// (check_enable_mode->True, enable/exit_enable_mode->""), so every
// NoEnable-conforming class now has its own direct override of
// isInEnableMode()/enterEnableMode()/exitEnableMode(), delegating to
// NoEnableBehavior.

import Testing
@testable import Swiftmiko

@Suite("NoEnable enforcement")
struct NoEnableEnforcementTests {
    private func testProfile(deviceType: String) -> ConnectionProfile {
        ConnectionProfile(
            host: "203.0.113.1",
            deviceType: deviceType,
            username: "netadmin",
            auth: .none
        )
    }

    @Test("Representative NoEnable classes trivially succeed rather than hitting BaseConnection's default")
    func noEnableClassesSucceedTrivially() async throws {
        let classes: [BaseConnection] = [
            CiscoXrBase(profile: testProfile(deviceType: "cisco_xr")),
            JuniperBase(profile: testProfile(deviceType: "juniper")),
            PaloAltoPanosBase(profile: testProfile(deviceType: "paloalto_panos")),
            HuaweiBase(profile: testProfile(deviceType: "huawei")),
            FlexvnfSSH(profile: testProfile(deviceType: "flexvnf")),
            NokiaSrlSSH(profile: testProfile(deviceType: "nokia_srl")),
            NokiaIsamSSH(profile: testProfile(deviceType: "nokia_isam")),
            DigiTransportSSH(profile: testProfile(deviceType: "digi_transport")),
            AviatWTMSSH(profile: testProfile(deviceType: "aviat_wtm")),
            BintecBossSSH(profile: testProfile(deviceType: "bintec_boss")),
            VertivMPHBase(profile: testProfile(deviceType: "vertiv_mph")),
        ]
        for connection in classes {
            // BaseConnection's own default enterEnableMode() throws
            // notImplemented and isInEnableMode() does a real prompt
            // check — if either of those ran instead of the NoEnable
            // override, these would fail (throw, or return false with
            // no real channel to check a prompt against).
            #expect(try await connection.isInEnableMode() == true)
            #expect(try await connection.enterEnableMode(secret: "irrelevant") == "")
            #expect(try await connection.exitEnableMode() == "")
        }
    }

    @Test("A driver that doesn't conform to NoEnable keeps BaseConnection's real default")
    func unrelatedDriverKeepsRealDefault() async throws {
        let connection = CiscoSSHConnection(profile: testProfile(deviceType: "cisco_ios"))
        await #expect(throws: (any Error).self) {
            try await connection.enterEnableMode(secret: "x")
        }
    }

    @Test("SmciSwitchSmisSSH deliberately overrides isInEnableMode with a real check, not the NoEnable no-op")
    func smciKeepsItsOwnRealCheck() async throws {
        let channel = BufferedChannel()
        try await channel.open()
        let smci = SmciSwitchSmisSSH(profile: testProfile(deviceType: "supermicro_smis"), channel: channel)
        channel.enqueueOutput("switch>")
        // Real prompt check against "#" — a ">" prompt means false,
        // not NoEnableBehavior's hardcoded true.
        #expect(try await smci.isInEnableMode(checkString: "#") == false)
    }
}
