/**
 * Centralized Store Compliance Configuration for VioleafyCross Backend.
 * Contains legal entity details, support contacts, policy links, and Razorpay configuration.
 */

export const complianceConfig = {
  business: {
    legalName: "Violeafy Cross Private Limited",
    displayName: "VioleafyCross",
    address: "Plot 102, Green Tech Park, Electronic City, Bengaluru, Karnataka 560100, India",
    country: "India",
    supportEmail: "support@violeafy.com",
    supportPhone: "+91 80 4567 8900",
    privacyEmail: "privacy@violeafy.com",
    grievanceContact: {
      role: "Grievance Officer",
      name: "Compliance & Safety Cell",
      email: "grievance@violeafy.com",
      phone: "+91 80 4567 8901",
    },
  },
  urls: {
    website: "https://violeafy.com",
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
