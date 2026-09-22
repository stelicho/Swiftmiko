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
//  Examples/VlanViewerPad/ContentView.swift
//
//  iPad-first (but iPhone-compatible) counterpart to the macOS
//  VlanViewer: a NavigationSplitView list-detail layout instead of a
//  single window with a permanently-visible form + table. On compact
//  widths (iPhone) NavigationSplitView collapses to a stack
//  automatically, so this one layout covers both idioms.

import SwiftUI
import Swiftmiko

struct ContentView: View {
    @StateObject private var viewModel = SwitchViewModel()
    @State private var selectedVlanID: VlanEntry.ID?
    @State private var showingConnectSheet = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: $showingConnectSheet) {
            ConnectSheet(viewModel: viewModel, isPresented: $showingConnectSheet)
        }
        .onAppear {
            if viewModel.host.isEmpty {
                showingConnectSheet = true
            }
        }
    }

    private var sidebar: some View {
        List(viewModel.vlans, selection: $selectedVlanID) { vlan in
            VStack(alignment: .leading) {
                Text("VLAN \(vlan.number) — \(vlan.name)")
                    .font(.headline)
                Text("\(vlan.status) · \(vlan.ports.count) port(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(viewModel.host.isEmpty ? "VLANs" : "VLANs on \(viewModel.host)")
        .overlay {
            if viewModel.isLoading {
                ProgressView("Fetching VLANs…")
            } else if viewModel.vlans.isEmpty {
                ContentUnavailableView(
                    "No VLANs Yet",
                    systemImage: "network",
                    description: Text("Connect to a switch to see its VLANs.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingConnectSheet = true
                } label: {
                    Label("Connect", systemImage: "server.rack")
                }
            }
            ToolbarItem {
                Button {
                    Task { await viewModel.fetchVlans() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.host.isEmpty || viewModel.isLoading)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = selectedVlanID, let vlan = viewModel.vlans.first(where: { $0.id == id }) {
            VlanDetailView(vlan: vlan)
        } else if let error = viewModel.errorMessage {
            ContentUnavailableView(
                "Connection Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else {
            ContentUnavailableView(
                "Select a VLAN",
                systemImage: "sidebar.left",
                description: Text("Choose a VLAN from the list to see its ports.")
            )
        }
    }
}
