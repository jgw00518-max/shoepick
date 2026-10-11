class StaffProductOption {
  const StaffProductOption({
    required this.id,
    required this.productId,
    required this.productCode,
    required this.colorCode,
    required this.colorName,
    required this.sizeMm,
    required this.additionalPrice,
    required this.isActive,
  });

  final int id;
  final int productId;
  final String productCode;
  final String colorCode;
  final String colorName;
  final int sizeMm;
  final int additionalPrice;
  final bool isActive;

  factory StaffProductOption.fromJson(Map<String, dynamic> json) {
    return StaffProductOption(
      id: (json['product_variant_id'] as num).toInt(),
      productId: (json['product_id'] as num).toInt(),
      productCode: json['product_code'] as String,
      colorCode: json['color_code'] as String,
      colorName: json['color_name'] as String,
      sizeMm: (json['size_mm'] as num).toInt(),
      additionalPrice: (json['additional_price'] as num).toInt(),
      isActive: json['is_active'] as bool,
    );
  }
}