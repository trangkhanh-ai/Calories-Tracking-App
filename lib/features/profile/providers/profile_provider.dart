import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/profile_api_service.dart';

class ProfileNotifier extends AsyncNotifier<Map<String, dynamic>?> {
  @override
  Future<Map<String, dynamic>?> build() async {
    return await profileApiService.getProfile();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => profileApiService.getProfile());
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Map<String, dynamic>?>(() {
  return ProfileNotifier();
});
