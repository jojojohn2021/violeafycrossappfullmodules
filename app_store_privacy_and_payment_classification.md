# Apple App Store Privacy & Payment Compliance Audit Report — VioleafyCross

**App Title**: VioleafyCross  
**Bundle Identifier**: `com.violeafy.crossapp`  
**Audit Date**: August 31, 2026  
**Compliance Target**: Apple App Store Review Guidelines 3.1.5(a) & App Privacy Details  

---

## 1. Apple App Store Payment Compliance Classification

### Classification Determination
* **Product Type**: Physical Consumer Goods (authentic personal care, lifestyle, wellness, household goods).
* **Delivery Mechanism**: Physical shipment via regional logistics partners to specified PIN codes across India.
* **Consumable Location**: Consumed physically outside the application.

### Apple App Store Review Guideline 3.1.5(a) Verification
> *"3.1.5(a) Goods and Services Outside the App: If your app enables people to purchase physical goods or services that will be consumed outside the app, you must use purchase methods other than in-app purchase to collect those payments, such as Apple Pay or traditional credit card processing."*

**Conclusion**:
VioleafyCross exclusively sells physical goods delivered to customer shipping addresses. Under Apple App Store Review Guideline 3.1.5(a), the use of third-party payment processors like **Razorpay** is fully compliant and permitted for physical goods transactions. Apple In-App Purchase (IAP) is not required nor allowed for physical product purchases.

---

## 2. App Store Privacy Details (App Privacy Label Declaration)

### Data Types Collected:
1. **Contact Info**:
   * Name (Data Linked to User)
   * Email Address (Data Linked to User)
   * Phone Number (Data Linked to User)
   * Physical Address (Data Linked to User)
2. **Purchases**:
   * Purchase History (Data Linked to User)
3. **Identifiers**:
   * User ID / Account ID (Data Linked to User)
   * Device ID / Push Token (Data Linked to User)
4. **Diagnostics**:
   * Crash Data (Data Not Linked to User)

---

## 3. Account Deletion Compliance (Guideline 5.1.1(v))

VioleafyCross satisfies Apple App Store Review Guideline 5.1.1(v) by providing an accessible, in-app account deletion entry point in **Profile > Account & Data Deletion**. Initiating deletion revokes authentication tokens, deletes user profile data in Firestore, and calls Firebase Admin SDK `deleteUser()`.
