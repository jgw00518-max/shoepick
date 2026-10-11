class StaffProduct {
  const StaffProduct({
    required this.id,
    required this.name,
    required this.modelCode,
    required this.brandId,
    required this.brandName,
    required this.categoryId,
    required this.categoryName,
    required this.manufacturerId,
    required this.manufacturerName,
    required this.genderCode,
    required this.description,
    required this.price,
    required this.isActive,
  });

  final int id;
  final String name;
  final String modelCode;
  final int brandId;
  final String brandName;
  final int categoryId;
  final String categoryName;
  final int? manufacturerId;
  final String? manufacturerName;
  final String genderCode;
  final String? description;
  final int price;
  final bool isActive;

  factory StaffProduct.fromJson(Map<String, dynamic> json) {
    return StaffProduct(
      id: (json['product_id'] as num).toInt(),
      name: json['product_name'] as String,
      modelCode: json['model_code'] as String,
      brandId: (json['brand_id'] as num).toInt(),
      brandName: json['brand_name'] as String,
      categoryId: (json['category_id'] as num).toInt(),
      categoryName: json['category_name'] as String,
      manufacturerId: (json['manufacturer_id'] as num?)?.toInt(),
      manufacturerName: json['manufacturer_name'] as String?,
      genderCode: json['gender_code'] as String,
      description: json['product_description'] as String?,
      price: (json['price'] as num).toInt(),
      isActive: json['is_active'] as bool,
    );
  }
}