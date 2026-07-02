import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/api_client.dart';

class ProfileApiService {
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final response = await apiClient.get('/profile/me');
      if (response.statusCode == 200) return response.data;
      return null;
    } catch (e) {
      print('Get Profile Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateProfile({
    required String displayName,
    required double height,
    required double weight,
    required int age,
    required String gender,
    int? targetCalories,
    String? defaultAvatarUrl,
    String? activityLevel,
  }) async {
    try {
      final mapData = <String, dynamic>{
        'DisplayName': displayName,
        'Height': height.toString(),
        'Weight': weight.toString(),
        'Age': age.toString(),
        'Gender': gender,
      };

      if (targetCalories != null) {
        mapData['TargetCalories'] = targetCalories.toString();
      }

      if (defaultAvatarUrl != null) {
        mapData['DefaultAvatarUrl'] = defaultAvatarUrl;
      }
      if (activityLevel != null) {
        mapData['ActivityLevel'] = activityLevel;
      }

      final formData = FormData.fromMap(mapData);

      final response = await apiClient.patch('/profile/me', data: formData);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      }
      return null;
    } catch (e) {
      print('Update Profile Error: $e');
      rethrow;
    }
  }

  /// Backend tính BMI/BMR/TDEE/calo khuyến nghị từ hồ sơ đã lưu.
  /// [goal]: 'lose' | 'maintain' | 'gain'
  Future<Map<String, dynamic>?> getCalorieGoal({String? goal}) async {
    try {
      final response = await apiClient.get(
        '/profile/calorie-goal',
        queryParameters: goal != null ? {'goal': goal} : null,
      );
      if (response.statusCode == 200) return response.data;
      return null;
    } catch (e) {
      print('Get Calorie Goal Error: $e');
      return null;
    }
  }

  Future<List<String>> getDefaultAvatars() async {
    try {
      final response = await apiClient.get('/profile/default-avatars');
      if (response.statusCode == 200) {
        return List<String>.from(response.data);
      }
      return [];
    } catch (e) {
      print('Get Default Avatars Error: $e');
      return [];
    }
  }
}

final profileApiService = ProfileApiService();
