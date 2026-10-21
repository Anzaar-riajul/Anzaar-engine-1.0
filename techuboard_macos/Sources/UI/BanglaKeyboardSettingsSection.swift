// BanglaKeyboardSettingsSection.swift
// Settings panel for TechuAvro — the official Bangla phonetic system keyboard.
// Embedded in SettingsView under the "বাংলা কীবোর্ড" page.

import SwiftUI
import AppKit
import Carbon.HIToolbox

struct BanglaKeyboardSettingsSection: View {

    // MARK: - State
    @State private var isInstalled: Bool = TechuAvroInstaller.isInstalled()
    @State private var isWorking: Bool = false
    @State private var statusMessage: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // MARK: - Body
    var body: some View {
        Section {
            // Header card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "character.textbox")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("TechuAvro বাংলা কীবোর্ড")
                            .font(.headline)
                        Text("অফিশিয়াল ফনেটিক ইনপুট মেথড")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Status badge
                    Label(
                        isInstalled ? "সক্রিয়" : "নিষ্ক্রিয়",
                        systemImage: isInstalled ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isInstalled ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        isInstalled ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1),
                        in: Capsule()
                    )
                }

                Divider()

                // How-it-works description
                VStack(alignment: .leading, spacing: 6) {
                    featureRow(icon: "keyboard", text: "ইনস্টল করলে macOS মেনু বারে নিজের ইনপুট সোর্স হিসেবে দেখাবে")
                    featureRow(icon: "textformat", text: "যেকোনো অ্যাপে ফনেটিক বাংলা টাইপিং (ami → আমি, kivabe → কিভাবে)")
                    featureRow(icon: "list.number", text: "লাইভ ক্যান্ডিডেট উইন্ডো — ১–৯ কী দিয়ে শব্দ বেছে নিন")
                    featureRow(icon: "arrow.uturn.left", text: "Space দিয়ে commit, Escape দিয়ে বাতিল, Backspace দিয়ে ঠিক করুন")
                }
            }
            .padding(.vertical, 4)

            // Install / Uninstall button
            HStack {
                Spacer()
                if isWorking {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 6)
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button(action: toggleInstall) {
                        Label(
                            isInstalled ? "কীবোর্ড সরিয়ে ফেলুন" : "কীবোর্ড ইনস্টল করুন",
                            systemImage: isInstalled ? "trash" : "arrow.down.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isInstalled ? .red : .blue)
                }
                Spacer()
            }
            .padding(.top, 4)

            // Instructions after install
            if isInstalled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("কীভাবে ব্যবহার করবেন:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    instructionStep(number: "1", text: "মেনু বারে 🌐 আইকনে ক্লিক করুন বা Ctrl+Space চাপুন")
                    instructionStep(number: "2", text: "\"TechuAvro\" সিলেক্ট করুন")
                    instructionStep(number: "3", text: "যেকোনো অ্যাপে টাইপ শুরু করুন — বাংলা আপনাআপনি আসবে!")

                    Button("Input Sources সেটিংস খুলুন") {
                        openInputSourcePreferences()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                .padding(.top, 4)
            }

        } header: {
            Text("বাংলা কীবোর্ড")
        }
        .alert("ত্রুটি", isPresented: $showError) {
            Button("ঠিক আছে") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Actions

    private func toggleInstall() {
        isWorking = true
        if isInstalled {
            statusMessage = "সরানো হচ্ছে…"
            DispatchQueue.global(qos: .userInitiated).async {
                let err = TechuAvroInstaller.uninstall()
                DispatchQueue.main.async {
                    isWorking = false
                    if let e = err {
                        errorMessage = e
                        showError = true
                    } else {
                        isInstalled = false
                    }
                }
            }
        } else {
            statusMessage = "ইনস্টল হচ্ছে…"
            // The built app bundle lives next to the main Techuboard.app
            // At runtime we resolve it relative to this app's bundle
            let bundleURL = resolvedTechuAvroBundleURL()
            DispatchQueue.global(qos: .userInitiated).async {
                let err = TechuAvroInstaller.install(from: bundleURL)
                DispatchQueue.main.async {
                    isWorking = false
                    if let e = err {
                        errorMessage = e
                        showError = true
                    } else {
                        isInstalled = true
                    }
                }
            }
        }
    }

    /// Resolves TechuAvro.app relative to the running Techuboard.app bundle.
    /// Convention: TechuAvro.app lives inside Techuboard.app/Contents/Resources/TechuAvro.app
    private func resolvedTechuAvroBundleURL() -> URL {
        // First try embedded location (production: inside .app Resources)
        if let embeddedURL = Bundle.main.url(forResource: "TechuAvro", withExtension: "app") {
            return embeddedURL
        }
        // Dev fallback: sibling directory (when running from build output)
        let appDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let devURL = appDir.appendingPathComponent("TechuAvro.app")
        return devURL
    }

    private func openInputSourcePreferences() {
        // macOS 13+ deep-link to Keyboard > Input Sources
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func instructionStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.blue, in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
