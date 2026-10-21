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
//  Examples/MultiVendorDemoPad/ContentView.swift
//
//  iPhone/iPad counterpart to the macOS MultiVendorDemo: platform
//  choice and connection details move into a toolbar-triggered sheet
//  (see ConnectSheet) instead of always-visible form fields, keeping
//  the main screen focused on picking and running a command.

import SwiftUI
import Swiftmiko

struct ContentView: View {
    @StateObject private var viewModel = MultiVendorPadViewModel()
    @State private var showingConnectSheet = false

    var body: some View {
        NavigationStack {
            Form {
                if viewModel.isConnected {
                    Section("Platform") {
                        Text(viewModel.platform.displayName)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Command") {
                    Toggle("Use custom command", isOn: $viewModel.useCustomCommand)

                    if viewModel.useCustomCommand {
                        TextField("e.g. show version", text: $viewModel.customCommand)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        Picker("Command", selection: $viewModel.selectedCommand) {
                            ForEach(viewModel.platform.commands) { command in
                                Text(command.label).tag(Optional(command))
                            }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.runCommand() }
                    } label: {
                        HStack {
                            Text("Run")
                            if viewModel.isRunning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!viewModel.isConnected || viewModel.isRunning || viewModel.effectiveCommand.isEmpty)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if !viewModel.output.isEmpty {
                    Section("Output") {
                        Text(viewModel.output)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(viewModel.host.isEmpty ? "Multi-Vendor Demo" : viewModel.host)
            .toolbar {
                ToolbarItem {
                    if viewModel.isConnected {
                        Button(role: .destructive) {
                            Task { await viewModel.disconnect() }
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            showingConnectSheet = true
                        } label: {
                            Label("Connect", systemImage: "server.rack")
                        }
                    }
                }
            }
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
}
