const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const Stripe = require("stripe");

admin.initializeApp();

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");

const supportedPlans = {
  vr_basic: {
    amount: 1500,
    currency: "lkr",
    name: "VR Basic",
  },
  vr_premium: {
    amount: 3000,
    currency: "lkr",
    name: "VR Premium",
  },
};

exports.createVrSubscriptionPaymentIntent = onCall({
  secrets: [stripeSecretKey],
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }

  const stripeSecret = stripeSecretKey.value();

  if (!stripeSecret) {
    logger.error("Stripe secret key is not configured.");
    throw new HttpsError(
        "failed-precondition",
        "Stripe secret key is not configured on the backend.",
    );
  }

  const stripe = new Stripe(stripeSecret);

  const planId = request.data?.planId;
  const plan = supportedPlans[planId];

  if (!plan) {
    throw new HttpsError("invalid-argument", "Unsupported VR plan.");
  }

  const amountInMinorUnits = plan.amount * 100;

  try {
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountInMinorUnits,
      currency: plan.currency,
      automatic_payment_methods: {
        enabled: true,
      },
      metadata: {
        feature: "vr_subscription",
        planId,
        planName: plan.name,
        userId: request.auth.uid,
      },
    });

    return {
      clientSecret: paymentIntent.client_secret,
      amount: plan.amount,
      currency: plan.currency,
      planName: plan.name,
    };
  } catch (error) {
    logger.error("Failed to create Stripe PaymentIntent.", error);
    throw new HttpsError("internal", error.message || "Unable to create payment.");
  }
});
