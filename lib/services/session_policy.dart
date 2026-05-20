class SessionPolicy {
  static const Duration otpTrustDuration = Duration(hours: 8);
  static const Duration idleLockDuration = Duration(minutes: 45);
  static const Duration absoluteSessionDuration = Duration(hours: 12);

  static int get otpTrustMillis => otpTrustDuration.inMilliseconds;
  static int get absoluteSessionMillis =>
      absoluteSessionDuration.inMilliseconds;
}

int claimMillis(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

int authTimeMillis(dynamic value) {
  if (value is int) return value * 1000;
  if (value is num) return value.toInt() * 1000;
  return 0;
}

bool isAbsoluteSessionFresh(Map<String, dynamic> claims) {
  final authMs = authTimeMillis(claims['auth_time']);
  if (authMs <= 0) return false;
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  return (nowMs - authMs) <= SessionPolicy.absoluteSessionMillis;
}

bool isOtpSessionFresh(Map<String, dynamic> claims) {
  final otp = claims['otp_verified'] == true;
  final otpAtMs = claimMillis(claims['otp_verified_at']);
  final authMs = authTimeMillis(claims['auth_time']);
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  final otpAfterThisLogin = authMs > 0 && otpAtMs >= (authMs - 5000);
  return otp &&
      otpAtMs > 0 &&
      otpAfterThisLogin &&
      (nowMs - otpAtMs) <= SessionPolicy.otpTrustMillis &&
      isAbsoluteSessionFresh(claims);
}
