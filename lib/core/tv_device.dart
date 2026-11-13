enum TvBrand { lg, samsung, samsungEncrypted, samsungLegacy, fireTv }

class TvDevice {
  const TvDevice({
    required this.id,
    required this.name,
    required this.brand,
    required this.host,
    this.mac,
  });

  final String id;
  final String name;
  final TvBrand brand;
  final String host;
  final String? mac;

  TvDevice copyWith({String? host, String? mac}) => TvDevice(
        id: id,
        name: name,
        brand: brand,
        host: host ?? this.host,
        mac: mac ?? this.mac,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'brand': brand.name, 'host': host, 'mac': mac};

  factory TvDevice.fromJson(Map<String, dynamic> json) => TvDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        brand: TvBrand.values.byName(json['brand'] as String),
        host: json['host'] as String,
        mac: json['mac'] as String?,
      );
}
