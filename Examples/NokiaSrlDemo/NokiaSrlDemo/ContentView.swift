// Examples/NokiaSrlDemo/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var viewModel = NokiaSrlViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Connection") {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Host")
                        TextField("clab-srl-srl1 or 127.0.0.1", text: $viewModel.host)
                    }
                    GridRow {
                        Text("Port")
                        TextField("22", value: $viewModel.port, format: .number)
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
                    .help("Only enable this for old images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")
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
                        TextField("e.g. show network-instance default interfaces brief", text: $viewModel.customCommand)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Command", selection: $viewModel.selectedCommand) {
                            ForEach(NokiaSrlCommand.library) { command in
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
        .frame(minWidth: 700, minHeight: 550)
    }
}
