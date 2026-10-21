// Examples/SCPDemo/SCPViewModel.swift
import AppKit
import Foundation
import Swiftmiko

@MainActor
@Observable
final class SCPViewModel {
    var host = ""
    var username = ""
    var password = ""
    var secret = ""

    var direction: SCPTransferDirection = .put
    var localFileURL: URL?
    var remoteFileName = ""
    var fileSystem = "flash:"
    var enableSCPFirst = false
    var overwriteExisting = false

    /// Off by default. AES-CBC is a real security downgrade (known
    /// plaintext-recovery weaknesses) — only turn this on for lab/EOL
    /// gear you control that has no AES-GCM support.
    var allowLegacyCiphers = false

    var result: FileTransferResult?
    var isRunning = false
    var errorMessage: String?

    var canRun: Bool {
        !host.isEmpty && !remoteFileName.isEmpty && localFileURL != nil && !isRunning
    }

    func pickLocalFileForUpload() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            localFileURL = panel.url
            if remoteFileName.isEmpty, let name = panel.url?.lastPathComponent {
                remoteFileName = name
            }
        }
    }

    func pickLocalDestinationForDownload() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = remoteFileName.isEmpty ? "downloaded-file" : remoteFileName
        if panel.runModal() == .OK {
            localFileURL = panel.url
        }
    }

    func runTransfer() async {
        guard let localFileURL else { return }
        errorMessage = nil
        result = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let profile = ConnectionProfile(
                host: host,
                deviceType: "cisco_ios",
                username: username,
                auth: .password(password),
                secret: secret.isEmpty ? nil : secret,
                allowLegacyCiphers: allowLegacyCiphers
            )
            let connection = try await SSHDispatcher.connectHandler(profile: profile)
            defer { Task { await connection.disconnect() } }

            if !secret.isEmpty {
                try await connection.enterEnableMode(secret: secret)
            }

            // Cisco IOS devices need "ip scp server enable" configured
            // before they'll accept an SCP session at all — this does it
            // for you rather than failing confusingly mid-transfer.
            if enableSCPFirst {
                try await connection.sendConfigSet(["ip scp server enable"])
            }

            result = try await fileTransfer(
                sshConnection: connection,
                sourceFile: direction == .put ? localFileURL.path : remoteFileName,
                destinationFile: direction == .put ? remoteFileName : localFileURL.path,
                fileSystem: fileSystem.isEmpty ? nil : fileSystem,
                direction: direction,
                overwriteFile: overwriteExisting,
                scpClient: NIOSCPClient(profile: profile)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
