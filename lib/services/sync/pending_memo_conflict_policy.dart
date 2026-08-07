import 'package:flutter/foundation.dart';

import '../../data/models/memo_entry.dart';

enum PendingMemoDecision { alreadySynced, pushLocal, conflict }

void captureEditBaseline(MemoEntry memo) {
  memo.originalContent ??= memo.content;
}

void markMemoSynced(MemoEntry memo, {DateTime? syncedAt}) {
  memo
    ..syncStatus = SyncStatus.synced
    ..lastSyncAt = syncedAt ?? DateTime.now()
    ..originalContent = null
    ..conflictRemoteContent = null;
}

PendingMemoDecision decidePendingMemo(
  MemoEntry local,
  Map<String, dynamic> remote, {
  required bool archived,
}) {
  if (_memosMatch(local, remote, archived)) {
    return PendingMemoDecision.alreadySynced;
  }

  final remoteContent = remote['content'] as String? ?? '';
  if (local.originalContent != null && remoteContent == local.originalContent) {
    return PendingMemoDecision.pushLocal;
  }

  return PendingMemoDecision.conflict;
}

bool _memosMatch(MemoEntry local, Map<String, dynamic> remote, bool archived) {
  final remoteContent = remote['content'] as String? ?? '';
  if (local.content != remoteContent) return false;

  final remotePinned = remote['pinned'] as bool? ?? false;
  if (local.isPinned != remotePinned) return false;

  if (local.isArchived != archived) return false;

  final remoteLoc = remote['location'];
  if (remoteLoc is Map) {
    final remoteLatitude = (remoteLoc['latitude'] as num?)?.toDouble();
    final remoteLongitude = (remoteLoc['longitude'] as num?)?.toDouble();
    final remotePlaceholder = remoteLoc['placeholder'] as String?;
    if (remoteLatitude != null &&
        remoteLongitude != null &&
        !(remoteLatitude == 0.0 && remoteLongitude == 0.0)) {
      final expectedPlaceholder =
          (remotePlaceholder != null && remotePlaceholder.isNotEmpty)
          ? remotePlaceholder
          : null;
      if (local.location != expectedPlaceholder) return false;
      if (local.latitude != remoteLatitude) return false;
      if (local.longitude != remoteLongitude) return false;
    } else if (local.location != null ||
        local.latitude != null ||
        local.longitude != null) {
      return false;
    }
  } else if (local.location != null ||
      local.latitude != null ||
      local.longitude != null) {
    return false;
  }

  final remoteAttachments = remote['attachments'] as List<dynamic>? ?? [];
  final remoteNames = remoteAttachments
      .whereType<Map>()
      .map((attachment) => attachment['name'] as String? ?? '')
      .where((name) => name.isNotEmpty)
      .toSet();
  final localNames = local.attachments
      .where((attachment) => attachment.remoteResName != null)
      .map((attachment) => attachment.remoteResName!)
      .toSet();

  return setEquals(remoteNames, localNames);
}
