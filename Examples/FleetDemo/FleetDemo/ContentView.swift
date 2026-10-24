// Examples/FleetDemo/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var viewModel = FleetViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swiftmiko — Fleet Demo")
                .font(.title2)
                .bold()

            Text("Runs one command against every device below at once via withTaskGroup, rather than one at a time — watch results land independently as each connection finishes.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox("Devices") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($viewModel.devices) { $device in
                        HStack {
                            TextField("host", text: $device.host)
                            TextField("device_type", text: $device.deviceType)
                                .frame(width: 160)
                            statusIcon(for: viewModel.results[device.id])
                            Button(role: .destructive) {
                                viewModel.removeDevice(device.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isRunning)
                        }
                    }
                    Button("Add Device", systemImage: "plus.circle") {
                        viewModel.addDevice()
                    }
                    .disabled(viewModel.isRunning)
                }
                .padding(4)
            }

            GroupBox("Credentials & Command") {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Username")
                        TextField("admin", text: $viewModel.username)
                    }
                    GridRow {
                        Text("Password")
                        SecureField("••••••", text: $viewModel.password)
                    }
                    GridRow {
                        Text("Command")
                        TextField("show version", text: $viewModel.command)
                    }
                }
                .padding(4)

                Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                    .help("Only enable this for old images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")
                    .padding(.horizontal, 4)

                HStack {
                    Spacer()
                    if viewModel.isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Button("Run Fleet") {
                        Task { await viewModel.runFleet() }
                    }
                    .disabled(viewModel.activeDevices.isEmpty || viewModel.username.isEmpty || viewModel.isRunning)
                }
            }

            if !viewModel.results.isEmpty {
                GroupBox("Results") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(viewModel.activeDevices) { device in
                                if let state = viewModel.results[device.id] {
                                    resultRow(host: device.host, state: state)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .frame(maxHeight: 280)
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 700, minHeight: 600)
    }

    @ViewBuilder
    private func statusIcon(for state: FleetResultState?) -> some View {
        switch state {
        case .none, .pending:
            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func resultRow(host: String, state: FleetResultState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                statusIcon(for: state)
                Text(host).font(.headline)
            }
            switch state {
            case .success(let output):
                Text(output)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            case .failure(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            case .pending, .running:
                EmptyView()
            }
            Divider()
        }
    }
}
