// Examples/EnableDemo/ContentView.swift
import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var viewModel = EnableViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swiftmiko — Enable Mode Demo")
                .font(.title2)
                .bold()

            GroupBox("Connection") {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Host")
                        TextField("cisco1.lasthop.io", text: $viewModel.host)
                    }
                    GridRow {
                        Text("Username")
                        TextField("pyclass", text: $viewModel.username)
                    }
                    GridRow {
                        Text("Password")
                        SecureField("password", text: $viewModel.password)
                    }
                    GridRow {
                        Text("Enable secret")
                        SecureField("secret", text: $viewModel.secret)
                    }
                }
                .padding(4)

                Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                    .help("Only enable this for old IOS images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")
                    .padding(.horizontal, 4)

                HStack {
                    Spacer()
                    if viewModel.isConnecting {
                        ProgressView().controlSize(.small)
                    }
                    Button("Connect & Enable") {
                        Task { await viewModel.connectAndEnable() }
                    }
                    .disabled(viewModel.host.isEmpty || viewModel.isConnecting)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if let prompt = viewModel.prompt {
                GroupBox("Result") {
                    HStack {
                        Text("Prompt after enable:")
                            .foregroundStyle(.secondary)
                        Text(prompt)
                            .font(.system(.body, design: .monospaced))
                            .bold()
                        Spacer()
                    }
                    .padding(4)
                }
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }
}
