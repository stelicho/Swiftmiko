// Examples/C7200Demo/ContentView.swift
import SwiftUI
import Swiftmiko

struct ContentView: View {
    @State private var viewModel = C7200ViewModel()
    @State private var selectedStepID: UUID?

    var body: some View {
        @Bindable var viewModel = viewModel
        HSplitView {
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
                        GridRow {
                            Text("Enable secret")
                            SecureField("optional", text: $viewModel.secret)
                        }
                    }
                    .padding(4)

                    Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                        .help("Only enable this for old IOS images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")
                        .padding(.horizontal, 4)

                    HStack {
                        Spacer()
                        if viewModel.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Button("Run Sequence") {
                            Task { await viewModel.runSequence() }
                        }
                        .disabled(viewModel.host.isEmpty || viewModel.isRunning)
                    }
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
                        Spacer()
                        Text(step.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .tag(step.id)
                }
                .frame(minHeight: 150)
            }
            .padding()
            .frame(minWidth: 320)

            VStack(alignment: .leading) {
                HStack {
                    Text(selectedStepLabel)
                        .font(.headline)
                    Spacer()
                    Button("Save Running Config...") {
                        viewModel.saveRunningConfig()
                    }
                    .disabled(viewModel.runningConfig.isEmpty)
                }
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
            .frame(minWidth: 500)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            selectedStepID = viewModel.steps.last?.id
        }
    }

    private var selectedStep: RouterStep? {
        viewModel.steps.first(where: { $0.id == selectedStepID })
    }

    private var selectedStepLabel: String {
        selectedStep?.label ?? "Select a step"
    }

    private var selectedStepOutput: String {
        selectedStep?.output ?? ""
    }

    @ViewBuilder
    private func statusIcon(_ status: RouterStep.Status) -> some View {
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
