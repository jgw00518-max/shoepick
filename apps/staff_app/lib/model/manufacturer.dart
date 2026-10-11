class Manufacturer {
  const Manufacturer({
    required this.id,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
  });

  final int id;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;

  factory Manufacturer.fromJson(Map<String, dynamic> json) {
    return Manufacturer(
      id: (json['manufacturer_id'] as num).toInt(),
      name: json['manufacturer_name'] as String,
      contactName: json['contact_name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
    );
  }
}