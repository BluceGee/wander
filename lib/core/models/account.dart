/// 账号模型：服务器返回的用户与会话。
class UserProfile {
  const UserProfile({
    required this.username,
    required this.createdAt,
  });

  final String username;
  final String createdAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        username: json['username'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
      );
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final UserProfile user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        token: json['token'] as String? ?? '',
        user: UserProfile.fromJson(json['user'] as Map<String, dynamic>? ?? {}),
      );
}
