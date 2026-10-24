// Examples/StructuredParsingDemo/StructuredParsingViewModel.swift
//
// Runs the same raw CLI output through both of Swiftmiko's native
// structured-parsing engines — TextFSM and TTP — and shows the
// results side by side.
//
// The TTP half uses TTPTemplate.parse(rawText:) directly — the public
// entry point for inline template content. (NativeTTPParser is the
// other public TTP entry point, but it only accepts a template *file
// path*; see StructuredParsingDemo/README.md for the history here.)

import Foundation
import Swiftmiko

@MainActor
@Observable
final class StructuredParsingViewModel {
    var host = ""
    var username = ""
    var password = ""
    var deviceType = "cisco_ios"
    var command = "show version"

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    var allowLegacyCiphers = false

    var rawOutput = ParsingTemplates.sampleShowVersion
    var textFSMResult: String?
    var ttpResult: String?
    var errorMessage: String?
    var isRunning = false

    func loadSample() {
        errorMessage = nil
        rawOutput = ParsingTemplates.sampleShowVersion
        parseCurrentOutput()
    }

    func runAgainstDevice() async {
        errorMessage = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: deviceType,
                username: username,
                auth: .password(password),
                allowLegacyCiphers: allowLegacyCiphers
            )
            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            rawOutput = try await connection.sendCommand(command, readTimeout: 30.0)
            await connection.disconnect()
            parseCurrentOutput()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseCurrentOutput() {
        do {
            let template = try TextFSMTemplate(templateString: ParsingTemplates.textFSM)
            let rows = try template.parseTextToDicts(rawOutput)
            textFSMResult = Self.prettyPrint(rows)
        } catch {
            textFSMResult = "TextFSM parse failed: \(error)"
        }

        do {
            let template = try TTPTemplate(templateString: ParsingTemplates.ttp)
            let rows = template.parse(rawText: rawOutput)
            ttpResult = Self.prettyPrint(rows)
        } catch {
            ttpResult = "TTP parse failed: \(error)"
        }
    }

    private static func prettyPrint(_ rows: [[String: Any]]) -> String {
        guard JSONSerialization.isValidJSONObject(rows),
              let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "\(rows)"
        }
        return string
    }
}
