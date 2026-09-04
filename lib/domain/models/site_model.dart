class SiteModel {
  final String id;
  final String siteCode;
  final String name;
  final String address;
  final String? creatorId;

  const SiteModel({
    required this.id,
    required this.siteCode,
    required this.name,
    required this.address,
    this.creatorId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'site_code': siteCode,
      'name': name,
      'address': address,
      'creator_id': creatorId,
    };
  }

  factory SiteModel.fromMap(Map<String, dynamic> map) {
    return SiteModel(
      id: map['id'] as String,
      siteCode: map['site_code'] as String? ?? '',
      name: map['name'] as String? ?? '',
      address: map['address'] as String? ?? '',
      creatorId: map['creator_id'] as String?,
    );
  }
}
