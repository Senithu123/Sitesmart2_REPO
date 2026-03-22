import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter/material.dart';

import '../config/stripe_config.dart';

class VrPaymentService {
  const VrPaymentService._();

  static bool get supportsNativeVrPayments =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get vrPriceLabel => StripeConfig.vrAmountLabel;

  static String get unsupportedPlatformMessage =>
      'VR payments are currently supported on Android and iOS only.';

  static Future<bool> hasVrAccess({
    required String houseTitle,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    final firestore = FirebaseFirestore.instance;

    final globalAccessDoc = await firestore
        .collection('vr_access')
        .doc(_globalVrAccessId(currentUser.uid))
        .get();
    if (_isUnlocked(globalAccessDoc.data())) {
      return true;
    }

    final accessDoc = await firestore
        .collection('vr_access')
        .doc(_vrAccessId(currentUser.uid, houseTitle))
        .get();
    if (_isUnlocked(accessDoc.data())) {
      return true;
    }
    return false;
  }

  static bool _isUnlocked(Map<String, dynamic>? data) {
    if (data == null) return false;
    final paymentStatus = (data['paymentStatus'] ?? '').toString().toLowerCase();
    return data['accessGranted'] == true || paymentStatus == 'succeeded';
  }

  static Future<void> payForVrAccess({
    required String houseTitle,
    required String customerName,
    required String email,
  }) async {
    if (await hasVrAccess(houseTitle: houseTitle)) {
      return;
    }
    if (!supportsNativeVrPayments) {
      throw Exception(unsupportedPlatformMessage);
    }
    if (StripeConfig.publishableKey.isEmpty) {
      throw Exception('Stripe publishable key is not configured.');
    }

    final normalizedName = customerName.trim();
    final normalizedEmail = email.trim();
    final functions = FirebaseFunctions.instance;
    final createIntent = functions.httpsCallable('createVrPaymentIntent');
    final confirmAccess = functions.httpsCallable('confirmVrPaymentAccess');

    final createResponse = await createIntent.call({
      'houseTitle': houseTitle,
      'customerName': normalizedName,
      'email': normalizedEmail,
    });

    final paymentData = Map<String, dynamic>.from(createResponse.data as Map);
    final clientSecret = (paymentData['clientSecret'] ?? '').toString();
    final paymentIntentId = (paymentData['paymentIntentId'] ?? '').toString();
    if (clientSecret.isEmpty || paymentIntentId.isEmpty) {
      throw Exception('Stripe payment setup failed.');
    }

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        merchantDisplayName: StripeConfig.merchantDisplayName,
        paymentIntentClientSecret: clientSecret,
        primaryButtonLabel: 'Pay ${StripeConfig.vrAmountLabel}',
        style: ThemeMode.system,
        billingDetails: BillingDetails(
          name: normalizedName.isEmpty ? null : normalizedName,
          email: normalizedEmail.isEmpty ? null : normalizedEmail,
        ),
      ),
    );

    await Stripe.instance.presentPaymentSheet();

    await confirmAccess.call({
      'paymentIntentId': paymentIntentId,
      'houseTitle': houseTitle,
    });
  }

  static String describeError(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
    if (error is StripeException) {
      final localized = error.error.localizedMessage?.trim();
      if (localized != null && localized.isNotEmpty) {
        return localized;
      }

      final fallback = error.error.message?.trim();
      if (fallback != null && fallback.isNotEmpty) {
        return fallback;
      }

      return 'Stripe payment was cancelled or failed.';
    }

    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? 'Unable to unlock VR access right now.' : text;
  }

  static String _vrAccessId(String userId, String houseTitle) {
    final slug = houseTitle
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '${userId}_$slug';
  }

  static String _globalVrAccessId(String userId) {
    return '${userId}_global_vr_access';
  }
}
