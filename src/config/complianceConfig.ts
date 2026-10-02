/**
 * Centralized Store Compliance Configuration for VioleafyCross Backend.
 * Contains legal entity details, support contacts, policy links, and Razorpay configuration.
 */

export const complianceConfig = {
  business: {
    legalName: "VAMJO",
    displayName: "Leafyearth",
    address: "Kallettumkara,Thrissur,Kerala-680683",
    country: "India",
    supportEmail: "info@vamjo.com.com",
    supportPhone: "+918547927539",
    privacyEmail: "info@vamjo.com",
    grievanceContact: {
      role: "Grievance Officer",
      name: "Compliance & Safety Cell",
      email: "sales@vamjo.com",
      phone: "+918547927539",
    },
  },
  urls: {
    website: "https://vamjo.com",
    privacyPolicy: "/privacy-policy",
    termsAndConditions: "/terms-and-conditions",
    shippingPolicy: "/shipping-and-delivery-policy",
    cancellationPolicy: "/cancellation-policy",
    returnRefundPolicy: "/return-and-refund-policy",
    contactUs: "/contact-us",
  },
  razorpay: {
    keyId: process.env.RAZORPAY_LIVE_KEY_ID || process.env.RAZORPAY_KEY_ID || "",
    keySecret: process.env.RAZORPAY_LIVE_KEY_SECRET || process.env.RAZORPAY_KEY_SECRET || "",
    webhookSecret: process.env.RAZORPAY_WEBHOOK_SECRET || "",
  },
};
