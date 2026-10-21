// Examples/SNMPDemo/ContentView.swift
import SwiftUI
import Swiftmiko

struct ContentView: View {
    @State private var viewModel = SNMPViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swiftmiko — SNMP Demo")
                .font(.title2)
                .bold()

            Text("Uses a minimal real SNMP v1/v2c GET client (written for this demo) to fetch sysDescr, then runs Swiftmiko's own SNMPDetect.autodetect() against it.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox("Target") {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Host")
                        TextField("192.168.1.1", text: $viewModel.host)
                    }
                    GridRow {
                        Text("Community")
                        TextField("public", text: $viewModel.community)
                    }
                    GridRow {
                        Text("Version")
                        Picker("Version", selection: $viewModel.version) {
                            Text("v1").tag(SNMPVersion.v1)
                            Text("v2c").tag(SNMPVersion.v2c)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding(4)

                HStack {
                    Spacer()
                    if viewModel.isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Button("Query") {
                        Task { await viewModel.detect() }
                    }
                    .disabled(viewModel.host.isEmpty || viewModel.community.isEmpty || viewModel.isRunning)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if viewModel.sysDescr != nil || viewModel.detectedDeviceType != nil {
                GroupBox("Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let sysDescr = viewModel.sysDescr {
                            Text("sysDescr").font(.caption).foregroundStyle(.secondary)
                            Text(sysDescr)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        if let deviceType = viewModel.detectedDeviceType {
                            Text("Detected Swiftmiko device type").font(.caption).foregroundStyle(.secondary)
                            Text(deviceType)
                                .font(.system(.body, design: .monospaced))
                                .bold()
                        } else if viewModel.sysDescr != nil {
                            Text("No known device type pattern matched this sysDescr.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
    }
}
