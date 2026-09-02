# Installing dict8 from source

This is the supported installation path for the current source-only release. It builds a locally signed copy on the Mac where dict8 will run. It does not produce a notarized binary suitable for general redistribution.

## 1. Confirm the Mac can run dict8

You need:

- An Apple silicon Mac running macOS 26 or newer
- Xcode with the macOS 26 SDK
- Git
- An OpenRouter account and API key
- Authority to grant Microphone and Accessibility access

No Apple Account or signing team is required: the checked-in project is configured for ad-hoc local signing.

On a company-managed Mac, confirm that policy permits locally built applications, microphone recording, Accessibility control, global keyboard monitoring, Keychain access, and Launch at Login. Mobile-device-management policy can prevent one or more of these capabilities even when the build succeeds.

## 2. Configure OpenRouter privacy

Audio and transcript text are sent through OpenRouter to model providers. Before using dict8:

1. Sign in to OpenRouter.
2. Open **Settings → Privacy**.
3. Enable Zero Data Retention for the **OpenAI** model group.
4. Enable Zero Data Retention for the **Google** model group.
5. Leave private input/output logging disabled unless you intentionally want OpenRouter to retain request content for observability.
6. Create an API key for this installation. Apply an account or key spending limit if desired.

The transcription endpoint relies on the account-level OpenAI and Google controls. Cleanup requests additionally send per-request ZDR. Review OpenRouter's [ZDR documentation](https://openrouter.ai/docs/guides/features/zdr) and [data-collection documentation](https://openrouter.ai/docs/guides/privacy/data-collection) for the current policy details.

## 3. Clone and open the project

In Terminal:

```zsh
git clone https://github.com/xehl/dict8.git
cd dict8
open dict8/dict8.xcodeproj
```

In Xcode:

1. Open **Xcode → Settings → Accounts** (optional; only needed if you intentionally switch to team signing).
2. Select the blue **dict8** project in the Project navigator.
3. Select the **dict8** application target, then **Signing & Capabilities**, and confirm signing shows **Sign to Run Locally** with **Automatically manage signing** unchecked. This matches the checked-in project configuration.

The checked-in project uses manual ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_STYLE = Manual`). Ad-hoc signing produces a deterministic code-directory hash for a given build, so macOS treats rebuilds as the same application and permission grants survive recompiles. Keep the bundle identifier `com.xehl.dict8` stable.

Keep **App Sandbox** disabled. dict8 requires an active Accessibility event tap and focused-element inspection; the current implementation did not receive the required authorization while sandboxed. The application target must retain its Audio Input entitlement. Hardened Runtime is disabled in the local configuration because ad-hoc signing cannot use it; this is acceptable for a locally built personal tool and is not suitable for notarized distribution.

## 4. Build and test

1. Select the `dict8` scheme.
2. Select **My Mac** as the destination.
3. Press `Command + U` and confirm all test classes are green.
4. Press `Command + B` and confirm the application builds without errors.

The automated suite uses synthetic data and test doubles. It does not make live OpenRouter requests.

## 5. Create the installed app

The repeatable path is the packaging script, which builds Release and installs in one step:

```zsh
./Scripts/build-release.sh
```

The manual Archive flow is equivalent if you prefer Xcode:

1. Quit every running copy of dict8.
2. In Xcode, select the `dict8` scheme and **My Mac**.
3. Choose **Product → Archive**.
4. When Organizer opens, select the new archive and choose **Show in Finder**.
5. In Finder, Control-click the `.xcarchive` and choose **Show Package Contents**.
6. Open `Products/Applications`.
7. Copy `dict8.app` into `/Applications`, replacing an older copy only after that copy has quit.
8. Launch `/Applications/dict8.app` from Finder.

Do not launch the archived app in place. Moving or replacing the application after permissions are granted can make macOS display a duplicate or stale Accessibility entry.

## 6. Complete first-run setup

Open dict8 from the menu bar, choose **Settings**, and complete these steps:

1. Under **API key**, enter the OpenRouter key and choose **Save or Replace**. Confirm the field clears and status becomes **Configured in Keychain**.
2. Choose **Request Microphone**. If necessary, open **System Settings → Privacy & Security → Microphone** and enable dict8.
3. Choose **Request Accessibility**. If dict8 does not appear automatically, open **System Settings → Privacy & Security → Accessibility**, add `/Applications/dict8.app`, and enable it.
4. Quit and relaunch dict8 after changing Accessibility access.
5. Confirm Settings reports Microphone **Granted**, Accessibility **Granted**, and Global shortcuts **Running**.
6. Enable **Launch at Login** if desired. Approve dict8 under Login Items when macOS requests confirmation.

The API key and permission grants do not migrate from another Mac. Configure them independently on every installation.

## 7. Verify the installation

1. Open TextEdit and create a blank document.
2. Hold `Control + Option`, dictate a harmless sentence, and release.
3. Confirm the microphone capsule becomes a processing spinner and exactly one cleaned result appears in TextEdit.
4. Move to another blank line and press `Command + Control + V`. Confirm the last result pastes exactly once.
5. Start another dictation, switch to a different application before releasing, and confirm dict8 copies and notifies instead of pasting into the new application.
6. Try the shortcut in a known password field containing no real credential. Confirm dict8 refuses the operation.
7. Quit dict8 and launch it again from `/Applications`. Confirm the API-key status and permissions remain available.

## 8. Updating an installation

1. Pull the desired commit and review the changes.
2. Run the complete unit-test suite.
3. Run `./Scripts/build-release.sh` (or create a new Release archive).
4. Quit dict8.
5. Replace `/Applications/dict8.app` with the newly archived app (the script does this).
6. Launch the installed copy and confirm Accessibility, Microphone, Keychain, dictation, and Launch at Login still work.

Preserving the bundle identifier and signing identity gives macOS the best chance of retaining permission and Keychain continuity. If permissions no longer attach to the replacement, remove stale dict8 entries from the relevant Privacy & Security pane, add the installed app again, and relaunch it.

## Troubleshooting

### Global shortcuts is not running

Confirm Accessibility is granted to the copy located in `/Applications`, then quit and relaunch dict8. Remove stale entries that point to an Xcode build or an older copy.

### Two recordings or cues occur

Quit either the Xcode-launched copy or the installed copy. Only one dict8 process should run at a time.

### The API key is missing on the new Mac

This is expected. Keychain contents are intentionally not stored in Git or bundled with the application. Enter the key in Settings on the new installation.

### Launch at Login is unavailable or requires approval

Install dict8 under `/Applications`, launch that copy, and check **System Settings → General → Login Items & Extensions**. A managed Mac may prohibit registration.

### Xcode repeatedly requests Keychain access while signing

Open the signing certificate's private key in Keychain Access and review its Access Control settings. Grant Xcode's signing tools access only if the certificate and requesting executable are expected. Do not export or commit the private key.

### The work Mac blocks the app

Do not bypass company security controls. Ask the administrator whether locally signed apps with Microphone and Accessibility access are permitted. A future notarized Developer ID build would improve normal Gatekeeper distribution, but it would not override organizational policy.
