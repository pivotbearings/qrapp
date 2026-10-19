# Dependency Inventory — Pivot Bearings India

## 1. Core Architecture Packages

| Package | Version | Purpose | Compatibility Status |
|---|---|---|---|
| `mobile_scanner` | `^7.4.2` | Native hardware camera QR code scanning and payload extraction | Compatible with Flutter 3.44 / Android SDK 34+ / iOS 14+ |
| `qr_flutter` | `^4.1.0` | QR matrix rendering and image export for bulk generation | Pure Dart rendering; Web, Mobile, and Desktop compatible |
| `camera` | `^0.12.1` | Optical capture reticle for bearing removal proof | Android CameraX & iOS AVFoundation supported |
| `image` | `^4.10.1` | Pure-Dart deterministic JPEG compression & resizing | Multi-platform, zero native C-library dependencies |
| `crypto` | `^3.0.7` | Cryptographic SHA-256 telemetry hashing | Pure Dart |
| `supabase_flutter` | `^2.18.2` | Supabase backend integration (Auth, PostgREST, Realtime, Storage) | Web & Mobile compatible, with offline mock fallback |
| `flutter_localizations`| SDK | Material & Cupertino localization delegates | Built into Flutter SDK |
| `intl` | `0.20.2` | Translation formatting, date/time formatting | Pinned to Flutter 3.44 SDK requirements |
| `flutter_dotenv` | `^6.0.1` | Runtime environment configuration loader | Web & Mobile safe fallback |
| `cupertino_icons` | `^1.0.8` | Standard iOS icon support | Asset-based |

## 2. Dev & Test Dependencies

| Package | Version | Purpose |
|---|---|---|
| `flutter_test` | SDK | Unit, widget, and integration testing framework |
| `flutter_lints` | `^6.0.0` | Code quality and static analysis rules |

## 3. Disallowed Libraries (Explicit Non-Inclusions)
- **1D Barcode scanning/generation libraries**: Excluded.
- **3D Barcode libraries**: Excluded.
- **Styling frameworks (Tailwind/Bootstrap)**: Excluded in favor of strict vanilla Flutter `ThemeData`.
- **Third-party shadow or gradient packages**: Excluded per strict binary aesthetic rules.
