// Examples/FleetDemo/FleetDevice.swift
import Foundation

struct FleetDevice: Identifiable, Hashable, Sendable {
    let id = UUID()
    var host: String = ""
    var deviceType: String = "cisco_ios"
}

enum FleetResultState: Equatable, Sendable {
    case pending
    case running
    case success(String)
    case failure(String)
}
