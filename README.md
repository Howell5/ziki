# Ziki

**English** | [简体中文](README.zh-CN.md)

<img src="Packaging/Assets/ZikiIcon-1024.png" alt="Ziki split-Z logo" width="96" height="96">

Ziki is a focused, native voice-to-text app for macOS. Tap `fn` to start speaking, then tap it again to transcribe, clean up, and paste your words into the field that has keyboard focus when processing finishes.

Download the current Apple Silicon preview from [GitHub Releases](https://github.com/Howell5/ziki/releases/tag/v0.5.0).

The name takes inspiration from Ziqi, the legendary listener who understood the meaning behind the music. Two resonating ribbons form the Z in the logo: understand first, then put it into words.

### Upgrading from the previous brand

The app is now `Ziki.app`, release packages use `Ziki-<version>-macOS-<architecture>`, and code modules and build variables also use Ziki. No old-name compatibility packages are provided. The old Sotto updater only recognizes the old package name, so this transition requires quitting and moving aside the old app before installing Ziki. Subsequent Ziki versions support in-app updates.

To preserve existing permissions and data, the app retains the `Sotto Local Development` signing certificate, bundle ID `com.willhong.sotto`, Keychain service `com.sotto.voice.credentials`, and the `Sotto` directory under Application Support. These are persistent identities, not public product names. Renaming does not clear settings, keys, history, or diagnostics. macOS may still request permission confirmation after an installation path or executable name changes; follow the system prompts without bypassing security checks.

The app focuses on one workflow:

- A standard Dock app that also stays in the menu bar.
- Tap `fn` to start or finish dictation; press `Esc` to cancel.
- Real-time recognition with Alibaba Cloud Fun-ASR Realtime.
- Conservative cleanup with Qwen3.5 Flash, using the same Workspace and API key.
- System `⌘V` insertion into the currently focused field, with the result also kept on the clipboard.
- API keys in macOS Keychain; no recordings saved by default; final dictation text stored locally for 30 days.

Translation, chat, cloud history, and templates are outside the current scope.

## Install the GitHub preview

Current release packages target Apple Silicon and require macOS 13 or later. The project currently uses a no-cost distribution setup: maintainer builds use a fixed local self-signed certificate, not Apple Developer ID signing or notarization.

1. Download the DMG only from the [Ziki GitHub release](https://github.com/Howell5/ziki/releases/tag/v0.5.0). Use its `SHA256SUMS.txt` to verify the download.
2. Open the DMG and drag Ziki into **Applications**.
3. If macOS blocks the first launch, try right-clicking Ziki and choosing **Open**.
4. If it is still blocked, attempt to open it once, then go to **System Settings → Privacy & Security** and choose **Open Anyway** specifically for Ziki. Authenticate and confirm the launch.
5. Grant Microphone and Accessibility permissions and configure your own Bailian Workspace ID and API key as described below.

For subsequent updates, open **Settings → About** (`关于`), click **Check for Updates** (`检查更新`), then choose the button to update and quit. Ziki downloads the ZIP matching your architecture from the latest GitHub release and verifies its SHA-256, bundle ID, version, and signing identity. Only after verification does it quit and replace the current app. Reopen Ziki manually when the update finishes.

Do not disable Gatekeeper globally or run untrusted commands to remove security restrictions. Managed work or school Macs may prohibit **Open Anyway** and require administrator approval.

API keys are stored in macOS Keychain. When first saving a key or migrating from an ad-hoc build to the fixed local signature, macOS may ask whether Ziki can access the item. After verifying the source, choose **Always Allow**. Updates on the maintainer's Mac using the same certificate, bundle ID, and installation path should not repeatedly prompt. Other Macs do not automatically trust this local certificate; trusted public distribution still requires Developer ID.

## Requirements

- macOS 13 Ventura or later.
- Swift 6.0 or later command-line toolchain for building from source.
- Microphone and Accessibility permissions.
- A Bailian Workspace ID and an API key for the corresponding region.

This is a pure Swift package with no `.xcodeproj` dependency. Build and package it with `swift build`; opening Xcode is not required. By default, `package-app.sh` builds only for the current Mac's architecture. To distribute both Apple Silicon and Intel builds, build each architecture and either combine them or release separate packages.

## Build and run

Compile the source:

```bash
swift build
```

Do not launch the app with `swift run Ziki` or by running `.build/.../Ziki` directly. A bare SwiftPM executable lacks the app's `Info.plist` and audio-input entitlement; macOS may terminate it when it requests microphone access. Always package the app first and launch the resulting `.app` bundle.

Run the test harnesses and brand checks:

```bash
swift run ZikiCoreTestHarness
swift run ZikiAppTestHarness
swift scripts/verify-brand.swift
```

Optionally run the live cleanup-model evaluation. This uses your Bailian quota, but does not activate the microphone or read dictation history:

```bash
swift build
ZIKI_BUILD_DIR="$(swift build --show-bin-path)"
swiftc -parse-as-library -I "$ZIKI_BUILD_DIR/Modules" \
  "$ZIKI_BUILD_DIR"/ZikiCore.build/*.o \
  Sources/Ziki/TranscriptPolisher.swift scripts/evaluate-cleanup.swift \
  -o .build/evaluate-cleanup
ZIKI_EVAL_API_KEY="$(security find-generic-password -s com.sotto.voice.credentials -a fun-asr-api-key -w)" \
ZIKI_EVAL_WORKSPACE="$(defaults read com.willhong.sotto funWorkspaceID)" \
ZIKI_EVAL_REGION="$(defaults read com.willhong.sotto funRegion)" \
  .build/evaluate-cleanup
```

The evaluation submits six fixed examples sequentially using the production request builder and cleanup call. Review the output manually. Assertions are for evaluation only: they do not audit text at runtime or guarantee that the model never makes mistakes. Never run credential-bearing commands with shell tracing (`set -x`) enabled.

Package a release app:

```bash
./scripts/package-app.sh
open outputs/Ziki.app
```

The script:

1. Builds the app with `swift build -c release --product Ziki`.
2. Creates `outputs/Ziki.app`.
3. Embeds the standalone `ZikiUpdater` helper in the app bundle.
4. Copies `Info.plist`.
5. Applies an ad-hoc hardened-runtime signature using `Packaging/Ziki.entitlements`.
6. Verifies the app bundle and signature.

The default signing identity is `-`. If you have a Developer ID certificate, specify it explicitly:

```bash
ZIKI_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/package-app.sh
```

This signs the app; it does not submit it for notarization.

### Local development: stable signing and Keychain access

`package-app.sh` defaults to ad-hoc signing. Every rebuild changes the code hash, so Keychain may treat it as a different app and ask again for permission to read the API key. This is a macOS security check, not an API service error.

For local development, you can create a free, stable signing certificate for your own use:

1. Open **Keychain Access**.
2. Choose **Keychain Access → Certificate Assistant → Create a Certificate**.
3. Name it `Sotto Local Development`.
4. Select **Self Signed Root** as the identity type and **Code Signing** as the certificate type.
5. Enable **Let me override defaults**, then keep the remaining defaults and finish.

Verify that the signing identity is available:

```bash
security find-identity -v -p codesigning
```

Then use this workflow for local builds:

```bash
./scripts/package-dev-app.sh
open outputs/Ziki.app
```

The script uses `Sotto Local Development` and disables online timestamps for this local self-signed build. Keychain may ask once when `/usr/bin/codesign` first accesses the certificate's private key. Verify that the request comes from the system `codesign` tool before choosing **Always Allow**. Ziki may also prompt once when first accessing an existing API key after migration from an ad-hoc build. Subsequent rebuilds with the fixed identity should not repeatedly prompt.

This certificate provides stable local identity; it does not replace Apple notarization or establish public trust. To use a differently named certificate:

```bash
ZIKI_DEVELOPMENT_CODESIGN_IDENTITY="Your Local Code Signing" \
  ./scripts/package-dev-app.sh
```

## First launch and permissions

The settings window opens on first launch. Grant these two permissions:

1. **Microphone**: used only when you actively start dictation.
2. **Accessibility**: used to detect a standalone `fn` press, avoid secure input fields, and paste into the field with system keyboard focus.

If Ziki still shows a permission as unavailable after you change it in System Settings:

1. Confirm that Ziki is enabled in **System Settings → Privacy & Security**.
2. Quit Ziki completely and reopen it.
3. If rebuilding an ad-hoc version changed its signing identity, you may need to remove the old permission entry and authorize it again.

Ziki does not automatically type into secure fields such as password inputs. It first copies the final text to the clipboard, then sends one `⌘V` to the field that actually has keyboard focus when processing finishes. It does not preselect a target based on component type, window, or process relationships.

## Configure the speech service

Open Ziki from the Dock, Spotlight, Launchpad, or menu bar, then select **Bailian** (`百炼`). Some app settings currently use Chinese labels; the labels below help you locate them.

Fun-ASR streams PCM audio and receives recognition results during recording. Once transcription finishes, Qwen3.5 Flash cleans up filler words, repetition, and explicit self-corrections. Both calls share one Bailian configuration.

1. Select the region matching your Alibaba Cloud Model Studio account:
   - Mainland China (Beijing).
   - International (Singapore).
2. Enter your Bailian **Workspace ID**.
3. Enter the API key for that region.
4. Click **Save API Key** (`保存 API Key`).
5. Click **Test Both Models** (`测试两个模型`) to verify Fun-ASR and the cleanup of a sample that corrects a meeting time from 6 to 8.

API keys and endpoints from different regions are not interchangeable. If authorization fails, check the region first, then the key.

Cleanup is enabled by default. Disable it under **Speech → Automatically clean up dictation** (`语音 → 自动整理口述内容`). Output follows the language you speak: Chinese stays Chinese and English stays English; it is not translated. The model uses context to repair likely recognition errors, remove filler words, preserve questions and uncertainty, and use lists only when helpful. Completed model output is delivered without regex, numeric-difference, or length-ratio audits. Failed requests, empty responses, or unfinished output fall back to the original transcription. The model can still make mistakes; check important amounts, dates, email addresses, and similar details.

**Speech → Reference recent dictations** (`语音 → 参考最近几轮听写`) is enabled by default. Within the same target app, up to three complete turns of recognized and cleaned-up text, totaling at most 8,000 characters, accompany the next Qwen cleanup request. There is no additional summary or review-model call. Entire turns are dropped when the context budget is exceeded; fragments are not retained, and the current dictation is still submitted in full. Earlier turns are fallible reference material, not confirmed terminology. Context is neither restored from the 30-day history nor read from other apps' chat windows or AI replies.

Context resets when you switch target apps, more than 10 minutes pass since the previous cleanup completed, you clear it manually, or you restart Ziki. One app can contain multiple conversations: when changing chats or topics, choose **Start a new conversation (clear context)** (`开始新对话（清空上下文）`) in the menu bar or Speech settings. You can also disable recent context entirely. Context is held in memory by default; when diagnostics are enabled, the context used for each request is also saved with that session's diagnostics. API keys stay in Keychain; non-secret settings such as Workspace ID and region use UserDefaults.

## Use the Fn toggle

1. Place the cursor in your target input field.
2. Tap `fn` once. The bottom overlay shows **Listening…**.
3. Speak naturally.
4. Tap `fn` again. The overlay changes to **Thinking…**.
5. Once recognition and cleanup finish, the overlay disappears before Ziki sends `⌘V` to the field that has keyboard focus at that moment.
6. No extra confirmation appears after successful insertion. The final text remains on the clipboard, so you can press `⌘V` again if needed.

Press `Esc` during dictation to cancel. Ziki uses an approximately 120 ms guard against accidental `fn` activation. Combining `fn` with function keys, arrow keys, or other keys does not trigger dictation. You can also choose **Start Listening / Finish Dictation** from the menu bar.

**Speech → Mute system output while recording** (`语音 → 录音时静音系统声音`) is enabled by default. Ziki mutes the current system output before microphone capture and restores it immediately after capture stops, without waiting for ASR or Qwen. Music and video keep playing, and volume values do not change. Devices that were already muted stay muted; manual volume adjustments are not overwritten. Recording failure, cancellation, timeout, and normal app exit share the same restoration path. An internal recording-engine restart does not restore sound prematurely.

When the default output changes, Ziki mutes the new device before restoring the previous one. This requires a writable device-level mute control. Unsupported HDMI or channel-level outputs prompt you to mute manually. Players routed separately to another device are not controlled; notification sounds on the muted output are muted too.

If a device disconnects, restoration fails, or the app is force-quit, Ziki retains a small recovery record keyed by device UID, with no audio. Restarting the app does not automatically unmute devices. After reconnecting a device, choose **Restore devices previously muted by Ziki** (`恢复上次由 Ziki 静音的设备`) in the menu bar or Speech settings. A forced exit cannot guarantee immediate restoration; use the system mute key if necessary. If you manually unmute during recording, Ziki does not keep forcing mute back on. Restoration checks the mute state at the end and cannot distinguish a manual unmute-then-remute from the original Ziki-applied mute; disable automatic muting if this distinction matters for your workflow.

If the default input is a classic Bluetooth headset, Ziki displays a notice but continues recording. Bluetooth HFP can temporarily reduce playback quality while recording. Ziki fully releases the audio engine after dictation ends or is canceled so the system can return to higher-quality playback. To keep high-quality headset playback during dictation, use the MacBook microphone as the system input and the headset only as output.

Every valid final dictation is saved to local history before Ziki attempts to paste it. Use **History** (`历史`) in the settings sidebar or **Open History…** in the menu bar to search, copy, or delete entries. Copying only updates the clipboard; it does not paste again. History is retained for 30 days and can also be cleared manually.

To investigate truncated dictation or missing output, enable **Privacy → Save local diagnostics** (`隐私 → 保存本地诊断记录`). Each dictation creates WAV audio and a `session.json` file under `~/Library/Application Support/Sotto/Diagnostics/`, recording the ASR text, cleanup context, model and prompt versions, Qwen result, delivery or fallback decision, final text, and error stage. Diagnostics remain local, are excluded from system backups, and are automatically deleted after seven days. They may contain sensitive content; disable diagnostics and clear the records after troubleshooting.

If tapping `fn` does nothing, check Accessibility permission and make sure macOS has not assigned the standalone key to system dictation, input-source switching, or the emoji panel.

If `fn` also opens the emoji panel, go to **System Settings → Keyboard** and set **Press fn / Globe key to** to **Do Nothing**. The macOS shortcut and Ziki's global listener are independent; remove the conflicting system action first.

## Data and privacy

- Audio is sent to Alibaba Cloud Fun-ASR Realtime in your selected region.
- With cleanup enabled, transcription text is sent to Qwen3.5 Flash in the same Bailian Workspace. With recent context enabled, previous recognized and cleaned-up turns are also sent; they are not used solely on-device.
- By default, Ziki does not write recordings, live recognition fragments, or pre-cleanup transcripts to disk. Recent context stays in memory, while final cleaned-up text is stored locally in Application Support for 30 days.
- History does not contain the target app, window, PID, paste status, or copy status, and is not synced to the cloud.
- When you explicitly enable diagnostics, WAV audio, recognized and cleaned-up text, cleanup context, and model versions are retained locally for seven days. API keys are not written to diagnostics.
- Third-party services' data retention and training policies are governed by their own terms.

## Distribution status

Open `outputs/Ziki-0.5.0-macOS-arm64.dmg` and drag Ziki into **Applications**. You can then launch it from the Dock, Spotlight, Launchpad, Finder, or menu bar. Clicking the Dock icon again restores the settings window.

The project currently uses no-cost distribution. `package-distribution.sh` defaults to the fixed `Sotto Local Development` local signature and **does not notarize the app**. This preserves app identity across updates on the maintainer's Mac. Other Macs do not automatically trust the certificate, so Gatekeeper may warn about an unverified developer.

In-app updates require release assets named exactly `Ziki-<version>-macOS-<architecture>.zip` and matching designated requirements between the old and new apps. Do not change the signing certificate between releases. GitHub release assets must also retain their SHA-256 digests or the client will reject installation.

Locally built apps can usually launch directly. Apps downloaded through a browser or messaging app may be blocked on first launch. Try right-clicking the app and choosing **Open**; if it is still blocked, use **System Settings → Privacy & Security → Open Anyway** for that specific app. Do not disable Gatekeeper globally.

For trusted public distribution and stable identity across versions, the project still needs Apple Developer Program membership and:

- Developer ID Application signing.
- Hardened Runtime.
- Apple notarization and stapling.
- First-launch permission and upgrade-retention checks on a clean Mac.

The full app relies on Accessibility to monitor global `fn` presses and paste into other apps, while the Mac App Store requires App Sandbox. The current intended public distribution route is therefore a Developer ID-signed, notarized standalone DMG rather than the Mac App Store. A store version would need a separate sandboxed, copy-only workflow.

## Troubleshooting

**Ziki is missing from the menu bar**

Open Ziki again from the Dock or Spotlight. Normally, the settings window and menu bar icon reappear. If neither is visible, use Activity Monitor to check whether the process is running.

**Recognition succeeds, but nothing is pasted**

Check Accessibility permission and make sure your intended input field has focus when the Thinking overlay disappears. Ziki keeps the result on the clipboard; press `⌘V` to paste it manually.

**Fun-ASR returns an authorization error**

Make sure your account region, the region in settings, and the API key all match the same Model Studio endpoint.

**Permissions stop working after a rebuild**

An ad-hoc signature changes with the executable, so macOS may treat a rebuild as a new permission target. For local development, create a self-signed certificate as described above and use `./scripts/package-dev-app.sh`. Trusted public previews need Developer ID signing for stable identity across machines and versions.

**Keychain asks for API key access on every launch or rebuild**

Older development builds used an ad-hoc code hash that changed with each build, and Keychain protects credentials by signing identity. The app now reads the key once at startup and reuses it in memory. Combined with fixed local signing, confirmation should normally be needed only when trust is first established or when migrating from an old signature. Do not grant every app access to the Keychain item just to remove prompts.
