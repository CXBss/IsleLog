// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folder_entry.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetFolderEntryCollection on Isar {
  IsarCollection<FolderEntry> get folderEntrys => this.collection();
}

const FolderEntrySchema = CollectionSchema(
  name: r'FolderEntry',
  id: 3858974989197916207,
  properties: {
    r'createdAt': PropertySchema(
      id: 0,
      name: r'createdAt',
      type: IsarType.dateTime,
    ),
    r'folderName': PropertySchema(
      id: 1,
      name: r'folderName',
      type: IsarType.string,
    ),
    r'isDeleted': PropertySchema(
      id: 2,
      name: r'isDeleted',
      type: IsarType.bool,
    ),
    r'lastSyncAt': PropertySchema(
      id: 3,
      name: r'lastSyncAt',
      type: IsarType.dateTime,
    ),
    r'localParentFolderId': PropertySchema(
      id: 4,
      name: r'localParentFolderId',
      type: IsarType.long,
    ),
    r'parentFolderName': PropertySchema(
      id: 5,
      name: r'parentFolderName',
      type: IsarType.string,
    ),
    r'syncStatus': PropertySchema(
      id: 6,
      name: r'syncStatus',
      type: IsarType.byte,
      enumMap: _FolderEntrysyncStatusEnumValueMap,
    ),
    r'title': PropertySchema(
      id: 7,
      name: r'title',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 8,
      name: r'updatedAt',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _folderEntryEstimateSize,
  serialize: _folderEntrySerialize,
  deserialize: _folderEntryDeserialize,
  deserializeProp: _folderEntryDeserializeProp,
  idName: r'id',
  indexes: {
    r'folderName': IndexSchema(
      id: -3660704699439078006,
      name: r'folderName',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'folderName',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _folderEntryGetId,
  getLinks: _folderEntryGetLinks,
  attach: _folderEntryAttach,
  version: '3.1.0+1',
);

int _folderEntryEstimateSize(
  FolderEntry object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.folderName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.parentFolderName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _folderEntrySerialize(
  FolderEntry object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDateTime(offsets[0], object.createdAt);
  writer.writeString(offsets[1], object.folderName);
  writer.writeBool(offsets[2], object.isDeleted);
  writer.writeDateTime(offsets[3], object.lastSyncAt);
  writer.writeLong(offsets[4], object.localParentFolderId);
  writer.writeString(offsets[5], object.parentFolderName);
  writer.writeByte(offsets[6], object.syncStatus.index);
  writer.writeString(offsets[7], object.title);
  writer.writeDateTime(offsets[8], object.updatedAt);
}

FolderEntry _folderEntryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = FolderEntry();
  object.createdAt = reader.readDateTime(offsets[0]);
  object.folderName = reader.readStringOrNull(offsets[1]);
  object.id = id;
  object.isDeleted = reader.readBool(offsets[2]);
  object.lastSyncAt = reader.readDateTimeOrNull(offsets[3]);
  object.localParentFolderId = reader.readLongOrNull(offsets[4]);
  object.parentFolderName = reader.readStringOrNull(offsets[5]);
  object.syncStatus =
      _FolderEntrysyncStatusValueEnumMap[reader.readByteOrNull(offsets[6])] ??
          SyncStatus.pending;
  object.title = reader.readString(offsets[7]);
  object.updatedAt = reader.readDateTime(offsets[8]);
  return object;
}

P _folderEntryDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDateTime(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readBool(offset)) as P;
    case 3:
      return (reader.readDateTimeOrNull(offset)) as P;
    case 4:
      return (reader.readLongOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (_FolderEntrysyncStatusValueEnumMap[
              reader.readByteOrNull(offset)] ??
          SyncStatus.pending) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

const _FolderEntrysyncStatusEnumValueMap = {
  'pending': 0,
  'synced': 1,
  'conflict': 2,
};
const _FolderEntrysyncStatusValueEnumMap = {
  0: SyncStatus.pending,
  1: SyncStatus.synced,
  2: SyncStatus.conflict,
};

Id _folderEntryGetId(FolderEntry object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _folderEntryGetLinks(FolderEntry object) {
  return [];
}

void _folderEntryAttach(
    IsarCollection<dynamic> col, Id id, FolderEntry object) {
  object.id = id;
}

extension FolderEntryQueryWhereSort
    on QueryBuilder<FolderEntry, FolderEntry, QWhere> {
  QueryBuilder<FolderEntry, FolderEntry, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension FolderEntryQueryWhere
    on QueryBuilder<FolderEntry, FolderEntry, QWhereClause> {
  QueryBuilder<FolderEntry, FolderEntry, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterWhereClause> idBetween(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterWhereClause> folderNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'folderName',
        value: [null],
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterWhereClause>
      folderNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'folderName',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterWhereClause> folderNameEqualTo(
      String? folderName) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'folderName',
        value: [folderName],
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterWhereClause>
      folderNameNotEqualTo(String? folderName) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'folderName',
              lower: [],
              upper: [folderName],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'folderName',
              lower: [folderName],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'folderName',
              lower: [folderName],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'folderName',
              lower: [],
              upper: [folderName],
              includeUpper: false,
            ));
      }
    });
  }
}

extension FolderEntryQueryFilter
    on QueryBuilder<FolderEntry, FolderEntry, QFilterCondition> {
  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      createdAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      folderNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'folderName',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      folderNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'folderName',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      folderNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'folderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      folderNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'folderName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      folderNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'folderName',
        value: '',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      folderNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'folderName',
        value: '',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> idBetween(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      isDeletedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isDeleted',
        value: value,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      lastSyncAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastSyncAt',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      lastSyncAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastSyncAt',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      lastSyncAtEqualTo(DateTime? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastSyncAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      localParentFolderIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'localParentFolderId',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      localParentFolderIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'localParentFolderId',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      localParentFolderIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'localParentFolderId',
        value: value,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      localParentFolderIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'localParentFolderId',
        value: value,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      localParentFolderIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'localParentFolderId',
        value: value,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      localParentFolderIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'localParentFolderId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'parentFolderName',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'parentFolderName',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'parentFolderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'parentFolderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'parentFolderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'parentFolderName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'parentFolderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'parentFolderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'parentFolderName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'parentFolderName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'parentFolderName',
        value: '',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      parentFolderNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'parentFolderName',
        value: '',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      syncStatusEqualTo(SyncStatus value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'syncStatus',
        value: value,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> titleEqualTo(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> titleLessThan(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> titleBetween(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> titleStartsWith(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> titleEndsWith(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> titleContains(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> titleMatches(
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
      updatedAtEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

  QueryBuilder<FolderEntry, FolderEntry, QAfterFilterCondition>
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

extension FolderEntryQueryObject
    on QueryBuilder<FolderEntry, FolderEntry, QFilterCondition> {}

extension FolderEntryQueryLinks
    on QueryBuilder<FolderEntry, FolderEntry, QFilterCondition> {}

extension FolderEntryQuerySortBy
    on QueryBuilder<FolderEntry, FolderEntry, QSortBy> {
  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByFolderName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'folderName', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByFolderNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'folderName', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByIsDeletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy>
      sortByLocalParentFolderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localParentFolderId', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy>
      sortByLocalParentFolderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localParentFolderId', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy>
      sortByParentFolderName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parentFolderName', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy>
      sortByParentFolderNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parentFolderName', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension FolderEntryQuerySortThenBy
    on QueryBuilder<FolderEntry, FolderEntry, QSortThenBy> {
  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByFolderName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'folderName', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByFolderNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'folderName', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByIsDeletedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isDeleted', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByLastSyncAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSyncAt', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy>
      thenByLocalParentFolderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localParentFolderId', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy>
      thenByLocalParentFolderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'localParentFolderId', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy>
      thenByParentFolderName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parentFolderName', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy>
      thenByParentFolderNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'parentFolderName', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenBySyncStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'syncStatus', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension FolderEntryQueryWhereDistinct
    on QueryBuilder<FolderEntry, FolderEntry, QDistinct> {
  QueryBuilder<FolderEntry, FolderEntry, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QDistinct> distinctByFolderName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'folderName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QDistinct> distinctByIsDeleted() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isDeleted');
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QDistinct> distinctByLastSyncAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSyncAt');
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QDistinct>
      distinctByLocalParentFolderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'localParentFolderId');
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QDistinct> distinctByParentFolderName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'parentFolderName',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QDistinct> distinctBySyncStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'syncStatus');
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FolderEntry, FolderEntry, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension FolderEntryQueryProperty
    on QueryBuilder<FolderEntry, FolderEntry, QQueryProperty> {
  QueryBuilder<FolderEntry, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<FolderEntry, DateTime, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<FolderEntry, String?, QQueryOperations> folderNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'folderName');
    });
  }

  QueryBuilder<FolderEntry, bool, QQueryOperations> isDeletedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isDeleted');
    });
  }

  QueryBuilder<FolderEntry, DateTime?, QQueryOperations> lastSyncAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSyncAt');
    });
  }

  QueryBuilder<FolderEntry, int?, QQueryOperations>
      localParentFolderIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'localParentFolderId');
    });
  }

  QueryBuilder<FolderEntry, String?, QQueryOperations>
      parentFolderNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'parentFolderName');
    });
  }

  QueryBuilder<FolderEntry, SyncStatus, QQueryOperations> syncStatusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'syncStatus');
    });
  }

  QueryBuilder<FolderEntry, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<FolderEntry, DateTime, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
