import 'package:cloud_firestore/cloud_firestore.dart';

class HouseListing {
  final String id;
  final String imagePath;
  final String imageUrl;
  final List<String> galleryPaths;
  final String houseName;
  final String priceText;
  final String vrUrl;
  final String detail;
  final String location;
  final String bedrooms;
  final String bathrooms;
  final String sqft;
  final String about;
  final List<String> features;
  final bool isPublished;

  const HouseListing({
    required this.id,
    required this.imagePath,
    required this.imageUrl,
    required this.galleryPaths,
    required this.houseName,
    required this.priceText,
    required this.vrUrl,
    required this.detail,
    required this.location,
    required this.bedrooms,
    required this.bathrooms,
    required this.sqft,
    required this.about,
    required this.features,
    this.isPublished = true,
  });

  bool get hasNetworkImage => imageUrl.trim().isNotEmpty;

  String get primaryImage => hasNetworkImage ? imageUrl : imagePath;

  Map<String, dynamic> toMap({
    required String architectUid,
    required String architectEmail,
  }) {
    return {
      'imagePath': imagePath,
      'imageUrl': imageUrl.trim(),
      'galleryPaths': galleryPaths,
      'houseName': houseName.trim(),
      'priceText': priceText.trim(),
      'vrUrl': vrUrl.trim(),
      'detail': detail.trim(),
      'location': location.trim(),
      'bedrooms': bedrooms.trim(),
      'bathrooms': bathrooms.trim(),
      'sqft': sqft.trim(),
      'about': about.trim(),
      'features': features,
      'isPublished': isPublished,
      'architectUid': architectUid,
      'architectEmail': architectEmail,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static HouseListing fromMap(String id, Map<String, dynamic> data) {
    final bedrooms = (data['bedrooms'] ?? '').toString().trim();
    final bathrooms = (data['bathrooms'] ?? '').toString().trim();
    final sqft = (data['sqft'] ?? '').toString().trim();
    final detail = (data['detail'] ?? '').toString().trim();

    return HouseListing(
      id: id,
      imagePath: (data['imagePath'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      galleryPaths: _readFeatures(data['galleryPaths']),
      houseName: (data['houseName'] ?? 'Untitled House').toString(),
      priceText: (data['priceText'] ?? '-').toString(),
      vrUrl: (data['vrUrl'] ?? '').toString(),
      detail: detail.isNotEmpty
          ? detail
          : _buildDetail(
              bedrooms: bedrooms,
              bathrooms: bathrooms,
              sqft: sqft,
            ),
      location: (data['location'] ?? '-').toString(),
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      sqft: sqft,
      about: (data['about'] ?? '').toString(),
      features: _readFeatures(data['features']),
      isPublished: data['isPublished'] != false,
    );
  }

  static List<String> _readFeatures(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String) {
      return value
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static String _buildDetail({
    required String bedrooms,
    required String bathrooms,
    required String sqft,
  }) {
    final parts = <String>[];
    if (bedrooms.isNotEmpty) parts.add('$bedrooms Beds');
    if (bathrooms.isNotEmpty) parts.add('$bathrooms Baths');
    if (sqft.isNotEmpty) parts.add('$sqft sqft');
    return parts.isEmpty ? '-' : parts.join(' | ');
  }
}
