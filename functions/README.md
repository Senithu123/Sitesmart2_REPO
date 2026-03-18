# Stripe Test Setup

## 1. Set the Stripe secret key

Set the Firebase Functions secret before deploying:

```bash
firebase functions:secrets:set STRIPE_SECRET_KEY
```

When prompted, paste your current `sk_test_...` key.

## 2. Deploy the callable function

```bash
firebase deploy --only functions
```

## 3. Test in the Flutter app

Use Stripe test card details:

- Card number: `4242 4242 4242 4242`
- Expiry: any future date
- CVC: any 3 digits
- ZIP: any value

## Notes

- The Flutter app uses the publishable key only.
- The backend must keep the Stripe secret key private.
- The callable function name used by the app is `createVrSubscriptionPaymentIntent`.
