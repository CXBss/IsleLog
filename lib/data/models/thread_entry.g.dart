// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_entry.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetThreadEntryCollection on Isar {
  IsarCollection<ThreadEntry> get threadEntrys => this.collection();
}

const ThreadEntrySchema = CollectionSchema(
  name: r'ThreadEntry',
  id: -860543290537544165,
  properties: {
    r'createdAt': PropertySchema(
      id: 0,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'isDeleted': PropertySchema(
      id: 1,
      name: r'isDeleted',
      type: IsarType.bool,
    ),
    r'lastSyncAt': PropertySchema(
      id: 2,
      name: r'lastSyncAt',
      type: IsarType.dateTime,
    ),
    r'memberLocalIds': PropertySchema(
      id: 3,
      name: r'memberLocalIds',
      type: IsarType.longList,
    ),
    r'status': PropertySchema(
      id: 4,
      name: r'status',
      type: IsarType.byte,
      enumMap: _ThreadEntrystatusEnumValueMap,
    ),
    r'summary': PropertySchema(
      id: 5,
      name: r'summary',
      type: IsarType.string,
    ),
    r'summaryIsManual': PropertySchema(
      id: 6,
      name: r'summaryIsManual',
      type: IsarType.bool,
    ),
    r'summaryLocked': PropertySchema(
      id: 7,
      name: r'summaryLocked',
      type: IsarType.bool,
    ),
    r'syncStatus': PropertySchema(
      id: 8,
      name: r'syncStatus',
      type: IsarType.byte,
      enumMap: _ThreadEntrysyncStatusEnumValueMap,
    ),
    r'threadName': PropertySchema(
      id: 9,
      name: r'threadName',
      type: IsarType.string,
    ),
    r'title': PropertySchema(
      id: 10,
      name: r'title',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 11,
      name: r'updatedAt',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _threadEntryEstimateSize,
  serialize: _threadEntrySerialize,
  deserialize: _threadEntryDeserialize,
  deserializeProp: _threadEntryDeserializeProp,
  idName: r'id',
  indexes: {
    r'threadName': IndexSchema(
      id: 945108376913171267,
      name: r'threadName',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'threadName',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'memberLocalIds': IndexSchema(
      id: 3248473518503452900,
      name: r'memberLocalIds',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'memberLocalIds',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _threadEntryGetId,
  getLinks: _threadEntryGetLinks,
  attach: _threadEntryAttach,
  version: '3.1.0+1',
);

int _threadEntryEstimateSize(
  ThreadEntry object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.memberLocalIds.length * 8;
  bytesCount += 3 + object.summary.length * 3;
  {
    final value = object.threadName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _threadEntrySerialize(
  ThreadEntry object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.createdAt);
  writer.writeBool(offsets[1], object.isDeleted);
  writer.writeDateTime(offsets[2], object.lastSyncAt);
  writer.writeLongList(offsets[3], object.memberLocalIds);
  writer.writeByte(offsets[4], object.status.index);
  writer.writeString(offsets[5], object.summary);
  writer.writeBool(offsets[6], object.summaryIsManual);
  writer.writeBool(offsets[7], object.summaryLocked);
  writer.writeByte(offsets[8], object.syncStatus.index);
  writer.writeString(offsets[9], object.threadName);
  writer.writeString(offsets[10], object.title);
  writer.writeDateTime(offsets[11], object.updatedAt);
}

ThreadEntry _threadEntryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ThreadEntry();
  object.createdAt = reader.readDateTime(offsets[0]);
  object.id = id;
  object.isDeleted = reader.readBool(offsets[1]);
  object.lastSyncAt = reader.readDateTimeOrNull(offsets[2]);
  object.memberLocalIds = reader.readLongList(offsets[3]) ?? [];
  object.status =
      _ThreadEntrystatusValueEnumMap[reader.readByteOrNull(offsets[4])] ??
          ThreadStatus.active;
  object.summary = reader.readString(offsets[5]);
  object.summaryIsManual = reader.readBool(offsets[6]);
  object.summaryLocked = reader.readBool(offsets[7]);
  object.syncStatus =
      _ThreadEntrysyncStatusValueEnumMap[reader.readByteOrNull(offsets[8])] ??
          SyncStatus.pending;
  object.threadName = reader.readStringOrNull(offsets[9]);
  object.title = reader.readString(offsets[10]);
  object.updatedAt = reader.readDateTime(offsets[11]);
  return object;
}

P _threadEntryDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readBool(offset)) as P;
    case 2:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 3:
      return (reader.readLongList(offset) ?? []) as P;
    case 4:
      return (_ThreadEntrystatusValueEnumMap[reader.readByteOrNull(offset)] ??
          ThreadStatus.active) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readBool(offset)) as P;
    case 7:
      return (reader.readBool(offset)) as P;
    case 8:
      return (_ThreadEntrysyncStatusValueEnumMap[
              reader.readByteOrNull(offset)] ??
          SyncStatus.pending) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _ThreadEntrystatusEnumValueMap = {
  'active': 0,
  'resolved': 1,
};
const _ThreadEntrystatusValueEnumMap = {
  0: ThreadStatus.active,
  1: ThreadStatus.resolved,
};
const _ThreadEntrysyncStatusEnumValueMap = {
  'pending': 0,
  'synced': 1,
  'conflict': 2,
};
const _ThreadEntrysyncStatusValueEnumMap = {
  0: SyncStatus.pending,
  1: SyncStatus.synced,
  2: SyncStatus.conflict,
};

Id _threadEntryGetId(ThreadEntry object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _threadEntryGetLinks(ThreadEntry object) {
  return [];
}

void _threadEntryAttach(
    IsarCollection<dynamic> col, Id id, ThreadEntry object) {
  object.id = id;
}

extension ThreadEntryQueryWhereSort
    on QueryBuilder<ThreadEntry, ThreadEntry, QWhere> {
  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhere>
      anyMemberLocalIdsElement() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'memberLocalIds'),
      );
    });
  }
}

extension ThreadEntryQueryWhere
    on QueryBuilder<ThreadEntry, ThreadEntry, QWhereClause> {
  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause> threadNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'threadName',
        value: [null],
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause>
      threadNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'threadName',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause> threadNameEqualTo(
      String? threadName) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'threadName',
        value: [threadName],
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause>
      threadNameNotEqualTo(String? threadName) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'threadName',
              lower: [],
              upper: [threadName],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'threadName',
              lower: [threadName],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'threadName',
              lower: [threadName],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'threadName',
              lower: [],
              upper: [threadName],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause>
      memberLocalIdsElementEqualTo(int memberLocalIdsElement) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'memberLocalIds',
        value: [memberLocalIdsElement],
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause>
      memberLocalIdsElementNotEqualTo(int memberLocalIdsElement) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'memberLocalIds',
              lower: [],
              upper: [memberLocalIdsElement],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'memberLocalIds',
              lower: [memberLocalIdsElement],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'memberLocalIds',
              lower: [memberLocalIdsElement],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'memberLocalIds',
              lower: [],
              upper: [memberLocalIdsElement],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause>
      memberLocalIdsElementGreaterThan(
    int memberLocalIdsElement, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'memberLocalIds',
        lower: [memberLocalIdsElement],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause>
      memberLocalIdsElementLessThan(
    int memberLocalIdsElement, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'memberLocalIds',
        lower: [],
        upper: [memberLocalIdsElement],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterWhereClause>
      memberLocalIdsElementBetween(
    int lowerMemberLocalIdsElement,
    int upperMemberLocalIdsElement, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'memberLocalIds',
        lower: [lowerMemberLocalIdsElement],
        includeLower: includeLower,
        upper: [upperMemberLocalIdsElement],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ThreadEntryQueryFilter
    on QueryBuilder<ThreadEntry, ThreadEntry, QFilterCondition> {
  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      createdAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      createdAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      createdAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      isDeletedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isDeleted',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      lastSyncAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastSyncAt',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      lastSyncAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastSyncAt',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      lastSyncAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      lastSyncAtGreaterThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      lastSyncAtLessThan(
    DateTime? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      lastSyncAtBetween(
    DateTime? lower,
    DateTime? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastSyncAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'memberLocalIds',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsElementGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'memberLocalIds',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'memberLocalIds',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'memberLocalIds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'memberLocalIds',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'memberLocalIds',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'memberLocalIds',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'memberLocalIds',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'memberLocalIds',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      memberLocalIdsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'memberLocalIds',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> statusEqualTo(
      ThreadStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      statusGreaterThan(
    ThreadStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'status',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> statusLessThan(
    ThreadStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'status',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> statusBetween(
    ThreadStatus lower,
    ThreadStatus upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'status',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> summaryEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'summary',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      summaryGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'summary',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> summaryLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'summary',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> summaryBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'summary',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      summaryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'summary',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> summaryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'summary',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> summaryContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'summary',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> summaryMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'summary',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      summaryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'summary',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      summaryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'summary',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      summaryIsManualEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'summaryIsManual',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      summaryLockedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'summaryLocked',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      syncStatusEqualTo(SyncStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      syncStatusGreaterThan(
    SyncStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'syncStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      syncStatusLessThan(
    SyncStatus value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'syncStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      syncStatusBetween(
    SyncStatus lower,
    SyncStatus upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'syncStatus',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'threadName',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'threadName',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'threadName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'threadName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'threadName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'threadName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'threadName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'threadName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'threadName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'threadName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'threadName',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      threadNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'threadName',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> titleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      titleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> titleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> titleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'title',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> titleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> titleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      updatedAtGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      updatedAtLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterFilterCondition>
      updatedAtBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ThreadEntryQueryObject
    on QueryBuilder<ThreadEntry, ThreadEntry, QFilterCondition> {}

extension ThreadEntryQueryLinks
    on QueryBuilder<ThreadEntry, ThreadEntry, QFilterCondition> {}

extension ThreadEntryQuerySortBy
    on QueryBuilder<ThreadEntry, ThreadEntry, QSortBy> {
  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByIsDeletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortBySummary() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summary', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortBySummaryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summary', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortBySummaryIsManual() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summaryIsManual', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy>
      sortBySummaryIsManualDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summaryIsManual', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortBySummaryLocked() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summaryLocked', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy>
      sortBySummaryLockedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summaryLocked', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByThreadName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadName', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByThreadNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadName', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension ThreadEntryQuerySortThenBy
    on QueryBuilder<ThreadEntry, ThreadEntry, QSortThenBy> {
  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByIsDeletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenBySummary() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summary', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenBySummaryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summary', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenBySummaryIsManual() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summaryIsManual', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy>
      thenBySummaryIsManualDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summaryIsManual', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenBySummaryLocked() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summaryLocked', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy>
      thenBySummaryLockedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'summaryLocked', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByThreadName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadName', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByThreadNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadName', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension ThreadEntryQueryWhereDistinct
    on QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> {
  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isDeleted');
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncAt');
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctByMemberLocalIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'memberLocalIds');
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status');
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctBySummary(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'summary', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct>
      distinctBySummaryIsManual() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'summaryIsManual');
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctBySummaryLocked() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'summaryLocked');
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncStatus');
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctByThreadName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'threadName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ThreadEntry, ThreadEntry, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension ThreadEntryQueryProperty
    on QueryBuilder<ThreadEntry, ThreadEntry, QQueryProperty> {
  QueryBuilder<ThreadEntry, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ThreadEntry, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<ThreadEntry, bool, QQueryOperations> isDeletedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isDeleted');
    });
  }

  QueryBuilder<ThreadEntry, DateTime?, QQueryOperations> lastSyncAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncAt');
    });
  }

  QueryBuilder<ThreadEntry, List<int>, QQueryOperations>
      memberLocalIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'memberLocalIds');
    });
  }

  QueryBuilder<ThreadEntry, ThreadStatus, QQueryOperations> statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }

  QueryBuilder<ThreadEntry, String, QQueryOperations> summaryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'summary');
    });
  }

  QueryBuilder<ThreadEntry, bool, QQueryOperations> summaryIsManualProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'summaryIsManual');
    });
  }

  QueryBuilder<ThreadEntry, bool, QQueryOperations> summaryLockedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'summaryLocked');
    });
  }

  QueryBuilder<ThreadEntry, SyncStatus, QQueryOperations> syncStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncStatus');
    });
  }

  QueryBuilder<ThreadEntry, String?, QQueryOperations> threadNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'threadName');
    });
  }

  QueryBuilder<ThreadEntry, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<ThreadEntry, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
