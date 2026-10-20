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

    // MARK: - "super.foo() on a BaseConnection-direct class" footgun sweep
    //
    // Several drivers extend BaseConnection directly (not
    // CiscoBaseConnection) and either called super.enterEnableMode()/
    // exitEnableMode()/disablePaging() — all three unconditionally throw
    // on BaseConnection — or called enterConfigMode()/exitConfigMode()/
    // isInConfigMode()/disablePaging() with NO override in the file at
    // all, silently inheriting the same throwing stubs (or, for config
    // mode, a flag-only no-op that never does real wire I/O). Fixed by
    // adding shared `generic*` helpers to BaseConnection — mirroring
    // CiscoBaseConnection's existing proven implementations — that
    // these drivers now call directly instead of `super.xxx(...)`.

    func testPluribusDisablePagingSendsPagerOffInsteadOfThrowing() async throws {
        let channel = ScriptedChannel(responses: ["pluribus-switch#"])
        try await channel.open()
        let connection = PluribusSSH(
            profile: testProfile(deviceType: "pluribus"),
            channel: channel
        )

        // Before the fix, this always threw notImplemented — Pluribus's
        // own disablePaging() override unconditionally called
        // super.disablePaging(), which resolved to BaseConnection's
        // throwing stub since PluribusSSH extends BaseConnection
        // directly, not CiscoBaseConnection.
        _ = try await connection.disablePaging()

        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("pager off") })
    }

    func testYamahaEnterEnableModeSendsAdministratorCommandAndPassword() async throws {
        let channel = ScriptedChannel(responses: [
            "YAMAHA>",     // isInEnableMode() precheck -> not yet enabled
            "Password: ",  // wait for the password prompt after "administrator"
            "YAMAHA#",     // wait for the prompt after the secret is sent
        ])
        try await channel.open()
        let connection = YamahaSSH(
            profile: testProfile(deviceType: "yamaha", secret: "adminpass"),
            channel: channel
        )

        // Before the fix, this always threw notImplemented — Yamaha's
        // enterEnableMode() called super.enterEnableMode(), which
        // resolved to BaseConnection's throwing stub.
        _ = try await connection.enterEnableMode(secret: "adminpass")

        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("administrator") })
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("adminpass") })
    }

    func testEricssonIposEnterAndExitConfigModeSendRealCommandsNotSilentNoOps() async throws {
        let channel = ScriptedChannel(responses: [
            "router(config)#",  // enterConfigMode: wait for the prompt after "configure"
            "router(config)#",  // exitConfigMode's isInConfigMode() precheck
            "router#",          // exitConfigMode: wait for "#" after "end"
        ])
        try await channel.open()
        let connection = EricssonIposSSH(
            profile: testProfile(deviceType: "ericsson_ipos"),
            channel: channel
        )

        // Before the fix, both of these silently no-opped (BaseConnection's
        // enterConfigMode()/exitConfigMode() just flip the inConfigMode
        // flag and return "" — no throw, but also no real command ever
        // sent to the device) since EricssonIposSSH extends BaseConnection
        // directly and called super.enterConfigMode()/exitConfigMode().
        _ = try await connection.enterConfigMode()
        _ = try await connection.exitConfigMode()

        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("configure") })
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("end") })
    }

    // MARK: - CiscoBaseConnection: serialLogin()'s own raw-string bug dropped "#" from primaryTerminator

    func testCiscoBaseConnectionSerialLoginDoesNotMistakeABannerLineForAnAlreadyCompleteLogin() async throws {
        let channel = ScriptedChannel(responses: [
            "Welcome to IOS, a generic banner line\n",
            "login as: ",
            "assword: ",
            "host#",
        ])
        try await channel.open()
        let connection = CiscoSSHConnection(
            profile: testProfile(deviceType: "cisco_ios", password: "hunter2"),
            channel: channel
        )

        _ = try await connection.serialLogin()

        // Before the fix, primaryTerminator's default compiled to just
        // "\s*$" (trivially matches the end of any string, including
        // the banner line), so serialLogin() would mistake the banner
        // for an already-complete login and never fall through to
        // telnetLogin() at all — neither of these would ever be sent.
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("netadmin") })
        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("hunter2") })
    }

    // MARK: - BaseConnection-direct drivers missing the config-mode generic helpers
    //
    // A second grep pass (for `super.enterConfigMode|super.exitConfigMode|
    // super.isInConfigMode`) found 10 more BaseConnection-direct drivers with
    // the same footgun already fixed elsewhere for enable-mode/disablePaging:
    // calling `super.X()` silently resolves to BaseConnection's stub, not real
    // wire behavior. 7 of the 10 also had no disablePaging() override at all,
    // meaning sessionPreparation() couldn't even complete — most notably
    // Juniper, one of the most widely-used vendors in this entire codebase.

    func testJuniperDisablePagingSendsRealCommandsInsteadOfThrowing() async throws {
        let channel = ScriptedChannel(responses: ["Screen length set to 0\n>"])
        try await channel.open()
        let connection = JuniperSSH(
            profile: testProfile(deviceType: "juniper_junos"),
            channel: channel
        )

        // Before the fix, JuniperBase had no disablePaging() override at
        // all, so sessionPreparation()'s two calls (for two genuinely
        // different purposes — see the comment on sessionPreparation())
        // resolved to BaseConnection's unconditionally-throwing stub,
        // meaning Juniper devices couldn't even complete session setup.
        _ = try await connection.disablePaging(
            command: "set cli screen-length 0",
            pattern: "Screen length set to"
        )

        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("set cli screen-length 0") })
    }

    func testJuniperEnterAndIsInConfigModeSendRealCommandsNotSilentNoOps() async throws {
        let channel = ScriptedChannel(responses: [
            "Entering configuration mode\n[edit]\nroot@router#",
            "[edit]#",
        ])
        try await channel.open()
        let connection = JuniperSSH(
            profile: testProfile(deviceType: "juniper_junos"),
            channel: channel
        )

        // Before the fix, both of these silently no-opped (BaseConnection's
        // enterConfigMode()/isInConfigMode() just flip/read the in-memory
        // inConfigMode flag — no real command is ever sent) since
        // JuniperBase extends BaseConnection directly and called
        // super.enterConfigMode()/super.isInConfigMode().
        _ = try await connection.enterConfigMode()
        let inConfig = try await connection.isInConfigMode()

        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("configure") })
        XCTAssertTrue(inConfig)
    }

    func testRadETXDisablePagingSendsConfigTermLengthZeroInsteadOfThrowing() async throws {
        let channel = ScriptedChannel(responses: ["config term length 0\n#"])
        try await channel.open()
        let connection = RadETXSSH(
            profile: testProfile(deviceType: "rad_etx"),
            channel: channel
        )

        // Before the fix, RadETXBase had no disablePaging() override at
        // all, so sessionPreparation()'s call resolved to BaseConnection's
        // unconditionally-throwing stub.
        _ = try await connection.disablePaging()

        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("config term length 0") })
    }

    func testWatchguardFirewareEnterAndIsInConfigModeSendRealCommandsNotSilentNoOps() async throws {
        let channel = ScriptedChannel(responses: [
            "fireware(config)#",
            "fireware(config)#",
        ])
        try await channel.open()
        let connection = WatchguardFirewareSSH(
            profile: testProfile(deviceType: "watchguard_fireware"),
            channel: channel
        )

        // Before the fix, both of these silently no-opped since
        // WatchguardFirewareSSH extends BaseConnection directly and
        // called super.enterConfigMode()/super.isInConfigMode().
        _ = try await connection.enterConfigMode()
        let inConfig = try await connection.isInConfigMode()

        XCTAssertTrue(channel.writes.contains { $0.hasPrefix("configure") })
        XCTAssertTrue(inConfig)
    }
}
