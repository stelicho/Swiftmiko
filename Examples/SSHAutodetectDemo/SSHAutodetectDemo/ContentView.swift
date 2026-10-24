// Examples/SSHAutodetectDemo/ContentView.swift
import SwiftUI
import Swiftmiko

struct ContentView: View {
    @State private var viewModel = SSHAutodetectViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swiftmiko — SSH Autodetect Demo")
                .font(.title2)
                .bold()

            Text("Connects as a neutral terminal-server probe (no vendor-specific session setup), then matches the device's own banners and command output against Swiftmiko's SSHDetect signature table — the SSH-transport sibling of SNMPDemo's SNMP-based autodetect.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox("Target") {
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
                    .help("Only enable this for old images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")
                    .padding(.horizontal, 4)

                HStack {
                    Spacer()
                    if viewModel.isDetecting {
                        ProgressView().controlSize(.small)
                    }
                    Button("Detect") {
                        Task { await viewModel.detect() }
                    }
                    .disabled(viewModel.host.isEmpty || viewModel.username.isEmpty || viewModel.isDetecting)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if viewModel.bestMatch != nil || !viewModel.potentialMatches.isEmpty {
                GroupBox("Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let bestMatch = viewModel.bestMatch {
                            HStack {
                                Text("Best match").font(.caption).foregroundStyle(.secondary)
                                Text(bestMatch)
                                    .font(.system(.body, design: .monospaced))
                                    .bold()
                                Spacer()
                                if viewModel.isVerifying {
                                    ProgressView().controlSize(.small)
                                }
                                Button("Verify by connecting") {
                                    Task { await viewModel.verifyDetectedType() }
                                }
                                .disabled(viewModel.isVerifying)
                            }
                        } else {
                            Text("No signature matched.")
                                .foregroundStyle(.secondary)
                        }

                        if !viewModel.potentialMatches.isEmpty {
                            Text("All candidates scored").font(.caption).foregroundStyle(.secondary)
                            ForEach(viewModel.potentialMatches, id: \.deviceType) { match in
                                HStack {
                                    Text(match.deviceType)
                                        .font(.system(.footnote, design: .monospaced))
                                    Spacer()
                                    Text("\(match.score)")
                                        .font(.system(.footnote, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let verificationOutput = viewModel.verificationOutput {
                            Text("Prompt after reconnecting as the detected type").font(.caption).foregroundStyle(.secondary)
                            Text(verificationOutput)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 620, minHeight: 480)
    }
}
