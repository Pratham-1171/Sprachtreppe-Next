# Android release signing

The CI workflow can produce a repeat-installable release APK only when every future build uses the **same Android signing key**. The CI debug-key fallback is for build checks only; do not distribute those APKs as long-term upgrades.

## 1. Create and back up a release keystore

Run this in PowerShell on a trusted computer with JDK `keytool` available:

```powershell
keytool -genkeypair -v -keystore sprachtreppe-release.jks -alias sprachtreppe -keyalg RSA -keysize 2048 -validity 10000
```

Choose a strong keystore password and key password. Keep the `.jks` file and both passwords in a secure offline backup. **Do not commit the keystore or passwords to GitHub.** If the key is lost, future APKs signed with a replacement key generally will not update this installation.

## 2. Convert the keystore to Base64

In PowerShell, from the directory containing the keystore:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes(".\sprachtreppe-release.jks")) | Set-Clipboard
```

The Base64 value is copied to the clipboard. Paste it directly into the GitHub secret in the next step; don't put it in source code or a committed file.

## 3. Add the four repository Actions secrets

Open **Settings → Secrets and variables → Actions → New repository secret** in this repository, and add:

| Secret name | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The Base64 text copied above |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password |
| `ANDROID_KEY_ALIAS` | `sprachtreppe` |
| `ANDROID_KEY_PASSWORD` | The key password |

All four secrets must be present. The workflow intentionally fails when only some are configured, and it leaves the keystore on the temporary runner only for the duration of the build.

## 4. Verify updates before distributing

1. Trigger the Flutter Android workflow and confirm the signing step completes without the debug-key warning.
2. Install that first persistently signed APK on a test device.
3. Build another APK with the same secrets and confirm Android offers an update without uninstalling the first one.
4. Back up learning data before testing any upgrade path.

The Flutter shell's application ID is `com.example.sprachtreppe_flutter`. It is intentionally different from the older Capacitor app ID, so this Flutter APK is not a replacement for that app. APKs previously signed with a temporary debug key may also require a clean test installation before the persistent-key update path can be verified.
