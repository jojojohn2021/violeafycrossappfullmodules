# VioleafyDB Migration Summary & Documentation

## Overview
This document summarizes the migration of the Violeafy application stack from the default Firestore database instance `(default)` to the custom, explicit Firestore database instance **`violeafydb`**.

---

## Migration Deliverables & Codebase Updates

### 1. Client-Side Setup (`src/firebase.ts`)
- Configured client SDK initialization to explicitly target `violeafydb`:
```typescript
import { initializeApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";

const app = initializeApp(firebaseConfig);
export const db = getFirestore(app, "violeafydb");
```

### 2. Backend & Server Integration (`server.ts`)
- Configured Firebase Admin SDK to target `violeafydb`:
```typescript
import { initializeApp, cert } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

export const adminDb = getFirestore("violeafydb");
```
- Integrated `/api/products` and `/api/data` endpoints querying `adminDb.collection("products")`.
- Dynamic connection fallback to MongoDB API / Memory fallback pointing to `violeafydb`.

### 3. Application Configuration
- Updated `firebase-applet-config.json`:
```json
{
  "projectId": "violeafybasket",
  "firestoreDatabaseId": "violeafydb",
  "region": "asia-south2"
}
```
- Updated `lib/core/config/env_config.dart`:
```dart
static const String firestoreDatabaseId = 'violeafydb';
```

### 4. Firestore Rules & Deployment Setup (`firebase.json` & `firestore.rules`)
- `firebase.json` target configured for `violeafydb`:
```json
{
  "firestore": [
    {
      "database": "violeafydb",
      "rules": "firestore.rules"
    }
  ]
}
```

---

## Offline Synchronization & Resilience
- Mobile & Web catalog, categories, cart, wishlist, and user profile cache remain functional offline.
- Pending writes synchronize on network re-establishment with server conflict resolution prioritizing server inventory state.

---

## Firebase Admin & Firebase Client Verification
- Verified `npm install firebase firebase-admin` installation.
- Verified zero implicit `(default)` database references across repository.
