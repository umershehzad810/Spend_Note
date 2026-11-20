# Release signing

Release builds use a dedicated RSA signing key, not the Android debug key.

Private local files (excluded from version control):
- android/signing/spendnote-release.jks
- android/key.properties (includes generated signing passwords)

Keep a private backup of BOTH files. Future APK updates must use the same signing key. Do not commit or share these files. No signing passwords are printed in build output.

Build an installable release APK:

```powershell
C:\Users\pc\Tools\flutter\bin\flutter.bat build apk --release
```

Build a Play Store bundle if needed:

```powershell
C:\Users\pc\Tools\flutter\bin\flutter.bat build appbundle --release
```

The Google Drive feature still requires the owner's Google OAuth setup described in README.md. Register this release certificate's SHA-1 as well as the debug certificate when configuring Google sign-in.

A release-signed APK cannot update an installed debug-signed APK with the same package name. On a device with the earlier debug build, preserve any financial data before uninstalling that build; uninstalling erases its local data. Subsequent release APKs signed with this key can update this release normally (increase version/build number for distribution).

A release build is optimized and signed, but does not replace physical-device verification of Google OAuth or biometric hardware.
