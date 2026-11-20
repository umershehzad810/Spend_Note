# Shared source snapshot

This folder is a clean Android Flutter repository for SpendNote 1.2.0. The sibling APK is signed by the original owner. Private release signing keys and android/key.properties are intentionally absent.

Run flutter pub get, flutter analyze, flutter test and flutter run with Flutter and the Android toolchain installed. If Gradle wrappers need regeneration for your environment, use flutter create --platforms=android . after saving any local changes.

Release signing: copy android/key.properties.example to android/key.properties and supply your own keystore and passwords. Google sign-in for source builds requires registering your own debug/release SHA-1 alongside the package name. The Web client ID is public configuration in lib/security.dart; no client secret is bundled. See ../START-HERE.txt and README.md.

The shared Gradle configuration allows debug builds without the private release key, while refusing a requested release build without signing configuration.
