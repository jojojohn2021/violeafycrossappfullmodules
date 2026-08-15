# API Documentation

This document describes the primary REST API endpoints exposed by the Node.js/Express backend server (`server.ts`) and consumed by the Flutter application.

---

## 🔒 Authentication Flow

Authentication uses JWT tokens stored locally in standard headers (`Authorization: Bearer <token>`).

### 1. User Login
Authenticate user credentials.
* **URL**: `/api/auth/login`
* **Method**: `POST`
* **Request Body**:
  ```json
  {
    "username": "user123",
    "password": "pin_password"
  }
  ```
* **Response (Success)**:
  ```json
  {
    "token": "eyJhbGciOi...",
    "user": {
      "id": "u1",
      "username": "user123",
      "role": "Client"
    }
  }
  ```

### 2. Send OTP
Send verification code.
* **URL**: `/api/auth/send-otp`
* **Method**: `POST`
* **Request Body**:
  ```json
  {
    "phone": "+919876543210"
  }
  ```

---

## 🛍️ Shopping & Checkout APIs

### 1. Retrieve Catalog Products
Get inventory lists.
* **URL**: `/api/products`
* **Method**: `GET`
* **Response**:
  ```json
  [
    {
      "id": "p1",
      "name": "Bonsai Plant",
      "category": "Plants",
      "onlinePrice": 1200,
      "stock": 15
    }
  ]
  ```

### 2. Add Item to Cart
Add item to user shopping cart.
* **URL**: `/api/cart/add`
* **Method**: `POST`
* **Request Body**:
  ```json
  {
    "userId": "u1",
    "productId": "p1",
    "quantity": 1
  }
  ```

### 3. Initiate Payment (PayU Sandbox)
Initiate payment transaction callback.
* **URL**: `/api/payment/initiate`
* **Method**: `POST`
* **Request Body**:
  ```json
  {
    "orderId": "o100",
    "amount": 1200,
    "paymentMethod": "UPI"
  }
  ```
* **Response**:
  ```json
  {
    "txId": "pay_tx_99812",
    "redirectUrl": "https://sandbox.payu.in/_payment",
    "status": "initiated"
  }
  ```

---

## 💼 Lead Management & CRM APIs

### 1. Retrieve CRM Leads
Get all leads assigned to the user role.
* **URL**: `/api/leads`
* **Method**: `GET`
* **Response**:
  ```json
  [
    {
      "id": "lead_99",
      "name": "John Doe",
      "phone": "+919988776655",
      "status": "New"
    }
  ]
  ```

### 2. Get Gemini AI Lead Recommendations
Fetch automated AI suggestions for nurturing a lead.
* **URL**: `/api/leads/:id/ai-recommendation`
* **Method**: `GET`
* **Response**:
  ```json
  {
    "id": "lead_99",
    "recommendation": "Suggest festive plant gift discounts via WhatsApp message."
  }
  ```

---

## 💸 Wallet & Referrals APIs

### 1. Partner Wallet Balance
Fetch active partner Wallet logs.
* **URL**: `/api/partners/wallet`
* **Method**: `GET`
* **Response**:
  ```json
  {
    "balance": 4500,
    "ledger": [
      { "txId": "w1", "amount": 500, "type": "Credit", "description": "Referral commission" }
    ]
  }
  ```

### 2. Withdraw Earnings
Initiate withdrawal payout.
* **URL**: `/api/partners/withdraw`
* **Method**: `POST`
* **Request Body**:
  ```json
  {
    "amount": 1000,
    "paymentDetails": "upi@bank"
  }
  ```
