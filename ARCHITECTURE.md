# Antigravity - Technical Specification & Architecture Document (Flutter)

## 1. Overview

This document outlines the structural hierarchy, Flutter architectural pattern, file organization rules, and future extensibility for the **Antigravity** project inside the **Violeafy Cross-App** workspace.

---

## 2. Strict Local Location Constraints

> **Mandatory Rule:** All source code files, configurations, assets, and build outputs MUST reside strictly inside the designated root directory:
> `D:\violeafycrossapp\`

* **Local Enforcement:** No packages, native scripts, or temporary generation files should be output outside `D:\violeafycrossapp\`.
* **Package Imports:** Use relative imports or standard package imports defined within `pubspec.yaml` anchored to `D:\violeafycrossapp\`.

---

## 3. Flutter Directory & File Hierarchy

The project adheres to Flutter feature-first / domain-driven architecture to keep files organized, modular, and out of focus when not actively being worked on:

```text
D:\violeafycrossapp\
├── .dart_tool/              # Auto-generated Dart build tools (ignored)
├── android/                 # Native Android configuration & entry points
├── ios/                     # Native iOS configuration & entry points
├── web/                     # Web entry point & assets
├── assets/                  # App resources (images, icons, fonts, env configs)
│   ├── images/
│   └── icons/
├── lib/                     # Core Dart/Flutter application logic
│   ├── main.dart            # Main app entry point
│   ├── app/                 # App-wide routing, theme, and initialization
│   │   ├── routes.dart
│   │   └── theme.dart
│   ├── core/                # Shared state, constants, networks, & services
│   │   ├── constants/       # App-wide constants & keys
│   │   ├── network/         # API clients & HTTP services
│   │   └── utils/           # Helper functions & extension methods
│   ├── features/            # Feature-first modular breakdown
│   │   ├── antigravity/     # Core Antigravity module
│   │   │   ├── data/        # Models, repositories, data sources
│   │   │   ├── domain/      # Business logic, entities, use cases
│   │   │   └── presentation/# UI screens, widgets, controllers/state
│   │   │       ├── screens/
│   │   │       └── widgets/
│   │   └── common_widgets/  # Reusable UI widgets across features
├── test/                    # Unit, widget, and integration tests
├── build/                   # Compiled outputs (generated locally)
├── .gitignore               # Version control ignore list
├── pubspec.yaml             # Flutter dependencies & assets metadata
└── README.md                # Project quickstart guide
```

---

## 4. Code Focus & Separation (Out-of-Focus Modularization)

To ensure smooth maintenance and clarity:

* **Feature-First Architecture:** Isolate logic inside `lib/features/<feature>/` so secondary features or legacy modules stay separated and out of focus.
* **Layered Separation (Clean Architecture):** Keep **Data**, **Domain**, and **Presentation** strictly decoupled within each feature folder.
* **Extract Reusable Widgets:** Avoid giant `build()` methods in screens. Extract sub-views into standalone widgets inside `presentation/widgets/`.
* **Centralized Shared Utilities:** Move cross-cutting concerns (e.g., formatters, validators) into `lib/core/utils/`.

---

## 5. Future Roadmap & Extensibility

* **Modular Feature Expansion:** Add future features by introducing new directories under `lib/features/` without altering core application configurations.
* **Cross-Platform Readiness:** Maintain clean platform abstraction across desktop, mobile, and web targets bounded strictly within `D:\violeafycrossapp\`.
* **State Management Integration:** Pre-configured layer structure supports clean state management libraries (e.g., BLoC, Riverpod, or Provider).
