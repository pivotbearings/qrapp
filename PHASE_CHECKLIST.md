# Phase Checklist — Pivot Bearings India

## Phase 1: Foundation, Architecture & Platform Toolchain [COMPLETED]
- [x] Create clean project `pivot_bearings_app` without modifying legacy projects.
- [x] Initialize Android, iOS, and Web platform targets.
- [x] Integrate custom fonts: `neue-haas-light.otf` (Regular 400) and `neue-haas-roman.otf` (Medium 500).
- [x] Enforce strict binary design tokens: `#ECECEC` (Background) and `#0065C1` (Primary).
- [x] Implement zero-elevation theme (`elevation: 0.0`) and curved-square geometry (12px–16px).
- [x] Setup dependency inventory with verified versions (`mobile_scanner`, `qr_flutter`, `camera`, `image`, `supabase_flutter`, `intl`, `flutter_dotenv`).
- [x] Build multi-language localization framework (English, Hindi, Gujarati).
- [x] Build feature-based folder hierarchy with decoupled domain services.
- [x] Implement independent `WarrantyCalculator` domain service with 100% unit test coverage.
- [x] Implement independent `QrGenerationService` & `QrPayload` with 100% unit test coverage.
- [x] Implement `ImageCompressionService` with pure-Dart JPEG compression & SHA-256 telemetry hashing.
- [x] Map all 12 Stitch HTML/CSS/PNG designs to native Flutter screens.
- [x] Execute `flutter analyze` with 0 errors and 0 warnings.
- [x] Execute `flutter test` with 11/11 passing tests.
- [x] Execute `flutter build web` successfully (`build\web`).
- [x] Deliver `.env.example`, `ARCHITECTURE.md`, `DEPENDENCIES.md`, `SCREEN_MAP.md`, `ROUTE_MAP.md`, and `PHASE_CHECKLIST.md`.

---

## Phase 2: Hardware QR Scanner & Optical Evidence Engine
- [ ] Implement camera stream lifecycle management and torch control on physical devices.
- [ ] Connect `MobileScanner` barcode bounding box targeting to UI crosshairs.
- [ ] Add vibration/haptic feedback on successful optical barcode lock.
- [ ] Implement live reticle capture via CameraX/AVFoundation controller.
- [ ] Connect image compression isolate to prevent frame drops during SHA-256 hashing.
- [ ] Add offline SQLite queue for scans performed in remote industrial areas without cellular coverage.

---

## Phase 3: Lifecycle State Machine & Authoritative Timestamp Pipeline
- [ ] Verify first IN event creates irreversible warranty anchor.
- [ ] Prevent OUT transitions if bearing was never marked IN.
- [ ] Implement automatic cumulative operating duration calculation upon OUT event.
- [ ] Support re-installation (subsequent IN event) without resetting the initial expiration anchor.
- [ ] Build automated timestamp clock synchronization using NTP fallback to prevent device clock tampering.

---

## Phase 4: Supabase Production Schema & Storage Buckets
- [ ] Create `bearings`, `verification_events`, and `batches` tables in PostgreSQL.
- [ ] Configure Row Level Security (RLS) policies for plant operators vs. enterprise admins.
- [ ] Create Supabase Storage bucket `optical-proofs` with encrypted upload URLs.
- [ ] Configure Realtime subscriptions for live telemetry updates in the web dashboard.
- [ ] Add edge functions for tamper-detection validation on uploaded image proof hashes.

---

## Phase 5: High-Density Admin Panel & Bulk Print Generation
- [ ] Finalize responsive multi-pane layout for desktop (12-column grid) and tablet.
- [ ] Implement batch QR code PDF export using vector sheets and industrial thermal label formats (e.g., 50x50mm, 25x25mm).
- [ ] Add CSV/Excel telemetry log export.
- [ ] Build bulk warranty assignment overwrite transactions.
- [ ] Add advanced search with multi-filter queries across batches, facilities, and customer accounts.

---

## Phase 6: Multi-Platform Production Release & Field Pilot
- [ ] Configure Android signing key and release build profile.
- [ ] Configure iOS provisioning profiles and TestFlight deployment pipeline.
- [ ] Deploy Web admin panel to production hosting.
- [ ] Perform field testing in plant environments with varied lighting conditions, oil residues, and laser reflections.
- [ ] Complete enterprise accessibility audit and operator training documentation.
