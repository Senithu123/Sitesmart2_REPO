import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class StripeVrPaymentService {
  StripeVrPaymentService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  static Future<void> payForVrSubscription({
    required String planId,
    required String merchantDisplayName,
  }) async {
    final callable = _functions.httpsCallable(
      'createVrSubscriptionPaymentIntent',
    );

    final response = await callable.call(<String, dynamic>{
      'planId': planId,
    });

    final data = Map<String, dynamic>.from(response.data as Map);
    final clientSecret = data['clientSecret'] as String?;

    if (clientSecret == null || clientSecret.isEmpty) {
      throw Exception('Missing Stripe client secret from backend.');
    }

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: merchantDisplayName,
      ),
    );

    await Stripe.instance.presentPaymentSheet();
  }
}
