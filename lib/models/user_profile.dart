class UserProfile {
  final String firstName;
  final String lastName;
  final String email;

  const UserProfile({
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  String get fullName => ('$firstName $lastName').trim();
}