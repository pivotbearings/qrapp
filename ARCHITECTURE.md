# Architecture Specification — Pivot Bearings India

## 1. System Overview
The Pivot Bearings India application is an enterprise-grade precision QR code verification, optical telemetry, and lifecycle management system. It provides both native mobile operational workflows (for industrial plant operators, inspectors, and logistics personnel) and a responsive desktop web panel (for enterprise inventory management and batch warranty allocation).

---

## 2. Strict Design System Enforcement

### Color Paradigm
The entire user interface strictly uses a binary 2-color palette:
- **Surface / Background**: `#ECECEC`
- **Primary / Foreground / Borders / Icons**: `#001F59`

**Rules Enforced in Code:**
- Zero pure white (`#FFFFFF`), pure black (`#000000`), or gray shades.
- Zero gradients, colored overlay filters, or drop shadows (`elevation: 0.0` globally).
- No opacity/alpha reductions (`rgba` prohibited).
- Interaction states utilize inverse color fills:
  - Primary button: Solid `#001F59` fill with `#ECECEC` label.
  - Secondary button: `#ECECEC` fill with 1.5px `#001F59` border and label.
  - Status indicators: Monoline outline tag with explicit text (e.g. `[STATUS: MARKED IN]`).

### Typography
- **Font Family**: `NeueHaasGrotesk`
- **Weights**:
  - Regular (`400`): Neue Haas Light (`neue-haas-light.otf`) — body copy, forms, metadata, telemetry grids.
  - Medium (`500`): Neue Haas Roman (`neue-haas-roman.otf`) — page headings, card titles, table headers, buttons.
- **Architectural Discipline**: Headings stand alone without decorative eyebrow tags or subheaders.

### Form Geometry
- Curved-square profile: standard corner radii of `12px` to `16px`.
- Micro components (tags, checkboxes): `4px`.
- Fully circular components and pill geometries are disallowed for container boundaries.

---

## 3. Layered Feature-Based Architecture

```
lib/
├── core/
│   ├── config/             # Environment configuration (.env loader, timeouts)
│   ├── constants/          # AppColors (#ECECEC & #001F59), AppDimensions, AppTypography
│   ├── errors/             # Typed exception hierarchy (InvalidQr, Network, Lifecycle)
│   ├── localization/       # Multi-language system (English, Hindi, Gujarati)
│   ├── router/             # AppRoutes and AppRouter dynamic route generator
│   ├── services/           # SupabaseService, storage, and telemetry abstractions
│   ├── theme/              # AppTheme with 0.0 elevation and strict 2-color tokens
│   └── widgets/            # IndustrialButton, IndustrialCard, IndustrialAppBar, etc.
│
├── features/
│   ├── customer_home/      # Customer mobile home and recent telemetry list
│   ├── qr_scanner/         # Optical QR viewfinder with mobile_scanner & manual fallback
│   ├── bearing_verification/ # Verification cards, IN/OUT confirmation & results
│   │   ├── data/           # BearingModel, VerificationEvent, BearingRepository
│   │   └── domain/         # WarrantyCalculator (pure testable business logic)
│   ├── optical_capture/    # Camera proof capture with reticle & SHA-256 compression
│   ├── qr_generation/      # QrPayload encoding, QrImageView preview, batch generation
│   ├── warranty_assignment/# Bulk warranty duration & segment allocation
│   ├── qr_inventory/       # High-density inventory data grid with telemetry search
│   └── admin_dashboard/    # Responsive admin operations & telemetry statistics
│
└── main.dart               # Bootstrap & service orchestration
```

---

## 4. Testability & Decoupled Services
- **Warranty Calculations**: `WarrantyCalculator` handles 3, 6, 12, 24-month duration horizons, leap years, remaining balances, and operational cycle calculations with zero widget dependencies.
- **QR Scanning**: `QrScannerService` isolates barcode payload parsing and format validation.
- **Image Compression**: `ImageCompressionService` uses the `image` library to resize and compress captures to JPEG 80 quality and generate SHA-256 hashes independently.
- **Backend Communication**: `BearingRepository` abstracts Supabase communication with in-memory deterministic fallback when offline or in test environments.
