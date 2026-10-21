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
//  Examples/MultiVendorDemoPad/ConnectSheet.swift
//
//  The touch-first counterpart to the macOS MultiVendorDemo's
//  always-visible platform-picker-plus-form: on iPad/iPhone the
//  platform choice and connection details both live behind a
//  toolbar-triggered sheet, keeping the main screen focused on running
//  commands and reading output.

import SwiftUI

struct ConnectSheet: View {
    @ObservedObject var viewModel: MultiVendorPadViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Platform") {
                    Picker("Device Type", selection: $viewModel.platform) {
                        ForEach(DevicePlatform.allCases) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                }

                Section("Device") {
                    TextField("Host", text: $viewModel.host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $viewModel.password)
                    if viewModel.platform.supportsEnableMode {
                        SecureField("Enable secret (optional)", text: $viewModel.secret)
                    }
                }

                Section {
                    Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                } footer: {
                    Text("Only enable this for old IOS images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isConnecting {
                        ProgressView()
                    } else {
                        Button("Connect") {
                            Task {
                                await viewModel.connect()
                                if viewModel.errorMessage == nil {
                                    isPresented = false
                                }
                            }
                        }
                        .disabled(viewModel.host.isEmpty || viewModel.username.isEmpty)
                    }
                }
            }
        }
    }
}
