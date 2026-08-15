# Deployment Guide

This guide details the release build processes, environment setups, and production hosting steps for the **Leafy Fruits n Flowers** Flutter application and Express backend.

---

## 🌎 Environment & Production Configurations

### Environment Variables
Configure the following keys in your production hosting environment (e.g. Firebase, Render, AWS, Heroku):

* `MONGODB_URI`: Production MongoDB Atlas connection string.
* `PORT`: Server listening port (default is `3000`).
* `GEMINI_API_KEY`: API key for Google Gemini model.
* `NODE_ENV`: Set to `production` to serve static assets and disable dev tooling.

### Firebase Credentials config
Configure Firebase files in the platform-specific directories:
* **Android**: `android/app/google-services.json`
* **iOS**: `ios/Runner/GoogleService-Info.plist`

---

## 📦 Build Commands

### 1. Compile Flutter Web Assets
To compile the Flutter Web build:
```bash
flutter build web --release --web-renderer canvaskit
```
The output assets will be created in `build/web/`. The Express backend `server.ts` is configured to automatically serve these files statically.

### 2. Build Android App Bundle / APK
Generate the release build outputs:
```bash
# Compile APK
flutter build apk --release

# Compile App Bundle (for Play Store upload)
flutter build appbundle --release
```
The APK output is generated at `build/app/outputs/flutter-apk/app-release.apk`.

### 3. Build iOS Application IPA
Generate files for iOS TestFlight/App Store:
```bash
flutter build ipa --release
```
Open the generated Workspace in Xcode (`ios/Runner.xcworkspace`) to complete signing, profiling, and upload.

---

## 🚀 Production Hosting & Deployments

### Full-stack Node Server deployment (including Flutter Web)
Since `server.ts` is configured to serve the Flutter Web assets statically, you can host the entire full-stack app on any Node.js environment:

1. **Step 1**: Compile Flutter Web assets:
   ```bash
   flutter build web --release
   ```
2. **Step 2**: Compile the backend `server.ts` to Javascript using the bundler script:
   ```bash
   npm run build
   ```
   This generates the optimized `dist/server.cjs` file.
3. **Step 3**: Start the production server:
   ```bash
   npm start
   ```

### CDN & Separate Web Hosting (Static Hosting)
If you prefer to host the Flutter Web client separately on a static CDN (e.g. Netlify, Vercel, Firebase Hosting):
* Point the hosting source folder directly to `build/web`.
* Configure the static server to rewrite all fallback routes to `index.html` (SPA routing).
