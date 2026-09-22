//
//  ┌───────────────────────────────────────────────────────┐
//  │                   S W I F T M I K O                   │
//  │  Swift-Native Multi-Vendor Network Device Automation  │
//  └───────────────────────────────────────────────────────┘
//
//  Author & Maintainer: K.K. Campbell
//  Created with the assistance of Claude Sonnet 5 (Anthropic),
//  via Claude Code.
//
//  Examples/VlanViewerPad/VlanDetailView.swift

import SwiftUI

struct VlanDetailView: View {
    let vlan: VlanEntry

    var body: some View {
        List {
            Section("VLAN \(vlan.number)") {
                LabeledContent("Name", value: vlan.name.isEmpty ? "—" : vlan.name)
                LabeledContent("Status", value: vlan.status.isEmpty ? "—" : vlan.status)
            }

            Section("Ports (\(vlan.ports.count))") {
                if vlan.ports.isEmpty {
                    Text("No ports assigned")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vlan.ports, id: \.self) { port in
                        Text(port)
                    }
                }
            }
        }
        .navigationTitle("VLAN \(vlan.number)")
    }
}
