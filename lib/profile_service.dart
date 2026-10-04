import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class UserProfileData {
  final String role;
  final String id;
  final String name;
  final String? photoPath;
  final String? photoUrl;

  const UserProfileData({
    required this.role,
    required this.id,
    required this.name,
    this.photoPath,
    this.photoUrl,
  });
}

class ProfileService {
  static Future<UserProfileData> fetchProfile({
    required String role,
    required String id,
  }) async {
    final url = Uri.parse(
      ApiConfig.url(
        'get_user_profile.php?role=${Uri.encodeQueryComponent(role)}&id=${Uri.encodeQueryComponent(id)}',
      ),
    );
    final response = await http.get(url).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid profile response');
    }
    if (decoded['status'] != 'success') {
      throw Exception(decoded['message']?.toString() ?? 'Failed to load profile');
    }

    final profile = decoded['profile'];
    if (profile is! Map) {
      throw Exception('Missing profile payload');
    }

    return UserProfileData(
      role: profile['role']?.toString() ?? role,
      id: profile['id']?.toString() ?? id,
      name: profile['name']?.toString() ?? '',
      photoPath: profile['photo_path']?.toString(),
      photoUrl: profile['photo_url']?.toString(),
    );
  }

  static Future<UserProfileData> uploadPhoto({
    required String role,
    required String id,
    required File file,
  }) async {
    final uri = Uri.parse(ApiConfig.url('upload_profile_photo.php'));
    final request = http.MultipartRequest('POST', uri)
      ..fields['role'] = role
      ..fields['id'] = id
      ..files.add(await http.MultipartFile.fromPath('photo', file.path));

    final streamed = await request.send().timeout(const Duration(seconds: 20));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Upload failed: ${streamed.statusCode}');
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid upload response');
    }
    if (decoded['status'] != 'success') {
      throw Exception(decoded['message']?.toString() ?? 'Failed to upload photo');
    }

    final profile = decoded['profile'];
    if (profile is! Map) {
      throw Exception('Missing uploaded profile payload');
    }

    return UserProfileData(
      role: profile['role']?.toString() ?? role,
      id: profile['id']?.toString() ?? id,
      name: profile['name']?.toString() ?? '',
      photoPath: profile['photo_path']?.toString(),
      photoUrl: profile['photo_url']?.toString(),
    );
  }
}

