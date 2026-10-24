// Examples/RedispatchDemo/ContentView.swift
import SwiftUI
import Swiftmiko

struct ContentView: View {
    @State private var viewModel = RedispatchViewModel()
    @State private var selectedStepID: UUID?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Swiftmiko — Redispatch Demo")
                    .font(.title2)
                    .bold()

                GroupBox("First Hop") {
                    Grid(alignment: .leading) {
                        GridRow {
                            Text("Host")
                            TextField("192.168.1.1", text: $viewModel.host)
                        }
                        GridRow {
                            Text("Device Type")
                            TextField("cisco_ios", text: $viewModel.firstDeviceType)
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
                }

                GroupBox("Second Hop (via Telnet)") {
                    Grid(alignment: .leading) {
                        GridRow {
                            Text("Terminal Server Host")
                            TextField("10.0.0.5", text: $viewModel.terminalServerHost)
                        }
                        GridRow {
                            Text("Device Type")
                            TextField("cisco_ios", text: $viewModel.finalDeviceType)
                        }
                        GridRow {
                            Text("Command")
                            TextField("show version", text: $viewModel.finalCommand)
                        }
                    }
                    .padding(4)
                    Text("Uses the first hop's own username/password — telnetLogin() has no separate credentials of its own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                    .help("Only enable this for old images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")

                HStack {
                    Spacer()
                    if viewModel.isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Button("Run Sequence") {
                        Task { await viewModel.runSequence() }
                    }
                    .disabled(
                        viewModel.host.isEmpty || viewModel.terminalServerHost.isEmpty
                            || viewModel.isRunning
                    )
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                List(viewModel.steps, selection: $selectedStepID) { step in
                    HStack {
                        statusIcon(step.status)
                        Text(step.label)
                    }
                    .tag(step.id)
                }
                .frame(minHeight: 150)
            }
            .padding()
            .frame(minWidth: 380)

            VStack(alignment: .leading) {
                Text(selectedStepLabel)
                    .font(.headline)
                    .padding([.horizontal, .top])

                ScrollView {
                    Text(selectedStepOutput)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.secondary.opacity(0.3))
                .padding([.horizontal, .bottom])
            }
            .frame(minWidth: 450)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: viewModel.isRunning) {
            // steps.count never actually changes run to run (always
            // rebuilt as the same 4 fixed stages) — select the first
            // one as a new run starts, rather than leaving whatever
            // was selected from a previous run showing stale output.
            if viewModel.isRunning {
                selectedStepID = viewModel.steps.first?.id
            }
        }
    }

    private var selectedStep: RedispatchStep? {
        viewModel.steps.first(where: { $0.id == selectedStepID })
    }

    private var selectedStepLabel: String {
        selectedStep?.label ?? "Run the sequence to see each step"
    }

    private var selectedStepOutput: String {
        selectedStep?.output ?? ""
    }

    @ViewBuilder
    private func statusIcon(_ status: RedispatchStep.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
