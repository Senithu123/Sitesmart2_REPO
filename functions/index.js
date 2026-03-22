const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const Stripe = require("stripe");

admin.initializeApp();

const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const VR_AMOUNT = 150000;
const VR_CURRENCY = "lkr";

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be signed in.");
  }
}

function vrAccessId(userId, houseTitle) {
  const slug = String(houseTitle || "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_|_$/g, "");
  return `${userId}_${slug}`;
}

function globalVrAccessId(userId) {
  return `${userId}_global_vr_access`;
}

function readRequiredString(data, key, label) {
  const value = String(data?.[key] || "").trim();
  if (!value) {
    throw new HttpsError("invalid-argument", `${label} is required.`);
  }
  return value;
}

function readOptionalString(data, key) {
  return String(data?.[key] || "").trim();
}

function stripeClient() {
  const secret = stripeSecretKey.value();
  if (!secret) {
    throw new HttpsError(
        "failed-precondition",
        "Stripe secret key is not configured.",
    );
  }
  return new Stripe(secret);
}

exports.createVrPaymentIntent = onCall(
    {secrets: [stripeSecretKey]},
    async (request) => {
      requireAuth(request);

      const userId = request.auth.uid;
      const houseTitle = readRequiredString(
          request.data,
          "houseTitle",
          "House title",
      );
      const customerName = readOptionalString(request.data, "customerName");
      const email = readOptionalString(request.data, "email");
      const accessRef = admin.firestore()
          .collection("vr_access")
          .doc(globalVrAccessId(userId));
      const existingAccess = await accessRef.get();

      if (existingAccess.exists && existingAccess.data()?.accessGranted === true) {
        throw new HttpsError(
            "already-exists",
            "VR access is already unlocked for this account.",
        );
      }

      const stripe = stripeClient();
      const paymentIntent = await stripe.paymentIntents.create({
        amount: VR_AMOUNT,
        currency: VR_CURRENCY,
        automatic_payment_methods: {enabled: true},
        description: `Global VR access unlocked from ${houseTitle}`,
        metadata: {
          userId,
          houseTitle,
          customerName,
          email,
        },
        ...(email ? {receipt_email: email} : {}),
      });

      if (!paymentIntent.client_secret) {
        throw new HttpsError(
            "internal",
            "Stripe payment setup failed.",
        );
      }

      await accessRef.set({
        userId,
        scope: "global",
        houseTitle,
        customerName,
        email,
        amount: VR_AMOUNT,
        currency: VR_CURRENCY,
        paymentIntentId: paymentIntent.id,
        paymentStatus: paymentIntent.status,
        accessGranted: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      return {
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        amount: VR_AMOUNT,
        currency: VR_CURRENCY,
      };
    },
);

exports.confirmVrPaymentAccess = onCall(
    {secrets: [stripeSecretKey]},
    async (request) => {
      requireAuth(request);

      const userId = request.auth.uid;
      const houseTitle = readRequiredString(
          request.data,
          "houseTitle",
          "House title",
      );
      const paymentIntentId = readRequiredString(
          request.data,
          "paymentIntentId",
          "Payment intent ID",
      );

      const stripe = stripeClient();
      const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
      const metadataUserId = String(paymentIntent.metadata?.userId || "").trim();
      const metadataHouseTitle = String(paymentIntent.metadata?.houseTitle || "").trim();

      if (metadataUserId != userId || metadataHouseTitle != houseTitle) {
        throw new HttpsError(
            "permission-denied",
            "This payment does not belong to the current user or house.",
        );
      }

      if (paymentIntent.status !== "succeeded") {
        throw new HttpsError(
            "failed-precondition",
            "Stripe payment was not completed successfully.",
        );
      }

      await admin.firestore()
          .collection("vr_access")
          .doc(globalVrAccessId(userId))
          .set({
            userId,
            scope: "global",
            houseTitle,
            customerName: String(paymentIntent.metadata?.customerName || "").trim(),
            email: String(paymentIntent.metadata?.email || "").trim(),
            amount: paymentIntent.amount,
            currency: paymentIntent.currency,
            paymentIntentId: paymentIntent.id,
            paymentStatus: paymentIntent.status,
            accessGranted: true,
            confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

      return {
        success: true,
        paymentIntentId: paymentIntent.id,
        accessGranted: true,
      };
    },
);
