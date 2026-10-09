// Examples/JuniperDemo/ContentView.swift
import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var viewModel = JuniperViewModel()

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

            GroupBox("Operational Command") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use custom command", isOn: $viewModel.useCustomCommand)

                    if viewModel.useCustomCommand {
                        TextField("e.g. show route summary", text: $viewModel.customCommand)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Command", selection: $viewModel.selectedCommand) {
                            ForEach(JuniperCommand.library) { command in
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

            GroupBox("Candidate Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One \"set\"/\"delete\" statement per line. Loaded without leaving config mode, so Commit below has something to act on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $viewModel.configText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 70)
                        .border(Color.secondary.opacity(0.3))

                    HStack {
                        if viewModel.inConfigMode {
                            Label("In config mode", systemImage: "pencil.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                        Spacer()
                        Button("Discard & Exit Config") {
                            Task { await viewModel.discardAndExitConfig() }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isRunning)
                        Button("Load Config") {
                            Task { await viewModel.loadConfig() }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isRunning)
                    }
                }
                .padding(4)
            }

            GroupBox("Commit") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Toggle("Check only (dry run)", isOn: $viewModel.commitCheck)
                        Toggle("Confirmed", isOn: $viewModel.commitConfirm)
                        if viewModel.commitConfirm {
                            TextField("delay (sec)", text: $viewModel.commitConfirmDelay)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                        Toggle("And quit", isOn: $viewModel.commitAndQuit)
                    }
                    TextField("Optional commit comment", text: $viewModel.commitComment)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        if !viewModel.commitArgumentsValid {
                            Text("Invalid combination — \"check\" can't combine with confirm/comment, and a delay needs \"Confirmed\" on.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        if viewModel.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Button("Commit") {
                            Task { await viewModel.commit() }
                        }
                        .disabled(!viewModel.isConnected || viewModel.isRunning || !viewModel.commitArgumentsValid)
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
        .frame(minWidth: 800, minHeight: 760)
    }
}
