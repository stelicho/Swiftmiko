// Examples/MikrotikDemo/ContentView.swift
import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var viewModel = MikrotikViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Connection") {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Host")
                        TextField("192.168.1.1", text: $viewModel.host)
                    }
                    GridRow {
                        Text("Username")
                        TextField("admin", text: $viewModel.username)
                    }
                    GridRow {
                        Text("Password")
                        SecureField("••••••", text: $viewModel.password)
                    }
                }
                .padding(4)

                Text("No enable secret or config mode here — RouterOS has neither through this driver (NoEnable, NoConfig).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                    .help("Only enable this for old firmware that doesn't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")
                    .padding(.horizontal, 4)

                HStack {
                    Spacer()
                    if viewModel.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Disconnect") {
                            Task { await viewModel.disconnect() }
                        }
                    } else {
                        Button("Connect") {
                            Task { await viewModel.connect() }
                        }
                        .disabled(viewModel.host.isEmpty || viewModel.isRunning)
                    }
                }
            }

            GroupBox("Command") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use custom command", isOn: $viewModel.useCustomCommand)

                    if viewModel.useCustomCommand {
                        TextField("e.g. /interface print", text: $viewModel.customCommand)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Command", selection: $viewModel.selectedCommand) {
                            ForEach(MikrotikCommand.library) { command in
                                Text(command.label).tag(command)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text(viewModel.effectiveCommand)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if viewModel.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Button("Run") {
                            Task { await viewModel.runCommand() }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isRunning || viewModel.effectiveCommand.isEmpty)
                    }
                }
                .padding(4)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            ScrollView {
                Text(viewModel.output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color.secondary.opacity(0.3))
        }
        .padding()
        .frame(minWidth: 750, minHeight: 600)
    }
}
