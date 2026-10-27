class UserModel {
  const UserModel({
    this.id,
    required this.namaUser,
    required this.usernameUser,
    required this.passwordUser,
  });

  final int? id;
  final String namaUser;
  final String usernameUser;
  final String passwordUser;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    int? parsedId;
    if (map['id'] != null) {
      if (map['id'] is int) {
        parsedId = map['id'];
      } else {
        parsedId = int.tryParse(map['id'].toString());
      }
    }

    return UserModel(
      id: parsedId,
      namaUser: (map['nama_user'] ?? '').toString(),
      usernameUser: (map['username_user'] ?? '').toString(),
      passwordUser: (map['password_user'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nama_user': namaUser,
      'username_user': usernameUser,
      'password_user': passwordUser,
    };
  }
}
