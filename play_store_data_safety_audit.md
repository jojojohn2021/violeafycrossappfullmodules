# Google Play Data Safety Declaration Audit Report — VioleafyCross

**App Title**: VioleafyCross  
**Package Name**: `com.violeafy.crossapp`  
**Audit Date**: August 31, 2026  
**Auditor**: VioleafyCross Compliance & Security Team  

---

## 1. Data Collection & Sharing Overview

VioleafyCross collects and processes user data strictly to support e-commerce purchasing, delivery logistics, order fulfillment, account authentication, and customer support.

All data transmission between the client application and VioleafyCross servers is encrypted in transit via **HTTPS (TLS 1.3)**.

---

## 2. Detailed Data Category Declarations

| Data Category | Data Type | Collected? | Shared? | Purpose | Optional / Mandatory |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Personal Info** | Name | Yes | No | Account Management, Order Fulfillment | Mandatory for account |
| **Personal Info** | Email address | Yes | No | Authentication, Invoices, Order Notices | Mandatory for account |
| **Personal Info** | Phone / Mobile | Yes | No | OTP Authentication, Delivery Contacts | Mandatory for account |
| **Personal Info** | Address / PIN code | Yes | No | Order Delivery Logistics | Mandatory for checkout |
| **Financial Info** | Purchase History | Yes | No | Order Management, Customer History | Mandatory |
| **Financial Info** | Payment Identifiers | Yes | Shared with Razorpay | Payment Processing & Order Verification | Mandatory for payment |
| **App Info & Perf** | Crash Logs | Yes | No | App Stability & Troubleshooting | Automatic / Diagnostic |
| **Device / IDs** | Device / Push Token | Yes | No | Push Notifications & Security | Optional |

---

## 3. Third-Party SDK Data Audit

1. **Firebase Authentication (Google)**: Used for OTP mobile login and email authentication.
2. **Cloud Firestore (Google)**: Stores order history, product catalog, addresses, and user profiles.
3. **Firebase Storage (Google)**: Used for profile avatar uploads.
4. **Razorpay SDK / Gateway**: Handles payment processing securely. Sensitive payment credentials (card numbers, UPI PINs, bank credentials) are handled directly by Razorpay (PCI-DSS Level 1 compliant) and never stored on VioleafyCross servers.

---

## 4. User Data Rights & Account Deletion

VioleafyCross complies with Google Play user privacy policies by providing an in-app account deletion mechanism under **Profile > Account Settings > Request Account & Data Deletion**, as well as web-based deletion request options via privacy contact `privacy@violeafy.com`.
