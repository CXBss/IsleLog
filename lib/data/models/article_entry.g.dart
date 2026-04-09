// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'article_entry.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetArticleEntryCollection on Isar {
  IsarCollection<ArticleEntry> get articleEntrys => this.collection();
}

const ArticleEntrySchema = CollectionSchema(
  name: r'ArticleEntry',
  id: 6345156157650959092,
  properties: {
    r'articleName': PropertySchema(
      id: 0,
      name: r'articleName',
      type: IsarType.string,
    ),
    r'attachmentsJson': PropertySchema(
      id: 1,
      name: r'attachmentsJson',
      type: IsarType.stringList,
    ),
    r'conflictRemoteContent': PropertySchema(
      id: 2,
      name: r'conflictRemoteContent',
      type: IsarType.string,
    ),
    r'conflictRemoteTitle': PropertySchema(
      id: 3,
      name: r'conflictRemoteTitle',
      type: IsarType.string,
    ),
    r'content': PropertySchema(
      id: 4,
      name: r'content',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 5,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'folderName': PropertySchema(
      id: 6,
      name: r'folderName',
      type: IsarType.string,
    ),
    r'isArchived': PropertySchema(
      id: 7,
      name: r'isArchived',
      type: IsarType.bool,
    ),
    r'isDeleted': PropertySchema(
      id: 8,
      name: r'isDeleted',
      type: IsarType.bool,
    ),
    r'isPinned': PropertySchema(
      id: 9,
      name: r'isPinned',
      type: IsarType.bool,
    ),
    r'lastSyncAt': PropertySchema(
      id: 10,
      name: r'lastSyncAt',
      type: IsarType.dateTime,
    ),
    r'localFolderId': PropertySchema(
      id: 11,
      name: r'localFolderId',
      type: IsarType.long,
    ),
    r'syncStatus': PropertySchema(
      id: 12,
      name: r'syncStatus',
      type: IsarType.byte,
      enumMap: _ArticleEntrysyncStatusEnumValueMap,
    ),
    r'title': PropertySchema(
      id: 13,
      name: r'title',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 14,
      name: r'updatedAt',
      type: IsarType.dateTime,
    ),
    r'visibility': PropertySchema(
      id: 15,
      name: r'visibility',
      type: IsarType.string,
    )
  },
  estimateSize: _articleEntryEstimateSize,
  serialize: _articleEntrySerialize,
  deserialize: _articleEntryDeserialize,
  deserializeProp: _articleEntryDeserializeProp,
  idName: r'id',
  indexes: {
    r'articleName': IndexSchema(
      id: 8858027180363883350,
      name: r'articleName',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'articleName',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'createdAt': IndexSchema(
      id: -3433535483987302584,
      name: r'createdAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'createdAt',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _articleEntryGetId,
  getLinks: _articleEntryGetLinks,
  attach: _articleEntryAttach,
  version: '3.1.0+1',
);

int _articleEntryEstimateSize(
  ArticleEntry object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.articleName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.attachmentsJson.length * 3;
  {
    for (var i = 0; i < object.attachmentsJson.length; i++) {
      final value = object.attachmentsJson[i];
      bytesCount += value.length * 3;
    }
  }
  {
    final value = object.conflictRemoteContent;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.conflictRemoteTitle;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.content.length * 3;
  {
    final value = object.folderName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.title.length * 3;
  bytesCount += 3 + object.visibility.length * 3;
  return bytesCount;
}

void _articleEntrySerialize(
  ArticleEntry object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.articleName);
  writer.writeStringList(offsets[1], object.attachmentsJson);
  writer.writeString(offsets[2], object.conflictRemoteContent);
  writer.writeString(offsets[3], object.conflictRemoteTitle);
  writer.writeString(offsets[4], object.content);
  writer.writeDateTime(offsets[5], object.createdAt);
  writer.writeString(offsets[6], object.folderName);
  writer.writeBool(offsets[7], object.isArchived);
  writer.writeBool(offsets[8], object.isDeleted);
  writer.writeBool(offsets[9], object.isPinned);
  writer.writeDateTime(offsets[10], object.lastSyncAt);
  writer.writeLong(offsets[11], object.localFolderId);
  writer.writeByte(offsets[12], object.syncStatus.index);
  writer.writeString(offsets[13], object.title);
  writer.writeDateTime(offsets[14], object.updatedAt);
  writer.writeString(offsets[15], object.visibility);
}

ArticleEntry _articleEntryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ArticleEntry();
  object.articleName = reader.readStringOrNull(offsets[0]);
  object.attachmentsJson = reader.readStringList(offsets[1]) ?? [];
  object.conflictRemoteContent = reader.readStringOrNull(offsets[2]);
  object.conflictRemoteTitle = reader.readStringOrNull(offsets[3]);
  object.content = reader.readString(offsets[4]);
  object.createdAt = reader.readDateTime(offsets[5]);
  object.folderName = reader.readStringOrNull(offsets[6]);
  object.id = id;
  object.isArchived = reader.readBool(offsets[7]);
  object.isDeleted = reader.readBool(offsets[8]);
  object.isPinned = reader.readBool(offsets[9]);
  object.lastSyncAt = reader.readDateTimeOrNull(offsets[10]);
  object.localFolderId = reader.readLongOrNull(offsets[11]);
  object.syncStatus =
      _ArticleEntrysyncStatusValueEnumMap[reader.readByteOrNull(offsets[12])] ??
          SyncStatus.pending;
  object.title = reader.readString(offsets[13]);
  object.updatedAt = reader.readDateTime(offsets[14]);
  object.visibility = reader.readString(offsets[15]);
  return object;
}

P _articleEntryDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringList(offset) ?? []) as P;
    case 2:
      return (reader.readStringOrNull(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readDateTime(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readBool(offset)) as P;
    case 8:
      return (reader.readBool(offset)) as P;
    case 9:
      return (reader.readBool(offset)) as P;
    case 10:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 11:
      return (reader.readLongOrNull(offset)) as P;
    case 12:
      return (_ArticleEntrysyncStatusValueEnumMap[
              reader.readByteOrNull(offset)] ??
          SyncStatus.pending) as P;
    case 13:
      return (reader.readString(offset)) as P;
    case 14:
      return (reader.readDateTime(offset)) as P;
    case 15:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _ArticleEntrysyncStatusEnumValueMap = {
  'pending': 0,
  'synced': 1,
  'conflict': 2,
};
const _ArticleEntrysyncStatusValueEnumMap = {
  0: SyncStatus.pending,
  1: SyncStatus.synced,
  2: SyncStatus.conflict,
};

Id _articleEntryGetId(ArticleEntry object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _articleEntryGetLinks(ArticleEntry object) {
  return [];
}

void _articleEntryAttach(
    IsarCollection<dynamic> col, Id id, ArticleEntry object) {
  object.id = id;
}

extension ArticleEntryQueryWhereSort
    on QueryBuilder<ArticleEntry, ArticleEntry, QWhere> {
  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhere> anyCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'createdAt'),
      );
    });
  }
}

extension ArticleEntryQueryWhere
    on QueryBuilder<ArticleEntry, ArticleEntry, QWhereClause> {
  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause> idGreaterThan(
      Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause> idBetween(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause>
      articleNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'articleName',
        value: [null],
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause>
      articleNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'articleName',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause>
      articleNameEqualTo(String? articleName) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'articleName',
        value: [articleName],
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause>
      articleNameNotEqualTo(String? articleName) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'articleName',
              lower: [],
              upper: [articleName],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'articleName',
              lower: [articleName],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'articleName',
              lower: [articleName],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'articleName',
              lower: [],
              upper: [articleName],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause> createdAtEqualTo(
      DateTime createdAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'createdAt',
        value: [createdAt],
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause>
      createdAtNotEqualTo(DateTime createdAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [createdAt],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'createdAt',
              lower: [],
              upper: [createdAt],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause>
      createdAtGreaterThan(
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [createdAt],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause> createdAtLessThan(
    DateTime createdAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [],
        upper: [createdAt],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterWhereClause> createdAtBetween(
    DateTime lowerCreatedAt,
    DateTime upperCreatedAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'createdAt',
        lower: [lowerCreatedAt],
        includeLower: includeLower,
        upper: [upperCreatedAt],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ArticleEntryQueryFilter
    on QueryBuilder<ArticleEntry, ArticleEntry, QFilterCondition> {
  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'articleName',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'articleName',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'articleName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'articleName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'articleName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'articleName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'articleName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'articleName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'articleName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'articleName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'articleName',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      articleNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'articleName',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attachmentsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'attachmentsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'attachmentsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'attachmentsJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'attachmentsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'attachmentsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'attachmentsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'attachmentsJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'attachmentsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'attachmentsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attachmentsJson',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attachmentsJson',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attachmentsJson',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attachmentsJson',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attachmentsJson',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      attachmentsJsonLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'attachmentsJson',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'conflictRemoteContent',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'conflictRemoteContent',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'conflictRemoteContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'conflictRemoteContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'conflictRemoteContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'conflictRemoteContent',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'conflictRemoteContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'conflictRemoteContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'conflictRemoteContent',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'conflictRemoteContent',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'conflictRemoteContent',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteContentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'conflictRemoteContent',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'conflictRemoteTitle',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'conflictRemoteTitle',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'conflictRemoteTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'conflictRemoteTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'conflictRemoteTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'conflictRemoteTitle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'conflictRemoteTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'conflictRemoteTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'conflictRemoteTitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'conflictRemoteTitle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'conflictRemoteTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      conflictRemoteTitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'conflictRemoteTitle',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'content',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'content',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'content',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      contentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'content',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'folderName',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'folderName',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'folderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'folderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'folderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'folderName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'folderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'folderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'folderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'folderName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'folderName',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      folderNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'folderName',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> idBetween(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      isArchivedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isArchived',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      isDeletedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isDeleted',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      isPinnedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isPinned',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      lastSyncAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastSyncAt',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      lastSyncAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastSyncAt',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      lastSyncAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      localFolderIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'localFolderId',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      localFolderIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'localFolderId',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      localFolderIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localFolderId',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      localFolderIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'localFolderId',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      localFolderIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'localFolderId',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      localFolderIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'localFolderId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      syncStatusEqualTo(SyncStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> titleEqualTo(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> titleLessThan(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> titleBetween(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      titleStartsWith(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> titleEndsWith(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> titleContains(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition> titleMatches(
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
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

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'visibility',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'visibility',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'visibility',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'visibility',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'visibility',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'visibility',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'visibility',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'visibility',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'visibility',
        value: '',
      ));
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterFilterCondition>
      visibilityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'visibility',
        value: '',
      ));
    });
  }
}

extension ArticleEntryQueryObject
    on QueryBuilder<ArticleEntry, ArticleEntry, QFilterCondition> {}

extension ArticleEntryQueryLinks
    on QueryBuilder<ArticleEntry, ArticleEntry, QFilterCondition> {}

extension ArticleEntryQuerySortBy
    on QueryBuilder<ArticleEntry, ArticleEntry, QSortBy> {
  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByArticleName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'articleName', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByArticleNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'articleName', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByConflictRemoteContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'conflictRemoteContent', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByConflictRemoteContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'conflictRemoteContent', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByConflictRemoteTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'conflictRemoteTitle', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByConflictRemoteTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'conflictRemoteTitle', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByFolderName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'folderName', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByFolderNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'folderName', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByIsArchivedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByIsDeletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByIsPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPinned', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByIsPinnedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPinned', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByLocalFolderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localFolderId', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByLocalFolderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localFolderId', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> sortByVisibility() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'visibility', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      sortByVisibilityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'visibility', Sort.desc);
    });
  }
}

extension ArticleEntryQuerySortThenBy
    on QueryBuilder<ArticleEntry, ArticleEntry, QSortThenBy> {
  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByArticleName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'articleName', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByArticleNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'articleName', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByConflictRemoteContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'conflictRemoteContent', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByConflictRemoteContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'conflictRemoteContent', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByConflictRemoteTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'conflictRemoteTitle', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByConflictRemoteTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'conflictRemoteTitle', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByFolderName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'folderName', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByFolderNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'folderName', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByIsArchivedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isArchived', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByIsDeletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByIsPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPinned', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByIsPinnedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPinned', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByLocalFolderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localFolderId', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByLocalFolderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localFolderId', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy> thenByVisibility() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'visibility', Sort.asc);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QAfterSortBy>
      thenByVisibilityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'visibility', Sort.desc);
    });
  }
}

extension ArticleEntryQueryWhereDistinct
    on QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> {
  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByArticleName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'articleName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct>
      distinctByAttachmentsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'attachmentsJson');
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct>
      distinctByConflictRemoteContent({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'conflictRemoteContent',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct>
      distinctByConflictRemoteTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'conflictRemoteTitle',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByContent(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'content', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByFolderName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'folderName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByIsArchived() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isArchived');
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isDeleted');
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByIsPinned() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isPinned');
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncAt');
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct>
      distinctByLocalFolderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'localFolderId');
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncStatus');
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<ArticleEntry, ArticleEntry, QDistinct> distinctByVisibility(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'visibility', caseSensitive: caseSensitive);
    });
  }
}

extension ArticleEntryQueryProperty
    on QueryBuilder<ArticleEntry, ArticleEntry, QQueryProperty> {
  QueryBuilder<ArticleEntry, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ArticleEntry, String?, QQueryOperations> articleNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'articleName');
    });
  }

  QueryBuilder<ArticleEntry, List<String>, QQueryOperations>
      attachmentsJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'attachmentsJson');
    });
  }

  QueryBuilder<ArticleEntry, String?, QQueryOperations>
      conflictRemoteContentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'conflictRemoteContent');
    });
  }

  QueryBuilder<ArticleEntry, String?, QQueryOperations>
      conflictRemoteTitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'conflictRemoteTitle');
    });
  }

  QueryBuilder<ArticleEntry, String, QQueryOperations> contentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'content');
    });
  }

  QueryBuilder<ArticleEntry, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<ArticleEntry, String?, QQueryOperations> folderNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'folderName');
    });
  }

  QueryBuilder<ArticleEntry, bool, QQueryOperations> isArchivedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isArchived');
    });
  }

  QueryBuilder<ArticleEntry, bool, QQueryOperations> isDeletedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isDeleted');
    });
  }

  QueryBuilder<ArticleEntry, bool, QQueryOperations> isPinnedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isPinned');
    });
  }

  QueryBuilder<ArticleEntry, DateTime?, QQueryOperations> lastSyncAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncAt');
    });
  }

  QueryBuilder<ArticleEntry, int?, QQueryOperations> localFolderIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localFolderId');
    });
  }

  QueryBuilder<ArticleEntry, SyncStatus, QQueryOperations>
      syncStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncStatus');
    });
  }

  QueryBuilder<ArticleEntry, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<ArticleEntry, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<ArticleEntry, String, QQueryOperations> visibilityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'visibility');
    });
  }
}
