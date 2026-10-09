// Examples/NokiaDemo/ContentView.swift
import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var viewModel = NokiaViewModel()

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
                    GridRow {
                        Text("Admin secret")
                        SecureField("optional — enable/enable-admin", text: $viewModel.adminSecret)
                    }
                }
                .padding(4)

                Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                    .help("Only enable this for old firmware that doesn't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")
                    .padding(.horizontal, 4)

                HStack {
                    if let dialect = viewModel.dialectDescription {
                        Label(dialect, systemImage: "terminal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

            GroupBox("Show Command") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use custom command", isOn: $viewModel.useCustomCommand)

                    if viewModel.useCustomCommand {
                        TextField("e.g. show router interface", text: $viewModel.customCommand)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Command", selection: $viewModel.selectedCommand) {
                            ForEach(NokiaCommand.library) { command in
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
                        Button("Run") {
                            Task { await viewModel.runCommand() }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isRunning || viewModel.effectiveCommand.isEmpty)
                    }
                }
                .padding(4)
            }

            GroupBox("Config / Commit (model-driven CLI only)") {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.isConnected && !viewModel.isModelDriven {
                        Text("This device is on the classical CLI — it has no config mode, so the controls below won't do anything.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    TextEditor(text: $viewModel.configText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 60)
                        .border(Color.secondary.opacity(0.3))

                    HStack {
                        Button("Load Config") {
                            Task { await viewModel.loadConfig() }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isRunning)
                        Button("Discard & Exit Config") {
                            Task { await viewModel.discardAndExitConfig() }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isRunning)
                        Spacer()
                        Button("Commit") {
                            Task { await viewModel.commit() }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isRunning)
                        Button("Save Config") {
                            Task { await viewModel.saveConfig() }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isRunning)
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
        .frame(minWidth: 800, minHeight: 740)
    }
}
