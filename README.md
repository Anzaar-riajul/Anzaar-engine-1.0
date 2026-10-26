<div align="center">
  <img src="assets/branding/techuboard-square-logo.png" alt="Techuboard" width="100" height="100" style="border-radius: 18px;" />
  <h1>Techuboard</h1>
  <p><strong>Smart Clipboard History, Encrypted Local Sync & TechuAvro Phonetic Keyboard</strong></p>
  <p>Universal multi-device ecosystem for macOS, Windows, Android, and iOS.</p>

  <p>
    <a href="#quick-install">Quick Install</a> ·
    <a href="#core-features">Core Features</a> ·
    <a href="#techuavro-keyboard">TechuAvro Keyboard</a> ·
    <a href="#techusync-architecture">TechuSync</a> ·
    <a href="#commercial-licensing">Commercial License</a>
  </p>
</div>

---

## 🚀 Overview

**Techuboard** (pronounced *Tech U Board*) is a private, cross-platform productivity ecosystem designed for seamless clipboard history management, encrypted peer-to-peer LAN file transfer, and phonetic typing:

* **Techuboard for macOS**: Native Swift/AppKit menu-bar assistant with instant search, text snippets, AI token expenditure tracker, dictionary/translation, and local LAN sync.
* **Techuboard for Android & Windows**: Flutter + Kotlin/Win32 application featuring clipboard synchronization, remote notifications, and the integrated **TechuAvro Keyboard**.
* **TechuAvro (টেক ইউ অভ্র)**: Built-in soft keyboard (Android IME) and transliteration engine providing instant phonetic Bengali typing (`ami` &rarr; `আমি`, `bangla` &rarr; `বাংলা`, `techuboard` &rarr; `টেকুবোর্ড`) combined with a **1-tap Clipboard Quick-Paste Bar** that pastes saved clippings directly into WhatsApp, Notes, or Messenger.
* **Zero Cloud Dependency**: 100% local, peer-to-peer AES-GCM encrypted network synchronization. No cloud servers, accounts, or telemetry required.
* **100% Open & Commercial-Ready**: Clean Apache 2.0 and MIT licensing without GPL copyleft restrictions.

---

## 📦 Click-To-Install Packages ("Techu Complete Versions")

Ready-to-use packages are organized under the `Techu Complete Versions/` directory:

| Platform | Format / File Location | Status | How to Install |
| :--- | :--- | :--- | :--- |
| **macOS** | `Techu Complete Versions/macOS/Techuboard-macOS.zip` | Ready | Unzip, drag `Techuboard.app` into `/Applications`, and open. |
| **Android** | `Techu Complete Versions/Android/Techuboard-Android-v1.0.apk` | Ready | Send APK to phone, tap to install, and enable **TechuAvro** in Settings. |
| **Windows** | `Techu Complete Versions/Windows/` | Ready Script | Run `scripts/package_windows.ps1` to produce a standalone `.exe` & portable `.zip`. |
| **iOS** | `Techu Complete Versions/iOS/` | Dev Build | Open `techuboard_android/ios` in Xcode or deploy via TestFlight. |

---

## ⌨️ TechuAvro Keyboard Engine

TechuAvro is an integrated phonetic typing engine and soft keyboard:

1. **Phonetic Bengali Grammar**: Implements standard phonetic transliteration with automatic conjunct formation (*juktakkhor*), vowel signs (*kar*), and dictionary overrides.
2. **Top Clipboard Quick-Paste Bar**: A horizontal strip above the keyboard displaying recent clippings from Techuboard. Tap any chip to instantly paste into the active chat or document.
3. **Clean English Typography**: Per user design requirements, keyboard controls, spacebars, and labels are displayed in clean English (`TechuAvro`, `Techuboard`, `ENG`) for a modern interface.
4. **Instant Language Switcher**: Switch between English and Bengali with a single tap on the globe or spacebar.
5. **Interactive Playground**: Dedicated in-app testing playground accessible via Settings &rarr; **TechuAvro Keyboard Settings**.

---

## 🔄 TechuSync: Encrypted LAN Synchronization

* **Peer Discovery**: Automatic `/24` subnet multicast discovery or manual `IP:Port` pairing across trusted local Wi-Fi.
* **Zero Cloud**: Data never leaves your local network. Direct socket communication over AES-GCM 256-bit encryption.
* **Text & File Transfer**: Seamless bidirectional text clipboard history synchronization, plus multi-file sending (up to 1 GiB per transfer).
* **Notification Mirroring**: Mirror incoming Android notifications to your macOS or Windows desktop with per-app filters.

---

## 🛠️ Building From Source

### macOS Application
Requirements: macOS 13+, Apple Silicon / Intel, Xcode Command Line Tools (`swiftc`).
```bash
./build_macos_app.sh
```
The output `.app` bundle will be generated at `techuboard_macos/Techuboard.app`.

### Android Application & APK
Requirements: Flutter SDK, Android SDK, Java 17+.
```bash
TECHUBOARD_ALLOW_DEBUG_SIGNING=1 ./build_android_apk.sh
```
Release APKs will be generated in `dist/` and `Techu Complete Versions/Android/`.

---

## 📄 Commercial Licensing & Verification

Techuboard and TechuAvro are released under permissive, commercially unrestricted terms:
* Core Application & Keyboard: **Apache License 2.0 / MIT License**
* No Copyleft (GPL): Legacy GPL-licensed modules have been fully excised.
* Suitable for commercial publication on the Google Play Store, Apple App Store, and enterprise environments with **zero royalties or licensing fees**.
