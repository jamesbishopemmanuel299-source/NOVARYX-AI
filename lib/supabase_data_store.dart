import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud persistence helpers for NOVARYX-AI.
/// Database rows hold metadata; large media files are uploaded to private Storage.
class NovaryxCloudStore {
  NovaryxCloudStore._();

  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _userId => _client.auth.currentUser?.id;

  static Future<String?> createOrGetLatestConversation() async {
    final userId = _userId;
    if (userId == null) return null;

    final existing = await _client
        .from('chat_conversations')
        .select('id')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(1);

    if (existing is List && existing.isNotEmpty) {
      return existing.first['id']?.toString();
    }

    final created = await _client
        .from('chat_conversations')
        .insert({'user_id': userId, 'title': 'NOVARYX Chat'})
        .select('id')
        .single();
    return created['id']?.toString();
  }

  static Future<List<Map<String, dynamic>>> loadChatMessages(
      String conversationId) async {
    final rows = await _client
        .from('chat_messages')
        .select('role,content,created_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .limit(500);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  static Future<void> saveChatMessage({
    required String conversationId,
    required String role,
    required String content,
    String? model,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    await _client.from('chat_messages').insert({
      'conversation_id': conversationId,
      'user_id': userId,
      'role': role,
      'content': content,
      'model': model,
    });
    await _client.from('chat_conversations').update({
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'title': content.length > 48 ? '${content.substring(0, 48)}…' : content,
    }).eq('id', conversationId).eq('user_id', userId);
  }

  /// Downloads a provider result and copies it into this user's private bucket.
  /// If a provider URL cannot be fetched, metadata still records the source URL.
  static Future<Map<String, dynamic>?> archiveGeneratedMedia({
    required String kind,
    required String prompt,
    required String sourceUrl,
    String? model,
    String? provider,
    String? providerJobId,
  }) async {
    final userId = _userId;
    if (userId == null) return null;

    final assetId = DateTime.now().microsecondsSinceEpoch.toString();
    String? bucketPath;
    String? mimeType;
    int? sizeBytes;
    String? archiveError;

    try {
      final uri = Uri.parse(sourceUrl);
      if (uri.scheme != 'https' && uri.scheme != 'http') {
        throw const FormatException('Unsupported media URL');
      }
      final response = await http.get(uri).timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Provider media download returned HTTP ${response.statusCode}');
      }
      final bytes = Uint8List.fromList(response.bodyBytes);
      if (bytes.isEmpty) throw Exception('Downloaded media was empty');
      if (bytes.length > 500 * 1024 * 1024) {
        throw Exception('Media exceeds the 500 MB storage limit');
      }
      mimeType = response.headers['content-type']?.split(';').first;
      final extension = _extensionFor(kind, mimeType, uri.path);
      bucketPath = '$userId/${kind}_${assetId}.$extension';
      await _client.storage.from('user-assets').uploadBinary(
        bucketPath,
        bytes,
        fileOptions: FileOptions(
          contentType: mimeType ?? _mimeFor(kind),
          upsert: false,
        ),
      );
      sizeBytes = bytes.length;
    } catch (error) {
      archiveError = error.toString();
    }

    final row = await _client.from('user_assets').insert({
      'user_id': userId,
      'asset_type': _assetTypeFor(kind),
      'bucket_id': 'user-assets',
      'file_path': bucketPath ?? sourceUrl,
      'original_filename': bucketPath?.split('/').last,
      'mime_type': mimeType ?? _mimeFor(kind),
      'size_bytes': sizeBytes,
      'prompt': prompt,
      'provider': provider ?? 'kie.ai',
      'provider_job_id': providerJobId,
      'status': bucketPath == null ? 'failed' : 'ready',
      'metadata': {
        'source_url': sourceUrl,
        if (model != null) 'model': model,
        if (archiveError != null) 'archive_error': archiveError,
      },
    }).select().single();

    return Map<String, dynamic>.from(row);
  }

  static String _assetTypeFor(String kind) {
    switch (kind.toLowerCase()) {
      case 'image': return 'image';
      case 'music': return 'music';
      case 'video': return 'video';
      case 'audio': return 'audio';
      case 'document': return 'document';
      default: return 'other';
    }
  }

  static String _mimeFor(String kind) {
    switch (kind.toLowerCase()) {
      case 'image': return 'image/jpeg';
      case 'music':
      case 'audio': return 'audio/mpeg';
      case 'video': return 'video/mp4';
      default: return 'application/octet-stream';
    }
  }

  static String _extensionFor(String kind, String? mime, String urlPath) {
    final pathExtension = urlPath.split('.').last.toLowerCase();
    if (pathExtension.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(pathExtension)) {
      return pathExtension;
    }
    switch (mime?.toLowerCase()) {
      case 'image/png': return 'png';
      case 'image/webp': return 'webp';
      case 'image/gif': return 'gif';
      case 'video/webm': return 'webm';
      case 'audio/wav':
      case 'audio/x-wav': return 'wav';
      case 'audio/mp4': return 'm4a';
      case 'audio/mpeg': return 'mp3';
      case 'video/mp4': return 'mp4';
      default:
        switch (kind.toLowerCase()) {
          case 'image': return 'jpg';
          case 'music':
          case 'audio': return 'mp3';
          case 'video': return 'mp4';
          default: return 'bin';
        }
    }
  }
}
