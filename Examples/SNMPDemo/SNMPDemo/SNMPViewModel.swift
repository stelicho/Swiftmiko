// Examples/SNMPDemo/SNMPViewModel.swift
import Foundation
import Swiftmiko

@MainActor
@Observable
final class SNMPViewModel {
    var host = ""
    var community = "public"
    var version: SNMPVersion = .v2c

    var sysDescr: String?
    var detectedDeviceType: String?
    var isRunning = false
    var errorMessage: String?

    /// sysDescr — every device answers this one, which is what makes it
    /// useful both as a standalone GET demo and as the OID most of
    /// SNMPAutodetectMapper's rules (including "cisco_ios") match against.
    private let sysDescrOID = ".1.3.6.1.2.1.1.1.0"

    func detect() async {
        errorMessage = nil
        sysDescr = nil
        detectedDeviceType = nil
        isRunning = true
        defer { isRunning = false }

        do {
            let transport = MinimalSNMPGetTransport()
            let detector = try SNMPDetect(
                hostname: host,
                snmpVersion: version,
                community: community,
                transport: transport
            )

            sysDescr = try await transport.get(
                hostname: host,
                port: detector.snmpPort,
                oid: sysDescrOID,
                credentials: detector.credentials
            )
            detectedDeviceType = try await detector.autodetect()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
