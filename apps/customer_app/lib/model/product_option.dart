class ProductOption {
  const ProductOption({
    required this.id,
    required this.colorName,
    required this.sizeMm,
    required this.additionalPrice,
    required this.availableQuantity,
  });

  final int id;
  final String colorName;
  final int sizeMm;
  final int additionalPrice;
  final int availableQuantity;

  factory ProductOption.fromJson(Map<String, dynamic> json) {
    return ProductOption(
      id: (json['product_variant_id'] as num).toInt(),
      colorName: json['color_name'] as String,
      sizeMm: (json['size_mm'] as num).toInt(),
      additionalPrice: (json['additional_price'] as num).toInt(),
      availableQuantity: (json['available_quantity'] as num).toInt(),
    );
  }
}