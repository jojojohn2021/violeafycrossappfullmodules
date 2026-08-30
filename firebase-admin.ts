import { initializeApp, cert, App, getApps } from 'firebase-admin/app';
import { getFirestore, Firestore } from 'firebase-admin/firestore';
import { getAuth, Auth } from 'firebase-admin/auth';
import { getStorage, Storage } from 'firebase-admin/storage';
import path from 'path';
import fs from 'fs';

let adminApp: App;

if (getApps().length > 0) {
  adminApp = getApps()[0];
} else {
  const serviceAccountPath = path.join(process.cwd(), 'serviceAccountKey.json');
  const storageBucket = process.env.VIO_FIREBASE_STORAGE_BUCKET || process.env.FIREBASE_STORAGE_BUCKET || 'violeafybasket.firebasestorage.app';

  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf-8'));
    adminApp = initializeApp({
      credential: cert(serviceAccount),
      storageBucket,
    });
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
    const serviceAccount = JSON.parse(fs.readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf-8'));
    adminApp = initializeApp({
      credential: cert(serviceAccount),
      storageBucket,
    });
  } else {
    // Google Cloud Runtime environment (Cloud Run / Cloud Functions / Firebase App Hosting)
    adminApp = initializeApp({
      storageBucket,
    });
  }
}

// Authenticated Authentication client
export const adminAuth: Auth = getAuth(adminApp);

// Authenticated Firestore client (using the "violeafydb" database)
const dbId = process.env.VIO_FIREBASE_DATABASE_ID || process.env.FIREBASE_DATABASE_ID || 'violeafydb';
export const adminDb: Firestore = getFirestore(adminApp, dbId);

// Authenticated Cloud Storage client
export const adminStorage: Storage = getStorage(adminApp);

export { adminApp };
