class ReasonModel {
  final String id;
  final String category;
  final String label;
  final String? description;
  final bool isActive;
  final int displayOrder;

  ReasonModel({
    required this.id,
    required this.category,
    required this.label,
    this.description,
    this.isActive = true,
    this.displayOrder = 0,
  });

  factory ReasonModel.fromJson(Map<String, dynamic> json) {
    return ReasonModel(
      id: json['id'] as String,
      category: json['category'] as String? ?? 'other',
      label: json['label'] as String? ?? '',
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'label': label,
      'description': description,
      'is_active': isActive,
      'display_order': displayOrder,
    };
  }
}
