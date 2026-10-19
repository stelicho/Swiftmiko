// Tests/SwiftmikoTests/DriverRegressionTests.swift
//
// Direct behavioral regression coverage for bugs found in a full
// review of Sources/ vendor drivers (fixed in 384ac81) that didn't
// already have a test locking in the fix — these are the ones where
// a structural check (e.g. "does this throw") wasn't enough to prove
// the actual wire-level behavior is correct.

import XCTest
@testable import Swiftmiko

final class DriverRegressionTests: XCTestCase {
    private func testProfile(
        deviceType: String,
        password: String? = nil,
        secret: String? = nil,
        globalDelayFactor: Double = 0.01
    ) -> ConnectionProfile {
        ConnectionProfile(
            host: "203.0.113.1",
            deviceType: deviceType,
            username: "netadmin",
            auth: password.map { .password($0) } ?? .none,
            secret: secret,
            globalDelayFactor: globalDelayFactor
        )
    }

    // MARK: - Audiocode: stripCommand()/stripPrompt() need (?m) to match line boundaries

    func testAudiocodeStripCommandOnlyRemovesTheBannerLineNotFollowingOutput() {
        let channel = BufferedChannel()
        let connection = AudiocodeShellSSH(
            profile: testProfile(deviceType: "audiocode_shell"),
            channel: channel
        )
        let output = "SIP status line here PING stuff\nreal response line 1\nreal response line 2"
        let cleaned = connection.stripCommand("irrelevant", output: output)
        XCTAssertFalse(cleaned.contains("SIP status line"))
        XCTAssertTrue(cleaned.contains("real response line 2"))
    }

    func testAudiocodeStripPromptStripsOnEveryLineNotJustTheFirst() {
        let channel = BufferedChannel()
        let connection = AudiocodeShellSSH(
            profile: testProfile(deviceType: "audiocode_shell"),
            channel: channel
        )
        let output = "/CONFiguration>\nline one\n/CONFiguration/VOIP>\nline two"
        let cleaned = connection.stripPrompt(output)
        XCTAssertFalse(cleaned.contains("/CONFiguration>"))
        XCTAssertFalse(cleaned.contains("/CONFiguration/VOIP>"))
        XCTAssertTrue(cleaned.contains("line one"))
        XCTAssertTrue(cleaned.contains("line two"))
    }

    // MARK: - Nokia SR OS: dotAll parameter was shadowed, not propagated

    func testNokiaResolvePatternAndDotAllKeepsCallerValuesWhenPatternIsExplicit() {
        let resolved = NokiaSros.resolvePatternAndDotAll(
            pattern: "custom-pattern",
            dotAll: true,
            basePrompt: "irrelevant"
        )
        XCTAssertEqual(resolved.pattern, "custom-pattern")
        XCTAssertTrue(resolved.dotAll, "caller's dotAll must survive, not get reset to false")
    }

    func testNokiaResolvePatternAndDotAllFallsBackAndForcesDotAllWhenPatternIsEmpty() {
        let resolved = NokiaSros.resolvePatternAndDotAll(
            pattern: "",
            dotAll: false,
            basePrompt: "A:router1#"
        )
        XCTAssertTrue(resolved.pattern.contains("A:router1#"))
        XCTAssertTrue(resolved.dotAll)
    }

    // MARK: - Furukawa FITELnet: raw-string bug dropped "#" from primaryTerminator

    func testFurukawaTelnetLoginDoesNotMistakeABannerLineForAnAlreadyCompleteLogin() async throws {
        let channel = ScriptedChannel(responses: [
            "Welcome to FITELnet, a generic banner line\n",
            "login as: ",
            "assword: ",
            "host#",
        ])
        try await channel.open()
        let connection = FurukawaFitelnetBase(
            profile: testProfile(deviceType: "furukawa_fitelnet", password: "hunter2"),
            channel: channel
        )

        _ = try await connection.telnetLogin()

        // Before the fix, primaryTerminator's default compiled to just
        // "\s*$" (trivially matches the end of any string), so the very
        // first banner line would be mistaken for login already being
        // complete, and neither of these would ever be sent.
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("netadmin") })
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("hunter2") })
    }

    // MARK: - Huawei SmartAX: disableMMIMode() left "(config)#" unescaped

    func testHuaweiSmartAXDisableMMIModeWaitsForTheEscapedConfigPromptAndSucceeds() async throws {
        let channel = ScriptedChannel(responses: [
            "switch1#",           // isInEnableMode() precheck -> already enabled
            "switch1(config)#",   // isInConfigMode() precheck -> already in config mode
            "switch1(config)#",   // sendCommand()'s expectString wait
        ])
        try await channel.open()
        let connection = HuaweiSmartAXSSH(
            profile: testProfile(deviceType: "huawei_smartax"),
            channel: channel
        )
        connection.basePrompt = "switch1"

        try await connection.disableMMIMode()

        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("mmi-mode disable") })
    }

    // MARK: - Check Point Gaia: enterEnableMode() always threw; fastCli wasn't forced off

    func testCheckPointGaiaFastCliIsForcedOffByDefault() {
        let profile = testProfile(deviceType: "checkpoint_gaia")
        XCTAssertTrue(profile.fastCli, "sanity: the library default is true")
        let connection = CheckPointGaiaSSH(profile: profile, channel: BufferedChannel())
        XCTAssertFalse(connection.profile.fastCli)
    }

    func testCheckPointGaiaEnterEnableModeSendsSecretAndReachesExpertPrompt() async throws {
        let channel = ScriptedChannel(responses: [
            "expert password: ",  // the command's own prompt wait
            "gw-gaia#",            // enableSecretHandler()'s post-secret read
            "gw-gaia#",            // the final setBasePrompt() call
        ])
        try await channel.open()
        let connection = CheckPointGaiaSSH(
            profile: testProfile(deviceType: "checkpoint_gaia", secret: "supersecret"),
            channel: channel
        )

        let output = try await connection.enterEnableMode(secret: "supersecret", checkState: false)

        // Before the fix, this threw notImplemented immediately (super
        // resolved to BaseConnection's unconditional throw) and never
        // reached enableSecretHandler() at all.
        XCTAssertTrue(channel.writes.contains("supersecret"))
        XCTAssertTrue(output.contains("#"))
        XCTAssertEqual(connection.basePrompt, "gw-gaia#")
    }

    // MARK: - Dell Isilon: exitEnableMode()/exitConfigMode() always threw

    func testDellIsilonExitEnableModeSendsExitAndConfirmsItLeftEnableMode() async throws {
        let channel = ScriptedChannel(responses: [
            "root@isilon#",   // isInEnableMode() precheck -> currently enabled
            "isilon$",        // readUntilPattern(#"\$.*$"#) after sending exit
            "isilon$",        // final isInEnableMode() confirmation -> no longer enabled
        ])
        try await channel.open()
        let connection = DellIsilonSSH(
            profile: testProfile(deviceType: "dell_isilon"),
            channel: channel
        )

        let output = try await connection.exitEnableMode()

        // Before the fix, this threw notImplemented immediately (super
        // resolved to BaseConnection's unconditional throw).
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("exit") })
        XCTAssertTrue(output.contains("$"))
    }

    // MARK: - Avara AOS: promptPattern/sessionPreparation didn't match the real "%" prompt

    func testAvaraAosSessionPreparationDetectsThePercentTerminatedPrompt() async throws {
        let channel = ScriptedChannel(responses: [
            "DEVNAME % ",  // testChannelRead(pattern: promptPattern)
            "DEVNAME % ",  // findPrompt() grabbing the base prompt
        ])
        try await channel.open()
        let connection = AvaraAosSSH(
            profile: testProfile(deviceType: "avara_aos"),
            channel: channel
        )

        // Before the fix, the inherited CiscoBaseConnection promptPattern
        // ("[>#]") never matches a "%"-terminated prompt, so this would
        // hang/time out instead of completing.
        try await connection.sessionPreparation()

        XCTAssertEqual(connection.basePrompt, "DEVNAME %")
    }

    // MARK: - Cisco WLC: extended BaseConnection (no working disablePaging) instead of CiscoBaseConnection

    func testCiscoWlcDisablePagingSendsTerminalLengthZeroInsteadOfThrowing() async throws {
        let channel = ScriptedChannel(responses: ["WLC-5508#"])
        try await channel.open()
        let connection = CiscoWlcSSH(
            profile: testProfile(deviceType: "cisco_wlc"),
            channel: channel
        )
        connection.basePrompt = "WLC-5508#"

        // Before the fix, this always threw notImplemented — BaseConnection's
        // default disablePaging(), inherited because CiscoWlcSSH extended it
        // directly instead of CiscoBaseConnection.
        _ = try await connection.disablePaging()

        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("terminal length 0") })
    }
}
