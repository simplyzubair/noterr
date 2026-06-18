# Build Notes

Do the preview and test run before building release installers. The current
workspace can be edited, but this Codex session may still be blocked from
writing Flutter tool cache files; use the full-access Codex launcher if `flutter`
hangs.

## Required Tools

- Flutter stable SDK.
- Android Studio with Android SDK and platform tools.
- Java 17.
- Visual Studio Build Tools 2022 with the Desktop development with C++ workload.
- Inno Setup or NSIS for a proper Windows installer.

## Generate Platform Runners

From this folder:

```powershell
flutter create --platforms=windows,android .
flutter pub get
```

## Windows Multi-Window Hook

The desktop sticky-note feature uses `desktop_multi_window`. After generating the Windows runner, edit `windows/runner/flutter_window.cpp`:

Add this include near the other generated plugin include:

```cpp
#include "desktop_multi_window/desktop_multi_window_plugin.h"
```

Then, after `RegisterPlugins(flutter_controller_->engine());` in `FlutterWindow::OnCreate`, add:

```cpp
DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
  auto *flutter_view_controller =
      reinterpret_cast<flutter::FlutterViewController *>(controller);
  RegisterPlugins(flutter_view_controller->engine());
});
```

Without this native hook, the main Windows app can run but child sticky windows may not get their plugins registered.

## Run Windows

For repeatable cloud-sync previews, run [../Configure-Sync.bat](../Configure-Sync.bat)
once, then use:

```powershell
.\Run-Windows-Sync-Preview.bat
```

The config is saved in `sync_config.bat`, which is ignored by git.

```powershell
flutter run -d windows --dart-define=NOTERR_SYNC_URL="https://noterr-sync.YOUR-SUBDOMAIN.workers.dev"
```

For the local-only preview, omit the Cloudflare Worker URL:

```powershell
flutter run -d windows
```

Create or unlock notes, select a note, then use the toolbar button with the
open-window icon to show it as a separate desktop sticky note.

## Build Android APK

For day-to-day mobile testing, prefer the live runner so you do not need to
reinstall APKs after every change:

```powershell
.\Run-Mobile-Live-Sync.bat
```

Keep the terminal open. Press `r` for hot reload, `R` for hot restart, and `q`
to quit.

For a debug APK with cloud sync enabled:

```powershell
.\Build-Android-Sync-Debug.bat
```

```powershell
flutter build apk --release --dart-define=NOTERR_SYNC_URL="https://noterr-sync.YOUR-SUBDOMAIN.workers.dev"
```

The APK will be under:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Build Windows Release

```powershell
flutter build windows --release --dart-define=NOTERR_SYNC_URL="https://noterr-sync.YOUR-SUBDOMAIN.workers.dev"
```

The executable will be under:

```text
build/windows/x64/runner/Release/noterr.exe
```

## Installer

Use [installer/noterr.iss](../installer/noterr.iss) after the Windows release build is available.
