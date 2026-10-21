# Techuboard Official Branding & Logo Assets

Techuboard features official branding assets designed for universal cross-platform usage across macOS, Windows, Android, and iOS.

---

## 🎨 Official Logo Variants (`/Logos`)

All logos are maintained in high resolution with strict aspect ratio preservation:

| Asset Name | Resolution | Aspect Ratio | Transparency | Primary Use Case |
| :--- | :--- | :--- | :--- | :--- |
| **`techuboard-square-logo.png`**<br>*(Bangla-English Keyboard Clipboard Logo)* | 1254 × 1254 | **1:1 (Square)** | Opaque Background | **App Icons**: macOS `AppIcon.icns`, Android mipmaps (`ic_launcher`), iOS `AppIcon`, Windows `.ico`, Favicons, and In-App Avatars. |
| **`techuboard-logo.png`**<br>*(Green Keyboard Clipboard Logo)* | 1536 × 1024 | **3:2 (Landscape)** | Transparent Alpha | **Navigation & Headers**: macOS About dialog, Web Studio navbar, README headers, and transparent UI bars. |
| **`techuboard-emblem.png`**<br>*(Techuboard Green Keyboard Emblem)* | 1536 × 1024 | **3:2 (Landscape)** | Transparent Alpha | **Emblem & Badges**: High-contrast branding badges, presentation slides, and promotional banners. |

> [!IMPORTANT]
> **Strict Aspect Ratio Guarantee**:
> Under no circumstances should the geometry or aspect ratio of any logo variant be distorted or stretched.
> When rendering horizontally in HTML/CSS, always use `height: Xpx; width: auto; object-fit: contain;`.
> When rendering square icons, only use the 1:1 `techuboard-square-logo.png`.

---

## 📁 Ecosystem Asset Placements

1. **macOS**:
   - Master Icon: `Techuboard/Resources/AppIcon.png` (1024 × 1024 square, generated from master square logo).
   - Compiled Bundle: `techuboard_macos/Techuboard.app/Contents/Resources/AppIcon.icns`.
   - Packaged Release: `Techu Complete Versions/macOS/Techuboard-macOS.zip`.

2. **Android**:
   - Launcher Icons: `techuboard_android/android/app/src/main/res/mipmap-*` (`ic_launcher.png`, `ic_launcher_round.png`).
   - Adaptive Foreground: `techuboard_android/android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png`.
   - In-App Branding: `techuboard_android/assets/branding/techuboard-logo.png`.

3. **iOS**:
   - Master App Icon: `techuboard_android/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`.

4. **Web Preview Studio**:
   - Navbar Logo: `web_preview/assets/logo.png` (Transparent landscape, `height: 30px; width: auto; object-fit: contain;`).
   - App Icon / Favicon: `web_preview/assets/logo-square.png`.
   - High Contrast Emblem: `web_preview/assets/logo-emblem.png`.
