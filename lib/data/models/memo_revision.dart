/// Memo/文章编辑历史相关数据模型（内存用，不存 Isar）

class MemoRevision {
  final String name;
  final int version;
  final List<String> changedFields;
  final DateTime createTime;

  const MemoRevision({
    required this.name,
    required this.version,
    required this.changedFields,
    required this.createTime,
  });

  factory MemoRevision.fromJson(Map<String, dynamic> json) {
    return MemoRevision(
      name: json['name'] as String,
      version: json['version'] as int,
      changedFields: (json['changedFields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createTime: DateTime.parse(json['createTime'] as String),
    );
  }
}

class MemoRevisionDetail {
  final String name;
  final int version;
  final DateTime createTime;
  final List<RevisionFieldDetail> details;

  const MemoRevisionDetail({
    required this.name,
    required this.version,
    required this.createTime,
    required this.details,
  });

  factory MemoRevisionDetail.fromJson(Map<String, dynamic> json) {
    return MemoRevisionDetail(
      name: json['name'] as String,
      version: json['version'] as int,
      createTime: DateTime.parse(json['createTime'] as String),
      details: (json['details'] as List<dynamic>?)
              ?.map((e) =>
                  RevisionFieldDetail.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class RevisionFieldDetail {
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final List<DiffOp>? diff;

  const RevisionFieldDetail({
    required this.fieldName,
    this.oldValue,
    this.newValue,
    this.diff,
  });

  factory RevisionFieldDetail.fromJson(Map<String, dynamic> json) {
    List<DiffOp>? diff;
    if (json['diff'] != null) {
      diff = (json['diff'] as List<dynamic>)
          .map((e) => DiffOp.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return RevisionFieldDetail(
      fieldName: json['fieldName'] as String,
      oldValue: json['oldValue'] as String?,
      newValue: json['newValue'] as String?,
      diff: diff,
    );
  }
}

/// diff op：0=不变，1=新增，-1=删除
class DiffOp {
  final int op;
  final String text;

  const DiffOp({required this.op, required this.text});

  factory DiffOp.fromJson(Map<String, dynamic> json) {
    return DiffOp(
      op: json['op'] as int,
      text: json['text'] as String,
    );
  }
}
