// Examples/SecureConnectDemo/ContentView.swift
import SwiftUI
import Swiftmiko

struct ContentView: View {
    @State private var viewModel = SecureConnectViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swiftmiko — Secure Connect Demo")
                .font(.title2)
                .bold()

            GroupBox("Device") {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Host")
                        TextField("192.168.1.1", text: $viewModel.host)
                    }
                    GridRow {
                        Text("Port")
                        TextField("22", value: $viewModel.port, format: .number)
                    }
                    GridRow {
                        Text("Device Type")
                        TextField("cisco_ios", text: $viewModel.deviceType)
                    }
                    GridRow {
                        Text("Username")
                        TextField("admin", text: $viewModel.username)
                    }
                    GridRow {
                        Text("Command")
                        TextField("show version", text: $viewModel.command)
                    }
                }
                .padding(4)
            }

            GroupBox("Authentication") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Method", selection: $viewModel.authKind) {
                        ForEach(SecureConnectAuthKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch viewModel.authKind {
                    case .password:
                        Grid(alignment: .leading) {
                            GridRow {
                                Text("Password")
                                SecureField("••••••", text: $viewModel.password)
                            }
                        }
                    case .keyFile:
                        Grid(alignment: .leading) {
                            GridRow {
                                Text("Key Path")
                                TextField("~/.ssh/id_ed25519", text: $viewModel.keyPath)
                            }
                            GridRow {
                                Text("Passphrase")
                                SecureField("optional", text: $viewModel.keyPassphrase)
                            }
                        }
                        Text("Ed25519 or ECDSA keys only (OpenSSH/SEC1/PKCS8 PEM) — RSA and passphrase-protected keys throw a clear error. See the README.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }

            GroupBox("Host Key Verification") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Verify against known_hosts (strict)", isOn: $viewModel.strictHostKeyChecking)
                        .help("Off (default) accepts any host key unconditionally — fine for lab gear, no protection against a MITM swapping in its own key.")

                    if viewModel.strictHostKeyChecking {
                        Grid(alignment: .leading) {
                            GridRow {
                                Text("known_hosts Path")
                                TextField("~/.ssh/known_hosts", text: $viewModel.knownHostsPath)
                            }
                            GridRow {
                                Text("Unknown Host Policy")
                                Picker("", selection: $viewModel.hostKeyPolicy) {
                                    Text("Reject").tag(HostKeyPolicy.rejectUnknown)
                                    Text("Trust on First Use").tag(HostKeyPolicy.autoAdd)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }
                        }
                        Text("A host WITH an existing known_hosts entry is always rejected if the presented key doesn't match it, regardless of this policy — that mismatch is what strict checking exists to catch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }

            Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                .help("Only enable this for old images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")

            HStack {
                Spacer()
                if viewModel.isRunning {
                    ProgressView().controlSize(.small)
                }
                Button("Connect & Run") {
                    Task { await viewModel.connect() }
                }
                .disabled(viewModel.host.isEmpty || viewModel.isRunning)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            Text("Output")
                .font(.headline)
            ScrollView {
                Text(viewModel.output ?? "")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color.secondary.opacity(0.3))
        }
        .padding()
        .frame(minWidth: 560, minHeight: 700)
    }
}
