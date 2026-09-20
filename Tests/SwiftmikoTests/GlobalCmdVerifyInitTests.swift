// Tests/SwiftmikoTests/GlobalCmdVerifyInitTests.swift
//
// Regression coverage for a race in several drivers' init() overrides:
// `Task { await self.setGlobalCmdVerify(false) }` scheduled the flip
// asynchronously rather than performing it immediately, so a caller
// reading `cmdVerifyEnabled` right after construction (before the
// enclosing Task had a chance to run on the cooperative pool) could
// still observe the profile's default. Fixed by calling
// setGlobalCmdVerify(false) directly and synchronously inside init.

import Testing
@testable import Swiftmiko

@Suite("Global cmd-verify override at init")
struct GlobalCmdVerifyInitTests {
    private func testProfile(deviceType: String) -> ConnectionProfile {
        ConnectionProfile(
            host: "203.0.113.1",
            deviceType: deviceType,
            username: "netadmin",
            auth: .none
        )
    }

    @Test("Aruba OS SSH disables cmd-verify immediately at init")
    func arubaOsDisablesCmdVerifyImmediately() {
        let connection = ArubaOsSSH(profile: testProfile(deviceType: "aruba_os"))
        #expect(connection.cmdVerifyEnabled == false)
    }

    @Test("HP Comware SSH disables cmd-verify immediately at init")
    func hpComwareSSHDisablesCmdVerifyImmediately() {
        let connection = HPComwareSSH(profile: testProfile(deviceType: "hp_comware"))
        #expect(connection.cmdVerifyEnabled == false)
    }

    @Test("HP Comware Telnet disables cmd-verify immediately at init")
    func hpComwareTelnetDisablesCmdVerifyImmediately() {
        let connection = HPComwareTelnet(profile: testProfile(deviceType: "hp_comware_telnet"))
        #expect(connection.cmdVerifyEnabled == false)
    }

    @Test("Silver Peak VXOA SSH disables cmd-verify immediately at init")
    func silverPeakDisablesCmdVerifyImmediately() {
        let connection = SilverPeakVXOASSH(profile: testProfile(deviceType: "silverpeak_vxoa"))
        #expect(connection.cmdVerifyEnabled == false)
    }

    @Test("A driver that doesn't override cmd-verify keeps the profile default")
    func unrelatedDriverKeepsDefault() {
        let connection = CiscoSSHConnection(profile: testProfile(deviceType: "cisco_ios"))
        #expect(connection.cmdVerifyEnabled == true)
    }
}
