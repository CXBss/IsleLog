// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_suggestion_entry.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetThreadSuggestionEntryCollection on Isar {
  IsarCollection<ThreadSuggestionEntry> get threadSuggestionEntrys =>
      this.collection();
}

const ThreadSuggestionEntrySchema = CollectionSchema(
  name: r'ThreadSuggestionEntry',
  id: -1465889802200925933,
  properties: {
    r'confidence': PropertySchema(
      id: 0,
      name: r'confidence',
      type: IsarType.double,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'memoLocalId': PropertySchema(
      id: 2,
      name: r'memoLocalId',
      type: IsarType.long,
    ),
    r'reason': PropertySchema(
      id: 3,
      name: r'reason',
      type: IsarType.string,
    ),
    r'status': PropertySchema(
      id: 4,
      name: r'status',
      type: IsarType.byte,
      enumMap: _ThreadSuggestionEntrystatusEnumValueMap,
    ),
    r'suggestionName': PropertySchema(
      id: 5,
      name: r'suggestionName',
      type: IsarType.string,
    ),
    r'syncStatus': PropertySchema(
      id: 6,
      name: r'syncStatus',
      type: IsarType.byte,
      enumMap: _ThreadSuggestionEntrysyncStatusEnumValueMap,
    ),
    r'threadLocalId': PropertySchema(
      id: 7,
      name: r'threadLocalId',
      type: IsarType.long,
    )
  },
  estimateSize: _threadSuggestionEntryEstimateSize,
  serialize: _threadSuggestionEntrySerialize,
  deserialize: _threadSuggestionEntryDeserialize,
  deserializeProp: _threadSuggestionEntryDeserializeProp,
  idName: r'id',
  indexes: {
    r'suggestionName': IndexSchema(
      id: 221789157131523216,
      name: r'suggestionName',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'suggestionName',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'memoLocalId': IndexSchema(
      id: 244767808568810295,
      name: r'memoLocalId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'memoLocalId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _threadSuggestionEntryGetId,
  getLinks: _threadSuggestionEntryGetLinks,
  attach: _threadSuggestionEntryAttach,
  version: '3.1.0+1',
);

int _threadSuggestionEntryEstimateSize(
  ThreadSuggestionEntry object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.reason.length * 3;
  {
    final value = object.suggestionName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _threadSuggestionEntrySerialize(
  ThreadSuggestionEntry object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDouble(offsets[0], object.confidence);
  writer.writeDateTime(offsets[1], object.createdAt);
  writer.writeLong(offsets[2], object.memoLocalId);
  writer.writeString(offsets[3], object.reason);
  writer.writeByte(offsets[4], object.status.index);
  writer.writeString(offsets[5], object.suggestionName);
  writer.writeByte(offsets[6], object.syncStatus.index);
  writer.writeLong(offsets[7], object.threadLocalId);
}

ThreadSuggestionEntry _threadSuggestionEntryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ThreadSuggestionEntry();
  object.confidence = reader.readDouble(offsets[0]);
  object.createdAt = reader.readDateTime(offsets[1]);
  object.id = id;
  object.memoLocalId = reader.readLong(offsets[2]);
  object.reason = reader.readString(offsets[3]);
  object.status = _ThreadSuggestionEntrystatusValueEnumMap[
          reader.readByteOrNull(offsets[4])] ??
      SuggestionStatus.pending;
  object.suggestionName = reader.readStringOrNull(offsets[5]);
  object.syncStatus = _ThreadSuggestionEntrysyncStatusValueEnumMap[
          reader.readByteOrNull(offsets[6])] ??
      SyncStatus.pending;
  object.threadLocalId = reader.readLong(offsets[7]);
  return object;
}

P _threadSuggestionEntryDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDouble(offset)) as P;
    case 1:
      return (reader.readDateTime(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (_ThreadSuggestionEntrystatusValueEnumMap[
              reader.readByteOrNull(offset)] ??
          SuggestionStatus.pending) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (_ThreadSuggestionEntrysyncStatusValueEnumMap[
              reader.readByteOrNull(offset)] ??
          SyncStatus.pending) as P;
    case 7:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _ThreadSuggestionEntrystatusEnumValueMap = {
  'pending': 0,
  'accepted': 1,
  'dismissed': 2,
};
const _ThreadSuggestionEntrystatusValueEnumMap = {
  0: SuggestionStatus.pending,
  1: SuggestionStatus.accepted,
  2: SuggestionStatus.dismissed,
};
const _ThreadSuggestionEntrysyncStatusEnumValueMap = {
  'pending': 0,
  'synced': 1,
  'conflict': 2,
};
const _ThreadSuggestionEntrysyncStatusValueEnumMap = {
  0: SyncStatus.pending,
  1: SyncStatus.synced,
  2: SyncStatus.conflict,
};

Id _threadSuggestionEntryGetId(ThreadSuggestionEntry object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _threadSuggestionEntryGetLinks(
    ThreadSuggestionEntry object) {
  return [];
}

void _threadSuggestionEntryAttach(
    IsarCollection<dynamic> col, Id id, ThreadSuggestionEntry object) {
  object.id = id;
}

extension ThreadSuggestionEntryQueryWhereSort
    on QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QWhere> {
  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhere>
      anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhere>
      anyMemoLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'memoLocalId'),
      );
    });
  }
}

extension ThreadSuggestionEntryQueryWhere on QueryBuilder<ThreadSuggestionEntry,
    ThreadSuggestionEntry, QWhereClause> {
  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      idNotEqualTo(Id id) {
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      idBetween(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      suggestionNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'suggestionName',
        value: [null],
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      suggestionNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'suggestionName',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      suggestionNameEqualTo(String? suggestionName) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'suggestionName',
        value: [suggestionName],
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      suggestionNameNotEqualTo(String? suggestionName) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'suggestionName',
              lower: [],
              upper: [suggestionName],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'suggestionName',
              lower: [suggestionName],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'suggestionName',
              lower: [suggestionName],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'suggestionName',
              lower: [],
              upper: [suggestionName],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      memoLocalIdEqualTo(int memoLocalId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'memoLocalId',
        value: [memoLocalId],
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      memoLocalIdNotEqualTo(int memoLocalId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'memoLocalId',
              lower: [],
              upper: [memoLocalId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'memoLocalId',
              lower: [memoLocalId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'memoLocalId',
              lower: [memoLocalId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'memoLocalId',
              lower: [],
              upper: [memoLocalId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      memoLocalIdGreaterThan(
    int memoLocalId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'memoLocalId',
        lower: [memoLocalId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      memoLocalIdLessThan(
    int memoLocalId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'memoLocalId',
        lower: [],
        upper: [memoLocalId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterWhereClause>
      memoLocalIdBetween(
    int lowerMemoLocalId,
    int upperMemoLocalId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'memoLocalId',
        lower: [lowerMemoLocalId],
        includeLower: includeLower,
        upper: [upperMemoLocalId],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ThreadSuggestionEntryQueryFilter on QueryBuilder<
    ThreadSuggestionEntry, ThreadSuggestionEntry, QFilterCondition> {
  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> confidenceEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'confidence',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> confidenceGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'confidence',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> confidenceLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'confidence',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> confidenceBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'confidence',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> createdAtGreaterThan(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> createdAtLessThan(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> createdAtBetween(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> idLessThan(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> idBetween(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> memoLocalIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'memoLocalId',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> memoLocalIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'memoLocalId',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> memoLocalIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'memoLocalId',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> memoLocalIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'memoLocalId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> reasonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reason',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> reasonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'reason',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> reasonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'reason',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> reasonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'reason',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> reasonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'reason',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> reasonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'reason',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
          QAfterFilterCondition>
      reasonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'reason',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
          QAfterFilterCondition>
      reasonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'reason',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> reasonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reason',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> reasonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'reason',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> statusEqualTo(SuggestionStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> statusGreaterThan(
    SuggestionStatus value, {
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> statusLessThan(
    SuggestionStatus value, {
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> statusBetween(
    SuggestionStatus lower,
    SuggestionStatus upper, {
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'suggestionName',
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'suggestionName',
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'suggestionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'suggestionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'suggestionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'suggestionName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'suggestionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'suggestionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
          QAfterFilterCondition>
      suggestionNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'suggestionName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
          QAfterFilterCondition>
      suggestionNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'suggestionName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'suggestionName',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> suggestionNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'suggestionName',
        value: '',
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> syncStatusEqualTo(SyncStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> syncStatusGreaterThan(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> syncStatusLessThan(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> syncStatusBetween(
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

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> threadLocalIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'threadLocalId',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> threadLocalIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'threadLocalId',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> threadLocalIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'threadLocalId',
        value: value,
      ));
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry,
      QAfterFilterCondition> threadLocalIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'threadLocalId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ThreadSuggestionEntryQueryObject on QueryBuilder<
    ThreadSuggestionEntry, ThreadSuggestionEntry, QFilterCondition> {}

extension ThreadSuggestionEntryQueryLinks on QueryBuilder<ThreadSuggestionEntry,
    ThreadSuggestionEntry, QFilterCondition> {}

extension ThreadSuggestionEntryQuerySortBy
    on QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QSortBy> {
  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByConfidence() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confidence', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByConfidenceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confidence', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByMemoLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memoLocalId', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByMemoLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memoLocalId', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByReason() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reason', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByReasonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reason', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortBySuggestionName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'suggestionName', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortBySuggestionNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'suggestionName', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByThreadLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadLocalId', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      sortByThreadLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadLocalId', Sort.desc);
    });
  }
}

extension ThreadSuggestionEntryQuerySortThenBy
    on QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QSortThenBy> {
  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByConfidence() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confidence', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByConfidenceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'confidence', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByMemoLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memoLocalId', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByMemoLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'memoLocalId', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByReason() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reason', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByReasonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reason', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenBySuggestionName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'suggestionName', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenBySuggestionNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'suggestionName', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByThreadLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadLocalId', Sort.asc);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QAfterSortBy>
      thenByThreadLocalIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'threadLocalId', Sort.desc);
    });
  }
}

extension ThreadSuggestionEntryQueryWhereDistinct
    on QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QDistinct> {
  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QDistinct>
      distinctByConfidence() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'confidence');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QDistinct>
      distinctByMemoLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'memoLocalId');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QDistinct>
      distinctByReason({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'reason', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QDistinct>
      distinctByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QDistinct>
      distinctBySuggestionName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'suggestionName',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QDistinct>
      distinctBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncStatus');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, ThreadSuggestionEntry, QDistinct>
      distinctByThreadLocalId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'threadLocalId');
    });
  }
}

extension ThreadSuggestionEntryQueryProperty on QueryBuilder<
    ThreadSuggestionEntry, ThreadSuggestionEntry, QQueryProperty> {
  QueryBuilder<ThreadSuggestionEntry, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, double, QQueryOperations>
      confidenceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'confidence');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, DateTime, QQueryOperations>
      createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, int, QQueryOperations>
      memoLocalIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'memoLocalId');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, String, QQueryOperations>
      reasonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'reason');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, SuggestionStatus, QQueryOperations>
      statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, String?, QQueryOperations>
      suggestionNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'suggestionName');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, SyncStatus, QQueryOperations>
      syncStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncStatus');
    });
  }

  QueryBuilder<ThreadSuggestionEntry, int, QQueryOperations>
      threadLocalIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'threadLocalId');
    });
  }
}
