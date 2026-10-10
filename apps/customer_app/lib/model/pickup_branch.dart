class PickupBranch {
  const PickupBranch({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
  });

  final int id;
  final String name;
  final String address;
  final String phone;

  factory PickupBranch.fromJson(Map<String, dynamic> json) {
    return PickupBranch(
      id: (json['branch_id'] as num).toInt(),
      name: json['branch_name'] as String,
      address: json['address'] as String,
      phone: json['phone'] as String,
    );
  }
}