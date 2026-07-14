# Phase 1 Validation

Phase 1 establishes the application shell only. It does not monitor the hotkey, record audio, paste, or call OpenRouter.

## Automated checks

1. Open `dict8/dict8.xcodeproj` in Xcode.
2. Select the `dict8` scheme and **My Mac** destination.
3. Press `Command + U`.
4. Confirm `PhaseZeroFoundationTests` and `PhaseOneAppShellTests` are green.

## Menu bar and settings

1. Press `Command + R` in Xcode.
2. Confirm a microphone icon appears in the macOS menu bar.
3. Confirm dict8 does not appear in the Dock or application switcher.
4. Open the menu and confirm it shows status, Enable/Disable, Settings, and Quit.
5. Select **Disable** and confirm the icon and status change.
6. Quit and relaunch dict8; confirm the disabled preference persists.
7. Re-enable dict8 and open Settings.

## Keychain status

1. With no stored key and no scheme environment override, confirm Settings shows **Missing**.
2. Enter the OpenRouter key locally in the SecureField and click **Save or Replace**. Never paste the key into logs, screenshots, fixtures, or chat.
3. Confirm the field clears and status changes to **Configured in Keychain** without displaying the key.
4. Quit the Xcode-launched copy of dict8.
5. In Xcode, right-click the built `dict8.app` product and choose **Show in Finder**.
6. Copy it to `/Applications`, launch that copy from Finder, and confirm the configured status remains available without a shell environment.
7. Optionally test the development override with a non-secret placeholder in the Xcode scheme environment; confirm Settings reports **Development override active** without displaying the value.

## Launch at Login

1. Launch `/Applications/dict8.app` and enable **Launch at Login** in Settings.
2. Confirm registration shows **On** or **Approval required**.
3. If approval is required, click **Open Login Items Settings**, approve dict8, return to Settings, and reopen it to refresh status.
4. Quit dict8, log out and back in, and confirm the menu bar icon returns without opening Terminal or Xcode.
5. Leave Launch at Login enabled if desired; otherwise disable it from Settings and confirm registration shows **Off**.

## Non-activating HUD

1. Open TextEdit with the insertion point in a blank document.
2. Open dict8 Settings and click **Preview Recording HUD**.
3. Immediately return focus to TextEdit and type while the microphone capsule remains visible near the bottom center of the active display.
4. Confirm the HUD accepts no clicks, does not reactivate dict8, and disappears after approximately two seconds.

## Expected limitations

- The app shell performs no recording, paste, hotkey, or network behavior yet.
- Launch at Login may require explicit approval in System Settings.
- A development build should be copied to `/Applications` before validating Finder launch and login persistence so its path remains stable.
- Phase 1 was initially validated with **Sign to Run Locally**. Phase 2 switches the project to automatic Personal Team development signing so Accessibility approval can remain attached to a stable signed identity across rebuilds.

## Verified result

Phase 1 passed on July 13, 2026:

- `PhaseZeroFoundationTests` and `PhaseOneAppShellTests` passed in Xcode.
- The dockless menu bar app, Settings window, Enable/Disable persistence, and non-activating HUD behaved as specified.
- The OpenRouter API key remained configured after copying the locally signed app to `/Applications` and launching it from Finder.
- Launch at Login registered after user approval and relaunched dict8 following logout and login.
- The installed locally signed application passed strict code-signature verification.
