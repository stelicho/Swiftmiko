// Examples/RedispatchDemo/RedispatchStep.swift
import Foundation

/// A single stage in the connect → telnet-to-terminal-server →
/// redispatch → run-command sequence, with its own label so the UI
/// can show progress as it runs. Unlike C7200Demo's RouterStep (every
/// step there is literally "send this command"), the stages here are
/// different kinds of operations, so there's no single `command`
/// field — each one just carries whatever output is meaningful for it.
struct RedispatchStep: Identifiable {
    let id = UUID()
    let label: String
    var output: String = ""
    var status: Status = .pending

    enum Status: Equatable {
        case pending
        case running
        case done
        case failed
    }
}
