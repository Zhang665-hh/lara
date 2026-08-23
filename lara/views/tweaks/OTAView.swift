import SwiftUI

struct OTAView: View {
    @ObservedObject var mgr: laramgr
    @AppStorage("lara.ota.disabled") private var otaDisabled: Bool = false
    @State private var isWorking: Bool = false
    @State private var lastResult: String? = nil

    var body: some View {
        List {
            Section(header: HeaderLabel(text: "Status", icon: "antenna.radiowaves.left.and.right")) {
                HStack {
                    Text("OTA Updates")
                    Spacer()
                    Text(otaDisabled ? "Disabled" : "Enabled")
                        .foregroundColor(otaDisabled ? .red : .green)
                        .monospaced()
                }
            }

            Section(
                header: HeaderLabel(text: "Actions", icon: "wrench.and.screwdriver"),
                footer: Text("Modifies launchd's disabled.plist via RemoteCall to prevent OTA update daemons from running. A reboot is required for changes to take effect.")
            ) {
                Button {
                    apply(disabled: true)
                } label: {
                    if isWorking && !otaDisabled {
                        HStack {
                            Text("Disabling…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Disable OTA Updates")
                    }
                }
                .disabled(isWorking || otaDisabled)

                Button {
                    apply(disabled: false)
                } label: {
                    if isWorking && otaDisabled {
                        HStack {
                            Text("Enabling…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Enable OTA Updates")
                    }
                }
                .disabled(isWorking || !otaDisabled)

                Button("Respring") {
                    mgr.respring()
                }
                .disabled(isWorking)
            }
        }
        .navigationTitle("OTA Updates")
        .alert("Result", isPresented: Binding(get: { lastResult != nil }, set: { if !$0 { lastResult = nil } })) {
            Button("OK") { lastResult = nil }
        } message: {
            Text(lastResult ?? "")
        }
    }

    private func apply(disabled: Bool) {
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = false
            let locked = self.mgr.withRCRunning {
                ok = ota_set_disabled(disabled)
            }
            if !locked {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.lastResult = "RemoteCall session busy"
                }
                return
            }
            DispatchQueue.main.async {
                isWorking = false
                if ok {
                    otaDisabled = disabled
                    lastResult = disabled
                        ? "OTA updates disabled. Reboot to apply."
                        : "OTA updates enabled. Reboot to apply."
                } else {
                    lastResult = "Operation failed. Check logs for details."
                }
            }
        }
    }
}
