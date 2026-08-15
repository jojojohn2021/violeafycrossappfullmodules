# Leafy Fruits n Flowers Web Application (Flutter Migration)

This repository contains the fully migrated native Flutter presentation layer of the **Leafy Fruits n Flowers Web Application**, supporting Android, iOS, and Web viewports. The legacy React/Vite/WebFrame components have been successfully removed, leaving a clean, production-ready full-stack workspace integrated with the Node.js/Express backend server.

---

## 🏗️ Project Architecture & Structure

The codebase is organized following clean architectural principles:

```
lib/
├── core/               # Infrastructure, app theme, configurations, and utilities
│   ├── config/         # Environment configurations (API Base URLs, flags)
│   ├── theme/          # App theme styling tokens (Material 3 colors, shapes)
│   └── utils/          # Helpers (formatters, validators)
├── models/             # Domain and network data transfer objects (models.dart)
├── providers/          # Business logic and state management (AuthProvider, ShoppingProvider, etc.)
├── repositories/       # Data Access Layer (REST client, local storage, Firestore repository)
├── screens/            # Presentation Layer - UI screens and feature views
│   ├── account/        # Profile views, tracking and customer settings
│   ├── leads/          # CRM management dashboard & partner panel
│   ├── referrals/      # Wallet transactions, ledger and earning metrics
│   ├── settings/       # App administration, role selector & backend controls
│   ├── shopping/       # Product browsing, catalog search, cart, and checkout flow
│   └── shell_navigation.dart # Responsive navigation viewport wrapper
├── widgets/            # Globally shared and customized widgets (Logo custom paints)
└── main.dart           # App bootstrap
```

---

## 🛠️ Environment Setup & Running

### Prerequisites
* **Flutter SDK**: `^3.12.2` (Dart `^3.0.0`)
* **Node.js**: `^20.0.0` or higher
* **MongoDB**: A running MongoDB instance or connection credentials

### Step 1: Install Backend Dependencies
Run the following in the root folder to install the required Node.js backend packages:
```bash
npm install
```

### Step 2: Configure Environment Variables
Create a `.env` file in the root folder and specify the backend credentials:
```ini
MONGODB_URI=mongodb://...
PORT=3000
GEMINI_API_KEY=...
```

### Step 3: Run the Backend Integration Server
Start the Express API backend, which hosts the REST endpoints and serves the compiled Flutter Web assets statically:
```bash
npm run dev
```

### Step 4: Run the Flutter Application
In a separate terminal, launch the Flutter application on your target platform:
```bash
# Run on connected emulator or device (Android/iOS)
flutter run

# Run on Web (using custom server port mapping)
flutter run -d chrome
```

---

## 📦 Build Instructions

### 1. Android Release Build
Compile the app into a release APK:
```bash
flutter build apk --release
```
The output file is generated at `build/app/outputs/flutter-apk/app-release.apk`.

### 2. iOS Release Build
Compile the app for iOS distribution:
```bash
flutter build ipa
```

### 3. Flutter Web Build
To build the static web bundle that is served by the backend server:
```bash
flutter build web --release
```
The output is generated at `build/web/` and served statically by the Node/Express backend at port `3000`.

---

## 🔬 Troubleshooting

* **Static Analysis Warnings**:
  If you encounter formatting or compiler issues, run:
  ```bash
  flutter analyze --no-pub
  ```
* **Clean Build Cache**:
  If there are caching or build issues:
  ```bash
  flutter clean
  flutter pub get
  ```
