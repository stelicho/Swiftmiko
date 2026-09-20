// Examples/C7200Demo/RouterStep.swift
import Foundation
import Swiftmiko

/// A single step in the command sequence, with its own label so the
/// UI can show progress through the list as it runs.
struct RouterStep: Identifiable {
    let id = UUID()
    let label: String
    let command: String
    var output: String = ""
    var status: Status = .pending

    enum Status {
        case pending
        case running
        case done
        case failed
    }
}
