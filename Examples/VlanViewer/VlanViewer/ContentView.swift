// Examples/VlanViewer/ContentView.swift
import SwiftUI
import Swiftmiko

struct ContentView: View {
    @StateObject private var viewModel = SwitchViewModel()

    var body: some View {
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
                }
                .padding(4)

                Toggle("Allow legacy AES-CBC ciphers", isOn: $viewModel.allowLegacyCiphers)
                    .help("Only enable this for old IOS images that don't support AES-GCM. AES-CBC is a known-weaker cipher — use it only against lab/EOL gear you control.")
                    .padding(.horizontal, 4)

                HStack {
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Button("Fetch VLANs") {
                        Task { await viewModel.fetchVlans() }
                    }
                    .disabled(viewModel.host.isEmpty || viewModel.isLoading)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Table(viewModel.vlans) {
                TableColumn("VLAN") { Text("\($0.number)") }
                    .width(50)
                TableColumn("Name", value: \.name)
                TableColumn("Status", value: \.status)
                    .width(80)
                TableColumn("Ports") { vlan in
                    Text(vlan.ports.joined(separator: ", "))
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}
