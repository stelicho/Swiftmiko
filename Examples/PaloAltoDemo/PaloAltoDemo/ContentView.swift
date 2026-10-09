// Examples/PaloAltoDemo/ContentView.swift
import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var viewModel = PaloAltoViewModel()

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

                Text("PAN-OS often expects keyboard-interactive SSH auth (to fold a EULA prompt in with the password) — that's not wired into Swiftmiko's transport yet, so this connects with plain password auth. Devices that accept password auth as a fallback work fine; ones that insist on keyboard-interactive will fail to connect here.")
                    .font(.caption)
                    .foregroundStyle(.orange)
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

            GroupBox("Operational Command") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use custom command", isOn: $viewModel.useCustomCommand)

                    if viewModel.useCustomCommand {
                        TextField("e.g. show session info", text: $viewModel.customCommand)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Command", selection: $viewModel.selectedCommand) {
                            ForEach(PaloAltoCommand.library) { command in
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
                        .frame(height: 60)
                        .border(Color.secondary.opacity(0.3))

                    HStack {
                        if viewModel.inConfigMode {
                            Label("In config mode", systemImage: "pencil.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                        Spacer()
                        Button("Exit Config") {
                            Task { await viewModel.exitConfig() }
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
                    TextField("Optional commit comment", text: $viewModel.commitComment)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 16) {
                        Toggle("Force", isOn: $viewModel.commitForce)
                        Toggle("Partial", isOn: $viewModel.commitPartial)
                    }

                    if viewModel.commitPartial {
                        HStack(spacing: 16) {
                            Toggle("Device & Network", isOn: $viewModel.commitDeviceAndNetwork)
                            Toggle("Policy & Objects", isOn: $viewModel.commitPolicyAndObjects)
                            Toggle("No Vsys", isOn: $viewModel.commitNoVsys)
                        }
                        HStack {
                            Text("Vsys")
                            TextField("e.g. vsys2", text: $viewModel.commitVsys)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack {
                        if !viewModel.commitArgumentsValid {
                            Text("Device & Network / Policy & Objects / Vsys / No Vsys all require \"Partial\" to be on.")
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
        .frame(minWidth: 820, minHeight: 800)
    }
}
