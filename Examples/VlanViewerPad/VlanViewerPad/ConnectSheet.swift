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
//  Examples/VlanViewerPad/ConnectSheet.swift
//
//  The touch-first counterpart to the macOS VlanViewer's always-visible
//  connection form: on iPad/iPhone the connection details live behind a
//  toolbar-triggered sheet instead, keeping the main screen focused on
//  the VLAN list itself.

import SwiftUI

struct ConnectSheet: View {
    @ObservedObject var viewModel: SwitchViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Switch") {
                    TextField("Host", text: $viewModel.host)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $viewModel.password)
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
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button("Connect") {
                            Task {
                                await viewModel.fetchVlans()
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
