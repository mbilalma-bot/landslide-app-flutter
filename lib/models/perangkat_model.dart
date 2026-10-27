class PerangkatModel {
  const PerangkatModel({
    required this.idPerangkat,
    required this.namaPerangkat,
    this.createdAt,
  });

  final String idPerangkat;
  final String namaPerangkat;
  final DateTime? createdAt;

  factory PerangkatModel.fromMap(Map<String, dynamic> map) {
    DateTime? created;
    final rawCreated = map['created_at'];
    if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated)?.toLocal();
    } else if (rawCreated is DateTime) {
      created = rawCreated.toLocal();
    }

    return PerangkatModel(
      idPerangkat: (map['id_perangkat'] ?? '').toString(),
      namaPerangkat: (map['nama_perangkat'] ?? '').toString(),
      createdAt: created,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_perangkat': idPerangkat,
      'nama_perangkat': namaPerangkat,
      if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
    };
  }

  PerangkatModel copyWith({
    String? idPerangkat,
    String? namaPerangkat,
    DateTime? createdAt,
  }) {
    return PerangkatModel(
      idPerangkat: idPerangkat ?? this.idPerangkat,
      namaPerangkat: namaPerangkat ?? this.namaPerangkat,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
