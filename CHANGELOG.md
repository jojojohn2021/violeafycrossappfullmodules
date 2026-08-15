# Changelog

All notable changes to this project during the migration will be documented in this file.

---

## [1.0.0] - 2026-07-25

### Added
* Native CustomPainter rendering the premium gold-crimson-fuchsia circular gradient logo border (`fruits_flowers_logo.dart`).
* State-managed providers (`AuthProvider`, `ShoppingProvider`, `LeadProvider`, `ReferralProvider`) utilizing clean abstraction layers.
* Responsive multi-viewport navigation layout (`shell_navigation.dart`) with bottom navigation and persistent drawer panels.
* WhatsApp client import integrations and Gemini AI lead recommendation pipeline.
* Administrative Settings metric dashboard controls to purge database and populate inventory models.
* Backend APIs in `server.ts` to clear databases and seed dummy catalog data.

### Changed
* Migrated deprecated `.withOpacity()` usage across all screens and widgets to the modern `.withValues(alpha: ...)` API.
* Restructured payment options inside `checkout_screen.dart` with modern `RadioGroup` widget wrappers.
* Migrated `DropdownButtonFormField` deprecated `value` parameter to `initialValue`.
* Optimized list spread operators by removing redundant `.toList()` iterations.
* Served Flutter Web build output statically from `build/web` in the Express server.

### Removed
* Deleted all legacy WebFrame, React, Vite, Babel, and Tailwind CSS configuration files.
* Removed legacy `src/` React source code files and `public/` directories.
* Deleted unused desktop platform modules (`linux/` and `macos/`).
* Pruned all unused frontend dependencies from `package.json` and cleaned up `node_modules/`.
