// Examples/LinuxDemo/LinuxCommand.swift
import Foundation
import Swiftmiko

/// A curated set of commands that work on any plain Linux box, useful for
/// smoke-testing LinuxSSHConnection against a new VM/distro without typing
/// anything.
struct LinuxCommand: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let command: String

    static let library: [LinuxCommand] = [
        .init(label: "Kernel / OS Info", command: "uname -a"),
        .init(label: "OS Release", command: "cat /etc/os-release"),
        .init(label: "Hostname", command: "hostname"),
        .init(label: "Current User", command: "whoami"),
        .init(label: "Uptime", command: "uptime"),
        .init(label: "Disk Usage", command: "df -h"),
        .init(label: "Memory Usage", command: "free -h"),
        .init(label: "Network Interfaces", command: "ip addr"),
        .init(label: "Running Processes", command: "ps aux"),
    ]
}
