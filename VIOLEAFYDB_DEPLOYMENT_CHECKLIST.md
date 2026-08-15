# VioleafyDB Deployment Checklist

## Pre-Deployment
- [x] 1. Verify `firebase-applet-config.json` specifies `"firestoreDatabaseId": "violeafydb"`.
- [x] 2. Verify `.env` / `.env.local` specify `REACT_APP_FIREBASE_DATABASE_ID=violeafydb`.
- [x] 3. Verify `src/firebase.ts` calls `getFirestore(app, "violeafydb")`.
- [x] 4. Verify `server.ts` calls `getFirestore("violeafydb")`.

## Deployment Steps
- [ ] 1. Deploy Firestore Security Rules specifically to `violeafydb`:
  ```bash
  firebase deploy --only firestore:rules:violeafydb
  ```
- [ ] 2. Deploy Firestore Indexes to `violeafydb`:
  ```bash
  firebase deploy --only firestore:indexes:violeafydb
  ```
- [ ] 3. Deploy Backend API Server (`server.ts` / production bundle).
- [ ] 4. Deploy Mobile & Web clients.

## Post-Deployment Verification
- [ ] 1. Query `/api/data` endpoint to verify `databaseId: "violeafydb"` response.
- [ ] 2. Verify document reads and writes in Firebase Console under `violeafydb` database instance.
