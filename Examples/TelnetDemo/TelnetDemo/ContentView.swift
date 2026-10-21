// Examples/TelnetDemo/ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var viewModel = TelnetViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swiftmiko — Telnet Demo")
                .font(.title2)
                .bold()

            Text("Telnet is unencrypted — only point this at lab gear on a trusted network, never a production device over an untrusted link.")
                .font(.callout)
                .foregroundStyle(.secondary)

            GroupBox("Connection") {
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Host")
                        TextField("192.168.1.1", text: $viewModel.host)
                    }
                    GridRow {
                        Text("Port")
                        TextField("23", value: $viewModel.port, format: .number)
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
            }

            GroupBox("Command") {
                HStack {
                    TextField("show version", text: $viewModel.command)
                        .textFieldStyle(.roundedBorder)
                    if viewModel.isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Button("Connect & Run") {
                        Task { await viewModel.connectRunAndDisconnect() }
                    }
                    .disabled(viewModel.host.isEmpty || viewModel.isRunning || viewModel.command.isEmpty)
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
        .frame(minWidth: 650, minHeight: 500)
    }
}
