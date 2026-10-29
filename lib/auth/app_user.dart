import '../models/json_helpers.dart';
import 'role.dart';

class AppUser {
  final int id;
  final String username;
  final String fullName;
  final String email;
  final Role role;
  final int? readerId;

  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    this.email = '',
    required this.role,
    this.readerId,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final username = jsonString(json['username']);
    final fullName = jsonString(json['fullName']).trim();
    return AppUser(
      id: jsonInt(json['id']),
      username: username,
      fullName: fullName.isEmpty ? username : fullName,
      email: jsonString(json['email']),
      // Неизвестная роль получает наименьшие права.
      role: Role.tryParse(json['role']) ?? Role.reader,
      readerId: jsonIntOrNull(json['readerId']),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'username': username,
        'fullName': fullName,
        'email': email,
        'role': role.code,
        'readerId': readerId,
      };

  AppUser copyWith({Role? role}) {
    return AppUser(
      id: id,
      username: username,
      fullName: fullName,
      email: email,
      role: role ?? this.role,
      readerId: readerId,
    );
  }
}
