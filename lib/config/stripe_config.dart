class StripeConfig {
  const StripeConfig._();

  // Set this with:
  // flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...
  static const String publishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  static const String merchantDisplayName = 'Site Smart';
  static const String vrCurrency = 'lkr';
  static const int vrAmount = 150000; // Rs.1500.00 in Stripe minor units.

  static String get vrAmountLabel {
    final majorUnits = vrAmount / 100;
    final hasDecimals = vrAmount % 100 != 0;
    return hasDecimals
        ? 'Rs.${majorUnits.toStringAsFixed(2)}'
        : 'Rs.${majorUnits.toStringAsFixed(0)}';
  }
}
