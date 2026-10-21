// Examples/SCPDemo/ContentView.swift
import SwiftUI
import Swiftmiko

struct ContentView: View {
    @State private var viewModel = SCPViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Swiftmiko — SCP Demo")
                .font(.title2)
                .bold()

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

                Toggle("Enable \"ip scp server enable\" first", isOn: $viewModel.enableSCPFirst)
                    .help("Cisco IOS refuses SCP sessions until this is configured — check this if you haven't already set it up on the device.")
                    .padding(.horizontal, 4)
            }

            GroupBox("Transfer") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Direction", selection: $viewModel.direction) {
                        Text("Put (upload to device)").tag(SCPTransferDirection.put)
                        Text("Get (download from device)").tag(SCPTransferDirection.get)
                    }
                    .pickerStyle(.segmented)

                    Grid(alignment: .leading) {
                        GridRow {
                            Text("Remote filename")
                            TextField("config.txt", text: $viewModel.remoteFileName)
                        }
                        GridRow {
                            Text("Remote filesystem")
                            TextField("flash:", text: $viewModel.fileSystem)
                        }
                        GridRow {
                            Text(viewModel.direction == .put ? "Local source file" : "Local destination file")
                            HStack {
                                Text(viewModel.localFileURL?.path ?? "none selected")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Choose…") {
                                    if viewModel.direction == .put {
                                        viewModel.pickLocalFileForUpload()
                                    } else {
                                        viewModel.pickLocalDestinationForDownload()
                                    }
                                }
                            }
                        }
                    }

                    Toggle("Overwrite if the remote file already exists", isOn: $viewModel.overwriteExisting)

                    HStack {
                        Spacer()
                        if viewModel.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Button("Transfer") {
                            Task { await viewModel.runTransfer() }
                        }
                        .disabled(!viewModel.canRun)
                    }
                }
                .padding(4)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if let result = viewModel.result {
                GroupBox("Result") {
                    Grid(alignment: .leading) {
                        GridRow {
                            Text("File already existed")
                            resultIcon(result.fileExists)
                        }
                        GridRow {
                            Text("File transferred")
                            resultIcon(result.fileTransferred)
                        }
                        GridRow {
                            Text("MD5 verified")
                            resultIcon(result.fileVerified)
                        }
                    }
                    .padding(4)
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 560)
    }

    private func resultIcon(_ value: Bool) -> some View {
        Label(value ? "Yes" : "No", systemImage: value ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(value ? .green : .secondary)
    }
}
