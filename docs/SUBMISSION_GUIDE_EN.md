# App Store Submission Guide (EN)

Practical companion to `APP_STORE_CHECKLIST.md`. Covers the App Review notes
(English) and a concrete screenshot capture plan. All steps that build, sign, or
archive require a Mac with Xcode 26.

---

## 1. App Review notes (paste into App Store Connect → App Review Information)

```
Tanamiru (タナミル) is an offline-first QR inventory manager for iPhone. There is no
account, login, or developer server: all data lives in the user's own iCloud
(CloudKit private database, plus a shared database when a project is shared).

No demo account is required. To populate the app in one tap:
1. Open the "Projects" tab → top-right "…" menu → "Generate sample".
   This creates a fully populated sample project (locations, folders,
   quantity / serial / lot products, QR labels, an overdue loan, and lots
   with near/expired dates).
2. Open a product to create and export a QR label (PNG / PDF / EPS).
3. The "Scan" tab uses the camera to read QR codes. If camera access is
   denied, every other feature still works (browse, edit, export, loans, lots).
4. Loans: on a serial-tracked product, tap "Check out" to record a borrower and
   a due date. Overdue loans are surfaced in Scan → top-right "On loan", and the
   app may schedule a LOCAL notification at the due date (permission optional;
   the app is fully usable if notifications are declined).
5. Lots: on a lot-tracked product, each lot has its own quantity, optional
   expiry date, and QR label; near-expiry / expired lots are badged.
6. iCloud sharing: Project detail → "Share" lets you invite another Apple ID
   with read-only or read-write access (requires a real device signed into
   iCloud).

Privacy: QR codes contain only a short opaque ID (prefix "IQ", 18 chars) — never
product names, quantities, prices, person names, or CloudKit record IDs. The
borrower name on a loan is free text entered by the user and stored only in the
user's iCloud; it is never sent to the developer. All notifications are local.
No third-party analytics/ads/tracking SDKs are used.
```

> Encryption: `ITSAppUsesNonExemptEncryption = false` is already set, so the
> export-compliance question is auto-answered.

---

## 2. Screenshot capture plan

### Required sizes (verify current rules in App Store Connect)
- **6.9" / 6.7"** (iPhone 16 Pro Max / 15 Pro Max) — required.
- **6.5"** (iPhone 11 Pro Max / XS Max) — required if 6.9"/6.7" not provided for
  all; safest to provide.
- **5.5"** (iPhone 8 Plus) — optional/legacy; include only if targeting it.
- iPad sizes only if you ship an iPad build (the app supports iPad orientations
  but is designed for iPhone).

You need 3–10 screenshots per size. Provide both **Japanese** and **English**
sets if you localize the listing (the app itself is now ja + en).

### Get a clean, deterministic device state
1. Use a fresh Simulator (Erase All Content & Settings) per size.
2. Launch the app, complete or skip onboarding.
3. Projects tab → "…" → "Generate sample" (sample data now includes an overdue
   loan and near/expired lots, so the dashboard and loan/lot screens look real).
4. Optionally clean the status bar:
   ```sh
   xcrun simctl status_bar booted override \
     --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
   ```
5. For the language toggle, set the Simulator (Settings → General → Language) or
   run the scheme with `-AppleLanguages (en)` / `(ja)`.

### Suggested shots (8)
1. **Home dashboard** — totals card + low-stock / overdue-loan / expiring-lot
   summary (the at-a-glance value proposition).
2. **Projects list** — sample project with low-stock chip and shared icon.
3. **Product detail (quantity)** — quick receive/consume + QR labels + history.
4. **QR Label Studio** — size presets, QR Fit score, PDF/PNG/EPS export.
5. **Scan** — camera reticle with torch/zoom controls (use a device or a posed
   simulator frame; camera is black in Simulator, so prefer a real device).
6. **On loan** — overdue section highlighted, borrower + due date.
7. **Lot detail** — lot quantity, expiry date with "expiring/expired" badge,
   per-lot QR label.
8. **Activity** — grouped ledger with filters (project / type / period).

### Tips
- Turn off the keyboard before capturing forms (tap elsewhere).
- Keep names generic in sample data (already the case).
- Export at native resolution; do not scale up.
- `-uiTesting` launch argument starts from a clean in-memory store and routes
  the scanner through a mock — handy for scripted/automated capture.

---

## 3. Final pre-upload gate (Mac)
- `xcodebuild ... build` (Simulator) is clean.
- `xcodebuild ... test` (Unit + UI) passes.
- Bundle ID / Team ID / CloudKit container set (`CLOUDKIT_SETUP.md`).
- CloudKit schema deployed to **Production**.
- `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` bumped.
- Archive → Distribute → App Store Connect → Upload → TestFlight, then verify on
  device: QR scan/print, overdue-loan local notification, lot expiry badges,
  and two-Apple-ID sharing.
