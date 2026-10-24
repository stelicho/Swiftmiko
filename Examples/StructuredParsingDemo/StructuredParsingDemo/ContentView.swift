// Examples/StructuredParsingDemo/ContentView.swift
import SwiftUI
import Swiftmiko

struct ContentView: View {
    @State private var viewModel = StructuredParsingViewModel()

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Swiftmiko — Structured Parsing Demo")
                    .font(.title2)
                    .bold()

                GroupBox("Device") {
                    Grid(alignment: .leading) {
                        GridRow {
                            Text("Host")
                            TextField("192.168.1.1", text: $viewModel.host)
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
                            Text("Password")
                            SecureField("••••••", text: $viewModel.password)
                        }
                        GridRow {
                            Text("Command")
                            TextField("show version", text: $viewModel.command)
                        }
                    }
                    .padding(4)
                }

                Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                    .help("Only enable this for old images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")

                HStack {
                    Button("Load Sample Output") {
                        viewModel.loadSample()
                    }
                    .help("Parse a realistic sample \"show version\" transcript without connecting to anything.")

                    Spacer()

                    if viewModel.isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Button("Connect & Run") {
                        Task { await viewModel.runAgainstDevice() }
                    }
                    .disabled(viewModel.host.isEmpty || viewModel.isRunning)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Text("Raw Output")
                    .font(.headline)
                ScrollView {
                    Text(viewModel.rawOutput)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.secondary.opacity(0.3))
            }
            .padding()
            .frame(minWidth: 420)

            HSplitView {
                parsedResultColumn(
                    title: "TextFSM (ntc-templates cisco_ios_show_version)",
                    result: viewModel.textFSMResult
                )
                parsedResultColumn(
                    title: "TTP",
                    result: viewModel.ttpResult
                )
            }
            .frame(minWidth: 520)
        }
        .frame(minWidth: 1000, minHeight: 650)
        .onAppear {
            viewModel.loadSample()
        }
    }

    @ViewBuilder
    private func parsedResultColumn(title: String, result: String?) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding([.horizontal, .top])

            ScrollView {
                Text(result ?? "Run a parse to see results here.")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color.secondary.opacity(0.3))
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 250)
    }
}
