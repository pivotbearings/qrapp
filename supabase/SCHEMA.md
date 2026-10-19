# Supabase Backend & Security Architecture — Pivot Bearings India

## 1. Executive Summary
The backend for **Pivot Bearings India** is architected on Supabase PostgreSQL, incorporating Row-Level Security (RLS), atomic stored procedures (`SECURITY DEFINER`), private Storage, and strict server-side state machines.

---

## 2. Security Foundation & Authentication

### Two-Role Authorization Matrix
The system enforces strictly two user roles across the backend:

| Role | Definition & Scope | Backend Check |
|---|---|---|
| **`ADMIN`** | Plant supervisors, quality assurance heads, and supply chain managers. Full read/write access to production batches, QR generation, warranty plan configurations, company settings, and system audit logs. | `public.is_admin(auth.uid()) = true` |
| **`USER`** | Industrial operators, field engineers, and enterprise customers. Restricted to inspecting assigned bearings, executing verified IN/OUT transitions via RPCs, and reading own profile. | `auth.role() = 'authenticated'` and `user_id = auth.uid()` |

### Self-Elevation Prevention
- All new user registrations in `auth.users` trigger `public.handle_new_auth_user()`, which automatically sets the role to `'USER'` in `public.user_roles`.
- RLS policies on `public.user_roles` prevent non-admin users from inserting, updating, or deleting any role record.
- Ordinary users cannot elevate themselves to `ADMIN` either via API or client code.

---

## 3. Normalized Relational Database Schema

```
                                  +-------------------+
                                  | company_settings  |
                                  +-------------------+
                                            |
+-------------------+             +-------------------+             +-------------------+
|      profiles     | <---------> |    user_roles     |             |   warranty_plans  |
+-------------------+             +-------------------+             +-------------------+
          |                                                                   |
          | (assigned_by / created_by)                                        | (default / assigned)
          v                                                                   v
+-------------------+                                               +-------------------+
|    qr_batches     | --------------------------------------------> |     qr_codes      |
+-------------------+                                               +-------------------+
                                                                              |
                          +---------------------------------------------------+-----------------------------------+
                          |                                                   |                                   |
                          v                                                   v                                   v
+-----------------------------------+             +-----------------------------------+             +-------------------+
|    bearing_installation_cycles    |             |     bearing_lifecycle_events      |             |   scan_records    |
+-----------------------------------+             +-----------------------------------+             +-------------------+
                          |                                                   |
                          +-------------------------+-------------------------+
                                                    |
                                                    v
                                  +-----------------------------------+
                                  |        verification_images        |
                                  +-----------------------------------+
```

### Table Dictionary

#### 1. `profiles`
- `id` (`uuid`, PK): Foreign key to `auth.users(id)` with cascading deletion.
- `full_name` (`text`, NOT NULL)
- `phone` (`text`, NULLABLE)
- `company_name` (`text`, NULLABLE)
- `facility_code` (`text`, NULLABLE)
- `is_active` (`boolean`, DEFAULT `true`)
- `created_at`, `updated_at` (`timestamptz`)

#### 2. `user_roles`
- `id` (`uuid`, PK): Default `gen_random_uuid()`
- `user_id` (`uuid`, FK to `profiles.id`, NOT NULL)
- `role` (`text`, CHECK `role in ('ADMIN', 'USER')`, NOT NULL)
- `assigned_at` (`timestamptz`)
- `assigned_by` (`uuid`, FK to `profiles.id`)
- Constraint: `UNIQUE(user_id, role)`

#### 3. `company_settings`
- `id` (`uuid`, PK)
- `company_name` (`text`, DEFAULT `'Pivot Bearings India'`)
- `gst_number` (`text`, NOT NULL) — e.g., `'27AABCP1234F1ZQ'`
- `address` (`text`, NOT NULL)
- `contact_email` (`text`, NOT NULL)
- `contact_phone` (`text`, NOT NULL)
- `website` (`text`, NOT NULL)
- `logo_storage_path` (`text`, NULLABLE)

#### 4. `app_settings`
- `id` (`uuid`, PK)
- `setting_key` (`text`, UNIQUE, NOT NULL)
- `setting_value` (`jsonb`, NOT NULL)
- `is_public` (`boolean`, DEFAULT `false`)

#### 5. `warranty_plans`
- `id` (`uuid`, PK)
- `plan_code` (`text`, UNIQUE, NOT NULL) — e.g., `'WP-3M'`, `'WP-6M'`, `'WP-12M'`, `'WP-24M'`
- `title` (`text`, NOT NULL)
- `duration_months` (`integer`, CHECK `duration_months > 0`, NOT NULL)
- `is_active` (`boolean`, DEFAULT `true`)

#### 6. `qr_batches`
- `id` (`uuid`, PK)
- `batch_code` (`text`, UNIQUE, NOT NULL) — e.g., `'BATCH-2026-OCT-A'`
- `plant_location` (`text`, NOT NULL)
- `lot_date` (`date`, NOT NULL)
- `total_quantity` (`integer`, CHECK `total_quantity > 0`, NOT NULL)
- `default_warranty_plan_id` (`uuid`, FK to `warranty_plans.id`)
- `created_by` (`uuid`, FK to `profiles.id`)

#### 7. `qr_codes`
- `id` (`uuid`, PK)
- `bearing_id` (`text`, UNIQUE, CHECK regex `'^PB-[0-9]{4}-[A-Z0-9]{2}$'`)
- `batch_id` (`uuid`, FK to `qr_batches.id`, NOT NULL)
- `model_number` (`text`, NOT NULL, DEFAULT `'PBI-6204-ZZ'`)
- `payload_value` (`text`, UNIQUE, NOT NULL) — The raw URI string encoded in the QR.
- `payload_hash` (`text`, NOT NULL) — Cryptographic SHA-256 telemetry hash.
- `assigned_warranty_plan_id` (`uuid`, FK to `warranty_plans.id`, NOT NULL)
- `assigned_customer_id` (`uuid`, FK to `profiles.id`, NULLABLE)
- `current_lifecycle_state` (`text`, CHECK `in ('NOT_ACTIVATED', 'CURRENTLY_IN', 'CURRENTLY_OUT')`)
- `first_in_timestamp` (`timestamptz`, NULLABLE) — Authoritative server timestamp for warranty start.
- `warranty_expiry_timestamp` (`timestamptz`, NULLABLE) — Anchored countdown end date.
- `is_flagged` (`boolean`, DEFAULT `false`)

> [!IMPORTANT]
> **NO QR CODE IMAGES ARE STORED**:
> No image files (PNG/JPEG/SVG) of QR codes are saved in Supabase. Only raw `payload_value` strings and hashes are persisted. The Flutter application generates all QR matrix representations in real time using `qr_flutter` on the client.

#### 8. `bearing_installation_cycles`
- `id` (`uuid`, PK)
- `qr_code_id` (`uuid`, FK to `qr_codes.id`, NOT NULL)
- `cycle_number` (`integer`, NOT NULL)
- `in_timestamp` (`timestamptz`, NOT NULL)
- `in_confirmed_by` (`uuid`, FK to `profiles.id`, NOT NULL)
- `in_verification_image_id` (`uuid`, FK to `verification_images.id`)
- `out_timestamp` (`timestamptz`, NULLABLE)
- `out_confirmed_by` (`uuid`, FK to `profiles.id`)
- `operating_duration_interval` (`interval`)
- `operating_duration_seconds` (`bigint`)
- `is_cycle_closed` (`boolean`, DEFAULT `false`)

#### 9. `bearing_lifecycle_events`
- `id` (`uuid`, PK)
- `qr_code_id` (`uuid`, FK to `qr_codes.id`, NOT NULL)
- `event_type` (`text`, CHECK `in ('INITIAL_GENERATION', 'CUSTOMER_ASSIGNMENT', 'MARKED_IN', 'MARKED_OUT', 'INSPECTION', 'FLAGGED', 'WARRANTY_EXTENDED')`)
- `recorded_by` (`uuid`, FK to `profiles.id`, NOT NULL)
- `server_timestamp` (`timestamptz`, NOT NULL)
- `verification_image_id` (`uuid`, FK to `verification_images.id`)
- `metadata` (`jsonb`, DEFAULT `'{}'::jsonb`)

#### 10. `scan_records`
- `id` (`uuid`, PK)
- `qr_code_id` (`uuid`, FK to `qr_codes.id`)
- `scanned_payload` (`text`, NOT NULL)
- `scanned_by` (`uuid`, FK to `profiles.id`, NULLABLE)
- `is_valid` (`boolean`, NOT NULL)
- `scan_timestamp` (`timestamptz`, DEFAULT `now()`)

#### 11. `verification_images`
- `id` (`uuid`, PK)
- `qr_code_id` (`uuid`, FK to `qr_codes.id`, NOT NULL)
- `uploaded_by` (`uuid`, FK to `profiles.id`, NOT NULL)
- `storage_path` (`text`, UNIQUE, NOT NULL) — Path inside private bucket `verification-images`.
- `sha256_hash` (`text`, NOT NULL) — Cryptographic digest of compressed proof photo.
- `file_size_bytes` (`integer`, NOT NULL)
- `image_type` (`text`, CHECK `in ('IN_INSTALLATION', 'OUT_REMOVAL', 'CONDITION_INSPECTION')`)

#### 12. `admin_audit_logs`
- `id` (`uuid`, PK)
- `admin_id` (`uuid`, FK to `profiles.id`, NOT NULL)
- `action` (`text`, NOT NULL)
- `target_entity` (`text`, NOT NULL)
- `target_id` (`uuid`)
- `old_values` (`jsonb`), `new_values` (`jsonb`)
- `created_at` (`timestamptz`, DEFAULT `now()`)

---

## 4. Row-Level Security (RLS) Policy Matrix

| Table | Anonymous / Public | Authenticated USER | Authenticated ADMIN |
|---|---|---|---|
| `profiles` | None | SELECT & UPDATE own profile (`id = auth.uid()`) | SELECT & UPDATE all profiles |
| `user_roles` | None | SELECT own role | SELECT, INSERT, UPDATE, DELETE all roles |
| `company_settings` | SELECT | SELECT | SELECT, INSERT, UPDATE |
| `app_settings` | SELECT (`is_public = true`) | SELECT (non-sensitive) | FULL ACCESS |
| `warranty_plans` | SELECT (`is_active = true`) | SELECT | FULL ACCESS |
| `qr_batches` | None | None | FULL ACCESS |
| `qr_codes` | SELECT (Public QR verification) | SELECT (Assigned bearings) | FULL ACCESS (Direct INSERT/UPDATE) |
| `bearing_installation_cycles` | None | SELECT (Assigned / confirmed by self) | FULL ACCESS |
| `bearing_lifecycle_events` | None | SELECT (Assigned bearings) | FULL ACCESS |
| `scan_records` | INSERT | INSERT, SELECT own scans | INSERT, SELECT all scans |
| `verification_images` | None | INSERT own, SELECT assigned | FULL ACCESS |
| `admin_audit_logs` | None | None | SELECT all audit logs |

---

## 5. Tamper-Proof State Machine (Server-Side RPCs)

Ordinary users are strictly blocked by RLS from executing direct `UPDATE` queries on `qr_codes` or `bearing_installation_cycles`. All state transitions are governed by security-definer stored procedures:

### `confirm_bearing_in(p_bearing_id, p_verification_image_id, p_notes)`
1. Verifies authentication and acquires a row lock on `qr_codes`.
2. Validates that the bearing is **not flagged** and **not currently installed** (`CURRENTLY_IN`).
3. **Warranty Anchoring Rule**:
   - If `first_in_timestamp` is `NULL`, sets `first_in_timestamp = now()` and calculates `warranty_expiry_timestamp = now() + duration`.
   - If bearing was previously marked `CURRENTLY_OUT`, re-installation updates status to `CURRENTLY_IN` while preserving the original `first_in_timestamp` and expiration anchor.
4. Increments and inserts a new row in `bearing_installation_cycles`.
5. Inserts an immutable log in `bearing_lifecycle_events`.

### `confirm_bearing_out(p_bearing_id, p_verification_image_id, p_notes)`
1. Verifies authentication and acquires a row lock on `qr_codes`.
2. Validates that current state is `CURRENTLY_IN`. Attempting to mark OUT an uninstalled bearing is rejected with an exception.
3. Calculates exact operational duration: `now() - in_timestamp`.
4. Closes the active installation cycle with `out_timestamp`, `operating_duration_interval`, and `operating_duration_seconds`.
5. Sets state to `CURRENTLY_OUT`.
6. Inserts an immutable log in `bearing_lifecycle_events`.

### `generate_qr_batch(p_batch_code, p_plant_location, p_quantity, p_model_number, p_default_warranty_plan_id)`
1. Strictly restricted to callers with `public.is_admin(auth.uid()) = true`.
2. Validates quantity between `1` and `5000`.
3. Creates or links the `qr_batches` manifest record.
4. Generates unique, unpredictable cryptographic identifiers matching `^PB-[0-9]{4}-[A-Z0-9]{2}$`.
5. Loops with collision avoidance retry logic until the exact quantity is safely persisted.
6. Encodes standard verification URL payload and SHA-256 hash.
7. Sets initial lifecycle state to `NOT_ACTIVATED`. Generation and printing strictly do not start warranty (`first_in_timestamp = NULL`, `warranty_expiry_timestamp = NULL`).
8. Logs batch operation into `admin_audit_logs` and `bearing_lifecycle_events`.

### `assign_warranties_bulk(p_assignments)`
1. Restricted to callers with `ADMIN` role.
2. Accepts a heterogeneous JSON array of assignments: `[{"bearing_id": "...", "warranty_plan_id": "..."}, ...]`.
3. Supports mixed assignment across batches (e.g. 5 bearings assigned to 3 months, 3 bearings to 6 months).
4. If a bearing has not yet been activated, updates the plan reference without setting an expiration date.
5. If already activated, recalculates expiration based on the immutable `first_in_timestamp` anchor.
6. Emits `WARRANTY_EXTENDED` event in `bearing_lifecycle_events`.

### `toggle_qr_block(p_bearing_id, p_is_flagged, p_flag_reason)`
1. Restricted to Admins.
2. Sets `is_flagged` and records inspection or tamper audit reason.
3. Emits `FLAGGED` event in `bearing_lifecycle_events`.

### `verify_bearing_qr(p_scanned_payload, p_ip_address, p_user_agent, p_device_info)`
1. Publicly callable verification RPC for customers, field engineers, and optical scanners.
2. Extracts and sanitizes bearing serial from URL or raw string (`PB-[0-9]{4}-[A-Z0-9]{2}`).
3. Records all scan attempts into `scan_records` telemetry log.
4. Checks cryptographic registry and returns clear states:
   - `VALID_NOT_ACTIVATED`: Bearing registered and ready for installation.
   - `VALID_WARRANTY_ACTIVE`: Currently in operating service or stored, with unexpired warranty.
   - `WARRANTY_EXPIRED`: Operational horizon has elapsed.
   - `QR_BLOCKED`: Flagged by Quality Directorate; transitions locked.
   - `QR_UNKNOWN_OR_INVALID`: Identifier not recognized in authoritative registry.
5. Invariant: Scanning strictly does **not** mutate lifecycle state or activate warranty.

---

## 6. Private Storage Bucket Architecture & Verification Image Pipeline

- **Bucket**: `verification-images` (Private: `public = false`).
- **Path convention**: `verification-images/{qr_id}/{event_id}.webp`.
- **Image Processing**:
  - EXIF orientation correction via `img.bakeOrientation`.
  - Max dimension capped at 1,800px (1,600–2,000px industrial range).
  - WebP encoding with adaptive quality 78 (70–82 range) and JPEG fallback.
  - Cryptographic SHA-256 tamper verification hash stored in `verification_images.sha256_hash`.
- **Upload policy**: Authenticated users can upload verification images into `verification-images` private storage with automated exponential backoff retry.
- **Read policy**: Private bucket requires authorized signed URLs (`createSignedUrl(storagePath, 3600)`) with 1-hour expiry for admin inspection.
- **Delete policy**: Ordinary users cannot delete verification evidence. Only Admins can delete objects.
- **Camera Coordination**: Shutterless automated capture executes after confirmed IN/OUT with an explicit disclosure banner. `MobileScannerController` and `CameraController` sessions are strictly isolated and never run concurrently. Platform camera privacy indicators and sounds remain uninhibited.

---

## 7. Secret Management & Client-Side Isolation
- **Client App Key**: Only `SUPABASE_URL` and `SUPABASE_ANON_KEY` are embedded in `.env` / client configurations.
- **Service-Role Key**: Never placed in client code, Flutter assets, Git repositories, or platform bundles. Administrative tasks and initial schema bootstrapping run strictly via server-side migrations and CLI operations.
