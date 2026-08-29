import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// `regions/_index` 의 한 줄.
class RegionRef {
  const RegionRef({required this.code, required this.name});

  final String code;
  final String name;

  static RegionRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = (json['code'] ?? '').toString().trim();
    if (code.isEmpty) return null;
    final name = (json['name'] ?? '').toString().trim();
    return RegionRef(code: code, name: name.isEmpty ? code : name);
  }
}

/// `regions/<code>.complexes` 의 한 줄.
class ComplexRef {
  const ComplexRef({
    required this.complexId,
    required this.name,
    required this.host,
  });

  final String complexId;
  final String name;

  /// 스킴도 포트도 없는 호스트 이름. 앱이 여기서 `wss://<host>/janus-ws` 같은
  /// 주소를 조립한다.
  final String host;

  /// 목록에서 보여 줄 이름. 단지를 고르는 시점에는 아직 사용자가 누구인지도
  /// 모르므로, 지역 안 모든 단지의 서버 주소를 그대로 늘어놓지 않는다.
  String get maskedHost {
    final label = host.split('.').first;
    final dash = label.indexOf('-');
    final prefix = dash >= 0 ? label.substring(0, dash + 1) : '';
    final id = label.substring(prefix.length);
    if (id.length <= 4) return label;
    return '$prefix${id.substring(0, 4)}${'*' * (id.length - 4)}';
  }

  /// 한 줄이 망가졌다고 지역 전체 목록이 무너지지 않도록 null 을 돌려준다.
  static ComplexRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final complexId = (json['complexId'] ?? '').toString().trim();
    final host = (json['host'] ?? '').toString().trim();
    if (complexId.isEmpty || !isPlainHost(host)) return null;
    final name = (json['name'] ?? '').toString().trim();
    return ComplexRef(
      complexId: complexId,
      name: name.isEmpty ? complexId : name,
      host: host,
    );
  }

  /// 업로더가 스킴을 떼고 넣으므로, 스킴이 붙어 있다면 목록 데이터가 깨진 것이다.
  /// 그대로 두면 `wss://https://…` 같은 주소가 만들어져 한참 뒤에 이상하게
  /// 실패하므로 여기서 버린다.
  static bool isPlainHost(String host) {
    if (host.isEmpty) return false;
    if (host.contains('://') || host.contains('/') || host.contains(':')) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(host);
  }
}

class DirectoryException implements Exception {
  const DirectoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 단지 목록을 Firestore 에서 읽는다.
///
/// 단지가 몇 개든 문서는 둘뿐이다 — 지역 목록은 `regions/_index`, 그 지역의
/// 단지는 `regions/<code>`.
///
/// **매번 읽지 않는다.** 고른 단지는 기기에 저장해 두고, 등록·연결이 실패하거나
/// 사용자가 단지를 바꿀 때만 다시 읽는다. 푸시와 이 목록이 같은 Firebase
/// 프로젝트를 쓰므로, 시작할 때마다 읽으면 그쪽이 흔들릴 때 이미 등록된
/// 사용자까지 앱에 못 들어온다.
class ComplexDirectory {
  const ComplexDirectory();

  static const _collection = 'regions';
  static const _indexDoc = '_index';

  /// 이 목록은 `(default)` 가 아니라 **이름 있는** Firestore 데이터베이스에 있다.
  /// 프로젝트 기본 DB 는 Datastore 모드라 Firestore SDK 로는 아예 말이 통하지
  /// 않는다.
  static const databaseId = String.fromEnvironment(
    'FIRESTORE_DATABASE_ID',
    defaultValue: 'apartment-complex-identifier',
  );

  FirebaseFirestore get _firestore =>
      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: databaseId);

  Future<List<RegionRef>> regions() async {
    final snapshot = await _read(_indexDoc);
    final regions = (snapshot['regions'] as List? ?? const [])
        .map(RegionRef.fromJson)
        .whereType<RegionRef>()
        .toList(growable: false);
    if (regions.isEmpty) {
      throw const DirectoryException('등록 가능한 지역이 아직 없습니다.');
    }
    return regions;
  }

  Future<List<ComplexRef>> complexes(String regionCode) async {
    final snapshot = await _read(regionCode);
    final raw = (snapshot['complexes'] as List? ?? const []);
    final complexes =
        raw.map(ComplexRef.fromJson).whereType<ComplexRef>().toList(
              growable: false,
            );
    if (raw.length != complexes.length) {
      debugPrint('단지 목록에서 ${raw.length - complexes.length}개가 형식이 어긋나 제외됐습니다');
    }
    if (complexes.isEmpty) {
      throw const DirectoryException('이 지역에는 아직 단지가 없습니다.');
    }
    return complexes;
  }

  Future<Map<String, dynamic>> _read(String documentId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(documentId).get();
      final data = doc.data();
      if (!doc.exists || data == null) {
        throw DirectoryException('단지 목록을 찾을 수 없습니다 ($documentId).');
      }
      return data;
    } on FirebaseException catch (e) {
      throw DirectoryException('단지 목록을 받지 못했습니다 (${e.code}).');
    }
  }
}
