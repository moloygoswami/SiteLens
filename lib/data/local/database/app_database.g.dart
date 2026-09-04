// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SitesTable extends Sites with TableInfo<$SitesTable, SiteEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SitesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _siteCodeMeta =
      const VerificationMeta('siteCode');
  @override
  late final GeneratedColumn<String> siteCode = GeneratedColumn<String>(
      'site_code', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _addressMeta =
      const VerificationMeta('address');
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
      'address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _creatorIdMeta =
      const VerificationMeta('creatorId');
  @override
  late final GeneratedColumn<String> creatorId = GeneratedColumn<String>(
      'creator_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, siteCode, name, address, creatorId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sites';
  @override
  VerificationContext validateIntegrity(Insertable<SiteEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('site_code')) {
      context.handle(_siteCodeMeta,
          siteCode.isAcceptableOrUnknown(data['site_code']!, _siteCodeMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('address')) {
      context.handle(_addressMeta,
          address.isAcceptableOrUnknown(data['address']!, _addressMeta));
    }
    if (data.containsKey('creator_id')) {
      context.handle(_creatorIdMeta,
          creatorId.isAcceptableOrUnknown(data['creator_id']!, _creatorIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SiteEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SiteEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      siteCode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}site_code']),
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name']),
      address: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}address']),
      creatorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}creator_id']),
    );
  }

  @override
  $SitesTable createAlias(String alias) {
    return $SitesTable(attachedDatabase, alias);
  }
}

class SiteEntry extends DataClass implements Insertable<SiteEntry> {
  final String id;
  final String? siteCode;
  final String? name;
  final String? address;
  final String? creatorId;
  const SiteEntry(
      {required this.id,
      this.siteCode,
      this.name,
      this.address,
      this.creatorId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || siteCode != null) {
      map['site_code'] = Variable<String>(siteCode);
    }
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || address != null) {
      map['address'] = Variable<String>(address);
    }
    if (!nullToAbsent || creatorId != null) {
      map['creator_id'] = Variable<String>(creatorId);
    }
    return map;
  }

  SitesCompanion toCompanion(bool nullToAbsent) {
    return SitesCompanion(
      id: Value(id),
      siteCode: siteCode == null && nullToAbsent
          ? const Value.absent()
          : Value(siteCode),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      address: address == null && nullToAbsent
          ? const Value.absent()
          : Value(address),
      creatorId: creatorId == null && nullToAbsent
          ? const Value.absent()
          : Value(creatorId),
    );
  }

  factory SiteEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SiteEntry(
      id: serializer.fromJson<String>(json['id']),
      siteCode: serializer.fromJson<String?>(json['siteCode']),
      name: serializer.fromJson<String?>(json['name']),
      address: serializer.fromJson<String?>(json['address']),
      creatorId: serializer.fromJson<String?>(json['creatorId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'siteCode': serializer.toJson<String?>(siteCode),
      'name': serializer.toJson<String?>(name),
      'address': serializer.toJson<String?>(address),
      'creatorId': serializer.toJson<String?>(creatorId),
    };
  }

  SiteEntry copyWith(
          {String? id,
          Value<String?> siteCode = const Value.absent(),
          Value<String?> name = const Value.absent(),
          Value<String?> address = const Value.absent(),
          Value<String?> creatorId = const Value.absent()}) =>
      SiteEntry(
        id: id ?? this.id,
        siteCode: siteCode.present ? siteCode.value : this.siteCode,
        name: name.present ? name.value : this.name,
        address: address.present ? address.value : this.address,
        creatorId: creatorId.present ? creatorId.value : this.creatorId,
      );
  SiteEntry copyWithCompanion(SitesCompanion data) {
    return SiteEntry(
      id: data.id.present ? data.id.value : this.id,
      siteCode: data.siteCode.present ? data.siteCode.value : this.siteCode,
      name: data.name.present ? data.name.value : this.name,
      address: data.address.present ? data.address.value : this.address,
      creatorId: data.creatorId.present ? data.creatorId.value : this.creatorId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SiteEntry(')
          ..write('id: $id, ')
          ..write('siteCode: $siteCode, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('creatorId: $creatorId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, siteCode, name, address, creatorId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SiteEntry &&
          other.id == this.id &&
          other.siteCode == this.siteCode &&
          other.name == this.name &&
          other.address == this.address &&
          other.creatorId == this.creatorId);
}

class SitesCompanion extends UpdateCompanion<SiteEntry> {
  final Value<String> id;
  final Value<String?> siteCode;
  final Value<String?> name;
  final Value<String?> address;
  final Value<String?> creatorId;
  final Value<int> rowid;
  const SitesCompanion({
    this.id = const Value.absent(),
    this.siteCode = const Value.absent(),
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.creatorId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SitesCompanion.insert({
    required String id,
    this.siteCode = const Value.absent(),
    this.name = const Value.absent(),
    this.address = const Value.absent(),
    this.creatorId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<SiteEntry> custom({
    Expression<String>? id,
    Expression<String>? siteCode,
    Expression<String>? name,
    Expression<String>? address,
    Expression<String>? creatorId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (siteCode != null) 'site_code': siteCode,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (creatorId != null) 'creator_id': creatorId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SitesCompanion copyWith(
      {Value<String>? id,
      Value<String?>? siteCode,
      Value<String?>? name,
      Value<String?>? address,
      Value<String?>? creatorId,
      Value<int>? rowid}) {
    return SitesCompanion(
      id: id ?? this.id,
      siteCode: siteCode ?? this.siteCode,
      name: name ?? this.name,
      address: address ?? this.address,
      creatorId: creatorId ?? this.creatorId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (siteCode.present) {
      map['site_code'] = Variable<String>(siteCode.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (creatorId.present) {
      map['creator_id'] = Variable<String>(creatorId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SitesCompanion(')
          ..write('id: $id, ')
          ..write('siteCode: $siteCode, ')
          ..write('name: $name, ')
          ..write('address: $address, ')
          ..write('creatorId: $creatorId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaTable extends Media with TableInfo<$MediaTable, MediaEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _siteIdMeta = const VerificationMeta('siteId');
  @override
  late final GeneratedColumn<String> siteId = GeneratedColumn<String>(
      'site_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sites (id)'));
  static const VerificationMeta _originalUriMeta =
      const VerificationMeta('originalUri');
  @override
  late final GeneratedColumn<String> originalUri = GeneratedColumn<String>(
      'original_uri', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _uriMeta = const VerificationMeta('uri');
  @override
  late final GeneratedColumn<String> uri = GeneratedColumn<String>(
      'uri', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _thumbUriMeta =
      const VerificationMeta('thumbUri');
  @override
  late final GeneratedColumn<String> thumbUri = GeneratedColumn<String>(
      'thumb_uri', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
      'lat', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
      'lon', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _accuracyMMeta =
      const VerificationMeta('accuracyM');
  @override
  late final GeneratedColumn<double> accuracyM = GeneratedColumn<double>(
      'accuracy_m', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _lowAccuracyMeta =
      const VerificationMeta('lowAccuracy');
  @override
  late final GeneratedColumn<int> lowAccuracy = GeneratedColumn<int>(
      'low_accuracy', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _altitudeMMeta =
      const VerificationMeta('altitudeM');
  @override
  late final GeneratedColumn<double> altitudeM = GeneratedColumn<double>(
      'altitude_m', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _activityTagMeta =
      const VerificationMeta('activityTag');
  @override
  late final GeneratedColumn<String> activityTag = GeneratedColumn<String>(
      'activity_tag', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _observationTypeMeta =
      const VerificationMeta('observationType');
  @override
  late final GeneratedColumn<String> observationType = GeneratedColumn<String>(
      'observation_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _linkedMediaIdMeta =
      const VerificationMeta('linkedMediaId');
  @override
  late final GeneratedColumn<String> linkedMediaId = GeneratedColumn<String>(
      'linked_media_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES media (id)'));
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _capturedAtMeta =
      const VerificationMeta('capturedAt');
  @override
  late final GeneratedColumn<String> capturedAt = GeneratedColumn<String>(
      'captured_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sha256HashMeta =
      const VerificationMeta('sha256Hash');
  @override
  late final GeneratedColumn<String> sha256Hash = GeneratedColumn<String>(
      'sha256_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _evidenceSha256HashMeta =
      const VerificationMeta('evidenceSha256Hash');
  @override
  late final GeneratedColumn<String> evidenceSha256Hash =
      GeneratedColumn<String>('evidence_sha256_hash', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _capturedAddressMeta =
      const VerificationMeta('capturedAddress');
  @override
  late final GeneratedColumn<String> capturedAddress = GeneratedColumn<String>(
      'captured_address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _creatorIdMeta =
      const VerificationMeta('creatorId');
  @override
  late final GeneratedColumn<String> creatorId = GeneratedColumn<String>(
      'creator_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<int> synced = GeneratedColumn<int>(
      'synced', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isDeletedMeta =
      const VerificationMeta('isDeleted');
  @override
  late final GeneratedColumn<int> isDeleted = GeneratedColumn<int>(
      'is_deleted', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        siteId,
        originalUri,
        uri,
        thumbUri,
        type,
        lat,
        lon,
        accuracyM,
        lowAccuracy,
        altitudeM,
        activityTag,
        observationType,
        linkedMediaId,
        note,
        capturedAt,
        sha256Hash,
        evidenceSha256Hash,
        capturedAddress,
        creatorId,
        synced,
        isDeleted
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media';
  @override
  VerificationContext validateIntegrity(Insertable<MediaEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('site_id')) {
      context.handle(_siteIdMeta,
          siteId.isAcceptableOrUnknown(data['site_id']!, _siteIdMeta));
    }
    if (data.containsKey('original_uri')) {
      context.handle(
          _originalUriMeta,
          originalUri.isAcceptableOrUnknown(
              data['original_uri']!, _originalUriMeta));
    }
    if (data.containsKey('uri')) {
      context.handle(
          _uriMeta, uri.isAcceptableOrUnknown(data['uri']!, _uriMeta));
    } else if (isInserting) {
      context.missing(_uriMeta);
    }
    if (data.containsKey('thumb_uri')) {
      context.handle(_thumbUriMeta,
          thumbUri.isAcceptableOrUnknown(data['thumb_uri']!, _thumbUriMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('lat')) {
      context.handle(
          _latMeta, lat.isAcceptableOrUnknown(data['lat']!, _latMeta));
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
          _lonMeta, lon.isAcceptableOrUnknown(data['lon']!, _lonMeta));
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('accuracy_m')) {
      context.handle(_accuracyMMeta,
          accuracyM.isAcceptableOrUnknown(data['accuracy_m']!, _accuracyMMeta));
    }
    if (data.containsKey('low_accuracy')) {
      context.handle(
          _lowAccuracyMeta,
          lowAccuracy.isAcceptableOrUnknown(
              data['low_accuracy']!, _lowAccuracyMeta));
    }
    if (data.containsKey('altitude_m')) {
      context.handle(_altitudeMMeta,
          altitudeM.isAcceptableOrUnknown(data['altitude_m']!, _altitudeMMeta));
    }
    if (data.containsKey('activity_tag')) {
      context.handle(
          _activityTagMeta,
          activityTag.isAcceptableOrUnknown(
              data['activity_tag']!, _activityTagMeta));
    }
    if (data.containsKey('observation_type')) {
      context.handle(
          _observationTypeMeta,
          observationType.isAcceptableOrUnknown(
              data['observation_type']!, _observationTypeMeta));
    }
    if (data.containsKey('linked_media_id')) {
      context.handle(
          _linkedMediaIdMeta,
          linkedMediaId.isAcceptableOrUnknown(
              data['linked_media_id']!, _linkedMediaIdMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('captured_at')) {
      context.handle(
          _capturedAtMeta,
          capturedAt.isAcceptableOrUnknown(
              data['captured_at']!, _capturedAtMeta));
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('sha256_hash')) {
      context.handle(
          _sha256HashMeta,
          sha256Hash.isAcceptableOrUnknown(
              data['sha256_hash']!, _sha256HashMeta));
    }
    if (data.containsKey('evidence_sha256_hash')) {
      context.handle(
          _evidenceSha256HashMeta,
          evidenceSha256Hash.isAcceptableOrUnknown(
              data['evidence_sha256_hash']!, _evidenceSha256HashMeta));
    }
    if (data.containsKey('captured_address')) {
      context.handle(
          _capturedAddressMeta,
          capturedAddress.isAcceptableOrUnknown(
              data['captured_address']!, _capturedAddressMeta));
    }
    if (data.containsKey('creator_id')) {
      context.handle(_creatorIdMeta,
          creatorId.isAcceptableOrUnknown(data['creator_id']!, _creatorIdMeta));
    }
    if (data.containsKey('synced')) {
      context.handle(_syncedMeta,
          synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta));
    }
    if (data.containsKey('is_deleted')) {
      context.handle(_isDeletedMeta,
          isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      siteId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}site_id']),
      originalUri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}original_uri'])!,
      uri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uri'])!,
      thumbUri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumb_uri']),
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type']),
      lat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lat'])!,
      lon: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}lon'])!,
      accuracyM: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}accuracy_m']),
      lowAccuracy: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}low_accuracy'])!,
      altitudeM: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}altitude_m']),
      activityTag: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}activity_tag']),
      observationType: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}observation_type']),
      linkedMediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}linked_media_id']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      capturedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}captured_at'])!,
      sha256Hash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sha256_hash']),
      evidenceSha256Hash: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}evidence_sha256_hash']),
      capturedAddress: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}captured_address']),
      creatorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}creator_id']),
      synced: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}synced'])!,
      isDeleted: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}is_deleted'])!,
    );
  }

  @override
  $MediaTable createAlias(String alias) {
    return $MediaTable(attachedDatabase, alias);
  }
}

class MediaEntry extends DataClass implements Insertable<MediaEntry> {
  final String id;
  final String? siteId;
  final String originalUri;
  final String uri;
  final String? thumbUri;
  final String? type;
  final double lat;
  final double lon;
  final double? accuracyM;
  final int lowAccuracy;
  final double? altitudeM;
  final String? activityTag;
  final String? observationType;
  final String? linkedMediaId;
  final String? note;
  final String capturedAt;
  final String? sha256Hash;
  final String? evidenceSha256Hash;
  final String? capturedAddress;
  final String? creatorId;
  final int synced;
  final int isDeleted;
  const MediaEntry(
      {required this.id,
      this.siteId,
      required this.originalUri,
      required this.uri,
      this.thumbUri,
      this.type,
      required this.lat,
      required this.lon,
      this.accuracyM,
      required this.lowAccuracy,
      this.altitudeM,
      this.activityTag,
      this.observationType,
      this.linkedMediaId,
      this.note,
      required this.capturedAt,
      this.sha256Hash,
      this.evidenceSha256Hash,
      this.capturedAddress,
      this.creatorId,
      required this.synced,
      required this.isDeleted});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || siteId != null) {
      map['site_id'] = Variable<String>(siteId);
    }
    map['original_uri'] = Variable<String>(originalUri);
    map['uri'] = Variable<String>(uri);
    if (!nullToAbsent || thumbUri != null) {
      map['thumb_uri'] = Variable<String>(thumbUri);
    }
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    if (!nullToAbsent || accuracyM != null) {
      map['accuracy_m'] = Variable<double>(accuracyM);
    }
    map['low_accuracy'] = Variable<int>(lowAccuracy);
    if (!nullToAbsent || altitudeM != null) {
      map['altitude_m'] = Variable<double>(altitudeM);
    }
    if (!nullToAbsent || activityTag != null) {
      map['activity_tag'] = Variable<String>(activityTag);
    }
    if (!nullToAbsent || observationType != null) {
      map['observation_type'] = Variable<String>(observationType);
    }
    if (!nullToAbsent || linkedMediaId != null) {
      map['linked_media_id'] = Variable<String>(linkedMediaId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['captured_at'] = Variable<String>(capturedAt);
    if (!nullToAbsent || sha256Hash != null) {
      map['sha256_hash'] = Variable<String>(sha256Hash);
    }
    if (!nullToAbsent || evidenceSha256Hash != null) {
      map['evidence_sha256_hash'] = Variable<String>(evidenceSha256Hash);
    }
    if (!nullToAbsent || capturedAddress != null) {
      map['captured_address'] = Variable<String>(capturedAddress);
    }
    if (!nullToAbsent || creatorId != null) {
      map['creator_id'] = Variable<String>(creatorId);
    }
    map['synced'] = Variable<int>(synced);
    map['is_deleted'] = Variable<int>(isDeleted);
    return map;
  }

  MediaCompanion toCompanion(bool nullToAbsent) {
    return MediaCompanion(
      id: Value(id),
      siteId:
          siteId == null && nullToAbsent ? const Value.absent() : Value(siteId),
      originalUri: Value(originalUri),
      uri: Value(uri),
      thumbUri: thumbUri == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbUri),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      lat: Value(lat),
      lon: Value(lon),
      accuracyM: accuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracyM),
      lowAccuracy: Value(lowAccuracy),
      altitudeM: altitudeM == null && nullToAbsent
          ? const Value.absent()
          : Value(altitudeM),
      activityTag: activityTag == null && nullToAbsent
          ? const Value.absent()
          : Value(activityTag),
      observationType: observationType == null && nullToAbsent
          ? const Value.absent()
          : Value(observationType),
      linkedMediaId: linkedMediaId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedMediaId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      capturedAt: Value(capturedAt),
      sha256Hash: sha256Hash == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256Hash),
      evidenceSha256Hash: evidenceSha256Hash == null && nullToAbsent
          ? const Value.absent()
          : Value(evidenceSha256Hash),
      capturedAddress: capturedAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(capturedAddress),
      creatorId: creatorId == null && nullToAbsent
          ? const Value.absent()
          : Value(creatorId),
      synced: Value(synced),
      isDeleted: Value(isDeleted),
    );
  }

  factory MediaEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaEntry(
      id: serializer.fromJson<String>(json['id']),
      siteId: serializer.fromJson<String?>(json['siteId']),
      originalUri: serializer.fromJson<String>(json['originalUri']),
      uri: serializer.fromJson<String>(json['uri']),
      thumbUri: serializer.fromJson<String?>(json['thumbUri']),
      type: serializer.fromJson<String?>(json['type']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      accuracyM: serializer.fromJson<double?>(json['accuracyM']),
      lowAccuracy: serializer.fromJson<int>(json['lowAccuracy']),
      altitudeM: serializer.fromJson<double?>(json['altitudeM']),
      activityTag: serializer.fromJson<String?>(json['activityTag']),
      observationType: serializer.fromJson<String?>(json['observationType']),
      linkedMediaId: serializer.fromJson<String?>(json['linkedMediaId']),
      note: serializer.fromJson<String?>(json['note']),
      capturedAt: serializer.fromJson<String>(json['capturedAt']),
      sha256Hash: serializer.fromJson<String?>(json['sha256Hash']),
      evidenceSha256Hash:
          serializer.fromJson<String?>(json['evidenceSha256Hash']),
      capturedAddress: serializer.fromJson<String?>(json['capturedAddress']),
      creatorId: serializer.fromJson<String?>(json['creatorId']),
      synced: serializer.fromJson<int>(json['synced']),
      isDeleted: serializer.fromJson<int>(json['isDeleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'siteId': serializer.toJson<String?>(siteId),
      'originalUri': serializer.toJson<String>(originalUri),
      'uri': serializer.toJson<String>(uri),
      'thumbUri': serializer.toJson<String?>(thumbUri),
      'type': serializer.toJson<String?>(type),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'accuracyM': serializer.toJson<double?>(accuracyM),
      'lowAccuracy': serializer.toJson<int>(lowAccuracy),
      'altitudeM': serializer.toJson<double?>(altitudeM),
      'activityTag': serializer.toJson<String?>(activityTag),
      'observationType': serializer.toJson<String?>(observationType),
      'linkedMediaId': serializer.toJson<String?>(linkedMediaId),
      'note': serializer.toJson<String?>(note),
      'capturedAt': serializer.toJson<String>(capturedAt),
      'sha256Hash': serializer.toJson<String?>(sha256Hash),
      'evidenceSha256Hash': serializer.toJson<String?>(evidenceSha256Hash),
      'capturedAddress': serializer.toJson<String?>(capturedAddress),
      'creatorId': serializer.toJson<String?>(creatorId),
      'synced': serializer.toJson<int>(synced),
      'isDeleted': serializer.toJson<int>(isDeleted),
    };
  }

  MediaEntry copyWith(
          {String? id,
          Value<String?> siteId = const Value.absent(),
          String? originalUri,
          String? uri,
          Value<String?> thumbUri = const Value.absent(),
          Value<String?> type = const Value.absent(),
          double? lat,
          double? lon,
          Value<double?> accuracyM = const Value.absent(),
          int? lowAccuracy,
          Value<double?> altitudeM = const Value.absent(),
          Value<String?> activityTag = const Value.absent(),
          Value<String?> observationType = const Value.absent(),
          Value<String?> linkedMediaId = const Value.absent(),
          Value<String?> note = const Value.absent(),
          String? capturedAt,
          Value<String?> sha256Hash = const Value.absent(),
          Value<String?> evidenceSha256Hash = const Value.absent(),
          Value<String?> capturedAddress = const Value.absent(),
          Value<String?> creatorId = const Value.absent(),
          int? synced,
          int? isDeleted}) =>
      MediaEntry(
        id: id ?? this.id,
        siteId: siteId.present ? siteId.value : this.siteId,
        originalUri: originalUri ?? this.originalUri,
        uri: uri ?? this.uri,
        thumbUri: thumbUri.present ? thumbUri.value : this.thumbUri,
        type: type.present ? type.value : this.type,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        accuracyM: accuracyM.present ? accuracyM.value : this.accuracyM,
        lowAccuracy: lowAccuracy ?? this.lowAccuracy,
        altitudeM: altitudeM.present ? altitudeM.value : this.altitudeM,
        activityTag: activityTag.present ? activityTag.value : this.activityTag,
        observationType: observationType.present
            ? observationType.value
            : this.observationType,
        linkedMediaId:
            linkedMediaId.present ? linkedMediaId.value : this.linkedMediaId,
        note: note.present ? note.value : this.note,
        capturedAt: capturedAt ?? this.capturedAt,
        sha256Hash: sha256Hash.present ? sha256Hash.value : this.sha256Hash,
        evidenceSha256Hash: evidenceSha256Hash.present
            ? evidenceSha256Hash.value
            : this.evidenceSha256Hash,
        capturedAddress: capturedAddress.present
            ? capturedAddress.value
            : this.capturedAddress,
        creatorId: creatorId.present ? creatorId.value : this.creatorId,
        synced: synced ?? this.synced,
        isDeleted: isDeleted ?? this.isDeleted,
      );
  MediaEntry copyWithCompanion(MediaCompanion data) {
    return MediaEntry(
      id: data.id.present ? data.id.value : this.id,
      siteId: data.siteId.present ? data.siteId.value : this.siteId,
      originalUri:
          data.originalUri.present ? data.originalUri.value : this.originalUri,
      uri: data.uri.present ? data.uri.value : this.uri,
      thumbUri: data.thumbUri.present ? data.thumbUri.value : this.thumbUri,
      type: data.type.present ? data.type.value : this.type,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      accuracyM: data.accuracyM.present ? data.accuracyM.value : this.accuracyM,
      lowAccuracy:
          data.lowAccuracy.present ? data.lowAccuracy.value : this.lowAccuracy,
      altitudeM: data.altitudeM.present ? data.altitudeM.value : this.altitudeM,
      activityTag:
          data.activityTag.present ? data.activityTag.value : this.activityTag,
      observationType: data.observationType.present
          ? data.observationType.value
          : this.observationType,
      linkedMediaId: data.linkedMediaId.present
          ? data.linkedMediaId.value
          : this.linkedMediaId,
      note: data.note.present ? data.note.value : this.note,
      capturedAt:
          data.capturedAt.present ? data.capturedAt.value : this.capturedAt,
      sha256Hash:
          data.sha256Hash.present ? data.sha256Hash.value : this.sha256Hash,
      evidenceSha256Hash: data.evidenceSha256Hash.present
          ? data.evidenceSha256Hash.value
          : this.evidenceSha256Hash,
      capturedAddress: data.capturedAddress.present
          ? data.capturedAddress.value
          : this.capturedAddress,
      creatorId: data.creatorId.present ? data.creatorId.value : this.creatorId,
      synced: data.synced.present ? data.synced.value : this.synced,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaEntry(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('originalUri: $originalUri, ')
          ..write('uri: $uri, ')
          ..write('thumbUri: $thumbUri, ')
          ..write('type: $type, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('lowAccuracy: $lowAccuracy, ')
          ..write('altitudeM: $altitudeM, ')
          ..write('activityTag: $activityTag, ')
          ..write('observationType: $observationType, ')
          ..write('linkedMediaId: $linkedMediaId, ')
          ..write('note: $note, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('sha256Hash: $sha256Hash, ')
          ..write('evidenceSha256Hash: $evidenceSha256Hash, ')
          ..write('capturedAddress: $capturedAddress, ')
          ..write('creatorId: $creatorId, ')
          ..write('synced: $synced, ')
          ..write('isDeleted: $isDeleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        siteId,
        originalUri,
        uri,
        thumbUri,
        type,
        lat,
        lon,
        accuracyM,
        lowAccuracy,
        altitudeM,
        activityTag,
        observationType,
        linkedMediaId,
        note,
        capturedAt,
        sha256Hash,
        evidenceSha256Hash,
        capturedAddress,
        creatorId,
        synced,
        isDeleted
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaEntry &&
          other.id == this.id &&
          other.siteId == this.siteId &&
          other.originalUri == this.originalUri &&
          other.uri == this.uri &&
          other.thumbUri == this.thumbUri &&
          other.type == this.type &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.accuracyM == this.accuracyM &&
          other.lowAccuracy == this.lowAccuracy &&
          other.altitudeM == this.altitudeM &&
          other.activityTag == this.activityTag &&
          other.observationType == this.observationType &&
          other.linkedMediaId == this.linkedMediaId &&
          other.note == this.note &&
          other.capturedAt == this.capturedAt &&
          other.sha256Hash == this.sha256Hash &&
          other.evidenceSha256Hash == this.evidenceSha256Hash &&
          other.capturedAddress == this.capturedAddress &&
          other.creatorId == this.creatorId &&
          other.synced == this.synced &&
          other.isDeleted == this.isDeleted);
}

class MediaCompanion extends UpdateCompanion<MediaEntry> {
  final Value<String> id;
  final Value<String?> siteId;
  final Value<String> originalUri;
  final Value<String> uri;
  final Value<String?> thumbUri;
  final Value<String?> type;
  final Value<double> lat;
  final Value<double> lon;
  final Value<double?> accuracyM;
  final Value<int> lowAccuracy;
  final Value<double?> altitudeM;
  final Value<String?> activityTag;
  final Value<String?> observationType;
  final Value<String?> linkedMediaId;
  final Value<String?> note;
  final Value<String> capturedAt;
  final Value<String?> sha256Hash;
  final Value<String?> evidenceSha256Hash;
  final Value<String?> capturedAddress;
  final Value<String?> creatorId;
  final Value<int> synced;
  final Value<int> isDeleted;
  final Value<int> rowid;
  const MediaCompanion({
    this.id = const Value.absent(),
    this.siteId = const Value.absent(),
    this.originalUri = const Value.absent(),
    this.uri = const Value.absent(),
    this.thumbUri = const Value.absent(),
    this.type = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.lowAccuracy = const Value.absent(),
    this.altitudeM = const Value.absent(),
    this.activityTag = const Value.absent(),
    this.observationType = const Value.absent(),
    this.linkedMediaId = const Value.absent(),
    this.note = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.sha256Hash = const Value.absent(),
    this.evidenceSha256Hash = const Value.absent(),
    this.capturedAddress = const Value.absent(),
    this.creatorId = const Value.absent(),
    this.synced = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaCompanion.insert({
    required String id,
    this.siteId = const Value.absent(),
    this.originalUri = const Value.absent(),
    required String uri,
    this.thumbUri = const Value.absent(),
    this.type = const Value.absent(),
    required double lat,
    required double lon,
    this.accuracyM = const Value.absent(),
    this.lowAccuracy = const Value.absent(),
    this.altitudeM = const Value.absent(),
    this.activityTag = const Value.absent(),
    this.observationType = const Value.absent(),
    this.linkedMediaId = const Value.absent(),
    this.note = const Value.absent(),
    required String capturedAt,
    this.sha256Hash = const Value.absent(),
    this.evidenceSha256Hash = const Value.absent(),
    this.capturedAddress = const Value.absent(),
    this.creatorId = const Value.absent(),
    this.synced = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        uri = Value(uri),
        lat = Value(lat),
        lon = Value(lon),
        capturedAt = Value(capturedAt);
  static Insertable<MediaEntry> custom({
    Expression<String>? id,
    Expression<String>? siteId,
    Expression<String>? originalUri,
    Expression<String>? uri,
    Expression<String>? thumbUri,
    Expression<String>? type,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<double>? accuracyM,
    Expression<int>? lowAccuracy,
    Expression<double>? altitudeM,
    Expression<String>? activityTag,
    Expression<String>? observationType,
    Expression<String>? linkedMediaId,
    Expression<String>? note,
    Expression<String>? capturedAt,
    Expression<String>? sha256Hash,
    Expression<String>? evidenceSha256Hash,
    Expression<String>? capturedAddress,
    Expression<String>? creatorId,
    Expression<int>? synced,
    Expression<int>? isDeleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (siteId != null) 'site_id': siteId,
      if (originalUri != null) 'original_uri': originalUri,
      if (uri != null) 'uri': uri,
      if (thumbUri != null) 'thumb_uri': thumbUri,
      if (type != null) 'type': type,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (lowAccuracy != null) 'low_accuracy': lowAccuracy,
      if (altitudeM != null) 'altitude_m': altitudeM,
      if (activityTag != null) 'activity_tag': activityTag,
      if (observationType != null) 'observation_type': observationType,
      if (linkedMediaId != null) 'linked_media_id': linkedMediaId,
      if (note != null) 'note': note,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (sha256Hash != null) 'sha256_hash': sha256Hash,
      if (evidenceSha256Hash != null)
        'evidence_sha256_hash': evidenceSha256Hash,
      if (capturedAddress != null) 'captured_address': capturedAddress,
      if (creatorId != null) 'creator_id': creatorId,
      if (synced != null) 'synced': synced,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaCompanion copyWith(
      {Value<String>? id,
      Value<String?>? siteId,
      Value<String>? originalUri,
      Value<String>? uri,
      Value<String?>? thumbUri,
      Value<String?>? type,
      Value<double>? lat,
      Value<double>? lon,
      Value<double?>? accuracyM,
      Value<int>? lowAccuracy,
      Value<double?>? altitudeM,
      Value<String?>? activityTag,
      Value<String?>? observationType,
      Value<String?>? linkedMediaId,
      Value<String?>? note,
      Value<String>? capturedAt,
      Value<String?>? sha256Hash,
      Value<String?>? evidenceSha256Hash,
      Value<String?>? capturedAddress,
      Value<String?>? creatorId,
      Value<int>? synced,
      Value<int>? isDeleted,
      Value<int>? rowid}) {
    return MediaCompanion(
      id: id ?? this.id,
      siteId: siteId ?? this.siteId,
      originalUri: originalUri ?? this.originalUri,
      uri: uri ?? this.uri,
      thumbUri: thumbUri ?? this.thumbUri,
      type: type ?? this.type,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      accuracyM: accuracyM ?? this.accuracyM,
      lowAccuracy: lowAccuracy ?? this.lowAccuracy,
      altitudeM: altitudeM ?? this.altitudeM,
      activityTag: activityTag ?? this.activityTag,
      observationType: observationType ?? this.observationType,
      linkedMediaId: linkedMediaId ?? this.linkedMediaId,
      note: note ?? this.note,
      capturedAt: capturedAt ?? this.capturedAt,
      sha256Hash: sha256Hash ?? this.sha256Hash,
      evidenceSha256Hash: evidenceSha256Hash ?? this.evidenceSha256Hash,
      capturedAddress: capturedAddress ?? this.capturedAddress,
      creatorId: creatorId ?? this.creatorId,
      synced: synced ?? this.synced,
      isDeleted: isDeleted ?? this.isDeleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (siteId.present) {
      map['site_id'] = Variable<String>(siteId.value);
    }
    if (originalUri.present) {
      map['original_uri'] = Variable<String>(originalUri.value);
    }
    if (uri.present) {
      map['uri'] = Variable<String>(uri.value);
    }
    if (thumbUri.present) {
      map['thumb_uri'] = Variable<String>(thumbUri.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (accuracyM.present) {
      map['accuracy_m'] = Variable<double>(accuracyM.value);
    }
    if (lowAccuracy.present) {
      map['low_accuracy'] = Variable<int>(lowAccuracy.value);
    }
    if (altitudeM.present) {
      map['altitude_m'] = Variable<double>(altitudeM.value);
    }
    if (activityTag.present) {
      map['activity_tag'] = Variable<String>(activityTag.value);
    }
    if (observationType.present) {
      map['observation_type'] = Variable<String>(observationType.value);
    }
    if (linkedMediaId.present) {
      map['linked_media_id'] = Variable<String>(linkedMediaId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<String>(capturedAt.value);
    }
    if (sha256Hash.present) {
      map['sha256_hash'] = Variable<String>(sha256Hash.value);
    }
    if (evidenceSha256Hash.present) {
      map['evidence_sha256_hash'] = Variable<String>(evidenceSha256Hash.value);
    }
    if (capturedAddress.present) {
      map['captured_address'] = Variable<String>(capturedAddress.value);
    }
    if (creatorId.present) {
      map['creator_id'] = Variable<String>(creatorId.value);
    }
    if (synced.present) {
      map['synced'] = Variable<int>(synced.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<int>(isDeleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaCompanion(')
          ..write('id: $id, ')
          ..write('siteId: $siteId, ')
          ..write('originalUri: $originalUri, ')
          ..write('uri: $uri, ')
          ..write('thumbUri: $thumbUri, ')
          ..write('type: $type, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('lowAccuracy: $lowAccuracy, ')
          ..write('altitudeM: $altitudeM, ')
          ..write('activityTag: $activityTag, ')
          ..write('observationType: $observationType, ')
          ..write('linkedMediaId: $linkedMediaId, ')
          ..write('note: $note, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('sha256Hash: $sha256Hash, ')
          ..write('evidenceSha256Hash: $evidenceSha256Hash, ')
          ..write('capturedAddress: $capturedAddress, ')
          ..write('creatorId: $creatorId, ')
          ..write('synced: $synced, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GooglePhotosSyncEntriesTable extends GooglePhotosSyncEntries
    with TableInfo<$GooglePhotosSyncEntriesTable, GooglePhotosSyncTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GooglePhotosSyncEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta =
      const VerificationMeta('mediaId');
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
      'media_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES media (id)'));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _googlePhotosMediaIdMeta =
      const VerificationMeta('googlePhotosMediaId');
  @override
  late final GeneratedColumn<String> googlePhotosMediaId =
      GeneratedColumn<String>('google_photos_media_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _uploadedAtMeta =
      const VerificationMeta('uploadedAt');
  @override
  late final GeneratedColumn<String> uploadedAt = GeneratedColumn<String>(
      'uploaded_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _errorMessageMeta =
      const VerificationMeta('errorMessage');
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
      'error_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastAttemptAtMeta =
      const VerificationMeta('lastAttemptAt');
  @override
  late final GeneratedColumn<String> lastAttemptAt = GeneratedColumn<String>(
      'last_attempt_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        mediaId,
        status,
        googlePhotosMediaId,
        uploadedAt,
        errorMessage,
        retryCount,
        lastAttemptAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'google_photos_sync_entries';
  @override
  VerificationContext validateIntegrity(
      Insertable<GooglePhotosSyncTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(_mediaIdMeta,
          mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta));
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('google_photos_media_id')) {
      context.handle(
          _googlePhotosMediaIdMeta,
          googlePhotosMediaId.isAcceptableOrUnknown(
              data['google_photos_media_id']!, _googlePhotosMediaIdMeta));
    }
    if (data.containsKey('uploaded_at')) {
      context.handle(
          _uploadedAtMeta,
          uploadedAt.isAcceptableOrUnknown(
              data['uploaded_at']!, _uploadedAtMeta));
    }
    if (data.containsKey('error_message')) {
      context.handle(
          _errorMessageMeta,
          errorMessage.isAcceptableOrUnknown(
              data['error_message']!, _errorMessageMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
          _lastAttemptAtMeta,
          lastAttemptAt.isAcceptableOrUnknown(
              data['last_attempt_at']!, _lastAttemptAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId};
  @override
  GooglePhotosSyncTableData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GooglePhotosSyncTableData(
      mediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_id'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      googlePhotosMediaId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}google_photos_media_id']),
      uploadedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uploaded_at']),
      errorMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error_message']),
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      lastAttemptAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_attempt_at']),
    );
  }

  @override
  $GooglePhotosSyncEntriesTable createAlias(String alias) {
    return $GooglePhotosSyncEntriesTable(attachedDatabase, alias);
  }
}

class GooglePhotosSyncTableData extends DataClass
    implements Insertable<GooglePhotosSyncTableData> {
  final String mediaId;
  final String status;
  final String? googlePhotosMediaId;
  final String? uploadedAt;
  final String? errorMessage;
  final int retryCount;
  final String? lastAttemptAt;
  const GooglePhotosSyncTableData(
      {required this.mediaId,
      required this.status,
      this.googlePhotosMediaId,
      this.uploadedAt,
      this.errorMessage,
      required this.retryCount,
      this.lastAttemptAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || googlePhotosMediaId != null) {
      map['google_photos_media_id'] = Variable<String>(googlePhotosMediaId);
    }
    if (!nullToAbsent || uploadedAt != null) {
      map['uploaded_at'] = Variable<String>(uploadedAt);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<String>(lastAttemptAt);
    }
    return map;
  }

  GooglePhotosSyncEntriesCompanion toCompanion(bool nullToAbsent) {
    return GooglePhotosSyncEntriesCompanion(
      mediaId: Value(mediaId),
      status: Value(status),
      googlePhotosMediaId: googlePhotosMediaId == null && nullToAbsent
          ? const Value.absent()
          : Value(googlePhotosMediaId),
      uploadedAt: uploadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadedAt),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      retryCount: Value(retryCount),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
    );
  }

  factory GooglePhotosSyncTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GooglePhotosSyncTableData(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      status: serializer.fromJson<String>(json['status']),
      googlePhotosMediaId:
          serializer.fromJson<String?>(json['googlePhotosMediaId']),
      uploadedAt: serializer.fromJson<String?>(json['uploadedAt']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastAttemptAt: serializer.fromJson<String?>(json['lastAttemptAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'status': serializer.toJson<String>(status),
      'googlePhotosMediaId': serializer.toJson<String?>(googlePhotosMediaId),
      'uploadedAt': serializer.toJson<String?>(uploadedAt),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastAttemptAt': serializer.toJson<String?>(lastAttemptAt),
    };
  }

  GooglePhotosSyncTableData copyWith(
          {String? mediaId,
          String? status,
          Value<String?> googlePhotosMediaId = const Value.absent(),
          Value<String?> uploadedAt = const Value.absent(),
          Value<String?> errorMessage = const Value.absent(),
          int? retryCount,
          Value<String?> lastAttemptAt = const Value.absent()}) =>
      GooglePhotosSyncTableData(
        mediaId: mediaId ?? this.mediaId,
        status: status ?? this.status,
        googlePhotosMediaId: googlePhotosMediaId.present
            ? googlePhotosMediaId.value
            : this.googlePhotosMediaId,
        uploadedAt: uploadedAt.present ? uploadedAt.value : this.uploadedAt,
        errorMessage:
            errorMessage.present ? errorMessage.value : this.errorMessage,
        retryCount: retryCount ?? this.retryCount,
        lastAttemptAt:
            lastAttemptAt.present ? lastAttemptAt.value : this.lastAttemptAt,
      );
  GooglePhotosSyncTableData copyWithCompanion(
      GooglePhotosSyncEntriesCompanion data) {
    return GooglePhotosSyncTableData(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      status: data.status.present ? data.status.value : this.status,
      googlePhotosMediaId: data.googlePhotosMediaId.present
          ? data.googlePhotosMediaId.value
          : this.googlePhotosMediaId,
      uploadedAt:
          data.uploadedAt.present ? data.uploadedAt.value : this.uploadedAt,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GooglePhotosSyncTableData(')
          ..write('mediaId: $mediaId, ')
          ..write('status: $status, ')
          ..write('googlePhotosMediaId: $googlePhotosMediaId, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastAttemptAt: $lastAttemptAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaId, status, googlePhotosMediaId,
      uploadedAt, errorMessage, retryCount, lastAttemptAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GooglePhotosSyncTableData &&
          other.mediaId == this.mediaId &&
          other.status == this.status &&
          other.googlePhotosMediaId == this.googlePhotosMediaId &&
          other.uploadedAt == this.uploadedAt &&
          other.errorMessage == this.errorMessage &&
          other.retryCount == this.retryCount &&
          other.lastAttemptAt == this.lastAttemptAt);
}

class GooglePhotosSyncEntriesCompanion
    extends UpdateCompanion<GooglePhotosSyncTableData> {
  final Value<String> mediaId;
  final Value<String> status;
  final Value<String?> googlePhotosMediaId;
  final Value<String?> uploadedAt;
  final Value<String?> errorMessage;
  final Value<int> retryCount;
  final Value<String?> lastAttemptAt;
  final Value<int> rowid;
  const GooglePhotosSyncEntriesCompanion({
    this.mediaId = const Value.absent(),
    this.status = const Value.absent(),
    this.googlePhotosMediaId = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GooglePhotosSyncEntriesCompanion.insert({
    required String mediaId,
    this.status = const Value.absent(),
    this.googlePhotosMediaId = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : mediaId = Value(mediaId);
  static Insertable<GooglePhotosSyncTableData> custom({
    Expression<String>? mediaId,
    Expression<String>? status,
    Expression<String>? googlePhotosMediaId,
    Expression<String>? uploadedAt,
    Expression<String>? errorMessage,
    Expression<int>? retryCount,
    Expression<String>? lastAttemptAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (status != null) 'status': status,
      if (googlePhotosMediaId != null)
        'google_photos_media_id': googlePhotosMediaId,
      if (uploadedAt != null) 'uploaded_at': uploadedAt,
      if (errorMessage != null) 'error_message': errorMessage,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GooglePhotosSyncEntriesCompanion copyWith(
      {Value<String>? mediaId,
      Value<String>? status,
      Value<String?>? googlePhotosMediaId,
      Value<String?>? uploadedAt,
      Value<String?>? errorMessage,
      Value<int>? retryCount,
      Value<String?>? lastAttemptAt,
      Value<int>? rowid}) {
    return GooglePhotosSyncEntriesCompanion(
      mediaId: mediaId ?? this.mediaId,
      status: status ?? this.status,
      googlePhotosMediaId: googlePhotosMediaId ?? this.googlePhotosMediaId,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (googlePhotosMediaId.present) {
      map['google_photos_media_id'] =
          Variable<String>(googlePhotosMediaId.value);
    }
    if (uploadedAt.present) {
      map['uploaded_at'] = Variable<String>(uploadedAt.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<String>(lastAttemptAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GooglePhotosSyncEntriesCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('status: $status, ')
          ..write('googlePhotosMediaId: $googlePhotosMediaId, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SitesTable sites = $SitesTable(this);
  late final $MediaTable media = $MediaTable(this);
  late final $GooglePhotosSyncEntriesTable googlePhotosSyncEntries =
      $GooglePhotosSyncEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [sites, media, googlePhotosSyncEntries];
}

typedef $$SitesTableCreateCompanionBuilder = SitesCompanion Function({
  required String id,
  Value<String?> siteCode,
  Value<String?> name,
  Value<String?> address,
  Value<String?> creatorId,
  Value<int> rowid,
});
typedef $$SitesTableUpdateCompanionBuilder = SitesCompanion Function({
  Value<String> id,
  Value<String?> siteCode,
  Value<String?> name,
  Value<String?> address,
  Value<String?> creatorId,
  Value<int> rowid,
});

final class $$SitesTableReferences
    extends BaseReferences<_$AppDatabase, $SitesTable, SiteEntry> {
  $$SitesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MediaTable, List<MediaEntry>> _mediaRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.media,
          aliasName: $_aliasNameGenerator(db.sites.id, db.media.siteId));

  $$MediaTableProcessedTableManager get mediaRefs {
    final manager = $$MediaTableTableManager($_db, $_db.media)
        .filter((f) => f.siteId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mediaRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SitesTableFilterComposer extends Composer<_$AppDatabase, $SitesTable> {
  $$SitesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get siteCode => $composableBuilder(
      column: $table.siteCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get creatorId => $composableBuilder(
      column: $table.creatorId, builder: (column) => ColumnFilters(column));

  Expression<bool> mediaRefs(
      Expression<bool> Function($$MediaTableFilterComposer f) f) {
    final $$MediaTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.siteId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableFilterComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SitesTableOrderingComposer
    extends Composer<_$AppDatabase, $SitesTable> {
  $$SitesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get siteCode => $composableBuilder(
      column: $table.siteCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get address => $composableBuilder(
      column: $table.address, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get creatorId => $composableBuilder(
      column: $table.creatorId, builder: (column) => ColumnOrderings(column));
}

class $$SitesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SitesTable> {
  $$SitesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get siteCode =>
      $composableBuilder(column: $table.siteCode, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get creatorId =>
      $composableBuilder(column: $table.creatorId, builder: (column) => column);

  Expression<T> mediaRefs<T extends Object>(
      Expression<T> Function($$MediaTableAnnotationComposer a) f) {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.siteId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableAnnotationComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SitesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SitesTable,
    SiteEntry,
    $$SitesTableFilterComposer,
    $$SitesTableOrderingComposer,
    $$SitesTableAnnotationComposer,
    $$SitesTableCreateCompanionBuilder,
    $$SitesTableUpdateCompanionBuilder,
    (SiteEntry, $$SitesTableReferences),
    SiteEntry,
    PrefetchHooks Function({bool mediaRefs})> {
  $$SitesTableTableManager(_$AppDatabase db, $SitesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SitesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SitesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SitesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> siteCode = const Value.absent(),
            Value<String?> name = const Value.absent(),
            Value<String?> address = const Value.absent(),
            Value<String?> creatorId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SitesCompanion(
            id: id,
            siteCode: siteCode,
            name: name,
            address: address,
            creatorId: creatorId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> siteCode = const Value.absent(),
            Value<String?> name = const Value.absent(),
            Value<String?> address = const Value.absent(),
            Value<String?> creatorId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SitesCompanion.insert(
            id: id,
            siteCode: siteCode,
            name: name,
            address: address,
            creatorId: creatorId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$SitesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({mediaRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (mediaRefs) db.media],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (mediaRefs)
                    await $_getPrefetchedData<SiteEntry, $SitesTable,
                            MediaEntry>(
                        currentTable: table,
                        referencedTable:
                            $$SitesTableReferences._mediaRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SitesTableReferences(db, table, p0).mediaRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.siteId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SitesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SitesTable,
    SiteEntry,
    $$SitesTableFilterComposer,
    $$SitesTableOrderingComposer,
    $$SitesTableAnnotationComposer,
    $$SitesTableCreateCompanionBuilder,
    $$SitesTableUpdateCompanionBuilder,
    (SiteEntry, $$SitesTableReferences),
    SiteEntry,
    PrefetchHooks Function({bool mediaRefs})>;
typedef $$MediaTableCreateCompanionBuilder = MediaCompanion Function({
  required String id,
  Value<String?> siteId,
  Value<String> originalUri,
  required String uri,
  Value<String?> thumbUri,
  Value<String?> type,
  required double lat,
  required double lon,
  Value<double?> accuracyM,
  Value<int> lowAccuracy,
  Value<double?> altitudeM,
  Value<String?> activityTag,
  Value<String?> observationType,
  Value<String?> linkedMediaId,
  Value<String?> note,
  required String capturedAt,
  Value<String?> sha256Hash,
  Value<String?> evidenceSha256Hash,
  Value<String?> capturedAddress,
  Value<String?> creatorId,
  Value<int> synced,
  Value<int> isDeleted,
  Value<int> rowid,
});
typedef $$MediaTableUpdateCompanionBuilder = MediaCompanion Function({
  Value<String> id,
  Value<String?> siteId,
  Value<String> originalUri,
  Value<String> uri,
  Value<String?> thumbUri,
  Value<String?> type,
  Value<double> lat,
  Value<double> lon,
  Value<double?> accuracyM,
  Value<int> lowAccuracy,
  Value<double?> altitudeM,
  Value<String?> activityTag,
  Value<String?> observationType,
  Value<String?> linkedMediaId,
  Value<String?> note,
  Value<String> capturedAt,
  Value<String?> sha256Hash,
  Value<String?> evidenceSha256Hash,
  Value<String?> capturedAddress,
  Value<String?> creatorId,
  Value<int> synced,
  Value<int> isDeleted,
  Value<int> rowid,
});

final class $$MediaTableReferences
    extends BaseReferences<_$AppDatabase, $MediaTable, MediaEntry> {
  $$MediaTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SitesTable _siteIdTable(_$AppDatabase db) =>
      db.sites.createAlias($_aliasNameGenerator(db.media.siteId, db.sites.id));

  $$SitesTableProcessedTableManager? get siteId {
    final $_column = $_itemColumn<String>('site_id');
    if ($_column == null) return null;
    final manager = $$SitesTableTableManager($_db, $_db.sites)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_siteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $MediaTable _linkedMediaIdTable(_$AppDatabase db) => db.media
      .createAlias($_aliasNameGenerator(db.media.linkedMediaId, db.media.id));

  $$MediaTableProcessedTableManager? get linkedMediaId {
    final $_column = $_itemColumn<String>('linked_media_id');
    if ($_column == null) return null;
    final manager = $$MediaTableTableManager($_db, $_db.media)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_linkedMediaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$GooglePhotosSyncEntriesTable,
      List<GooglePhotosSyncTableData>> _googlePhotosSyncEntriesRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.googlePhotosSyncEntries,
          aliasName: $_aliasNameGenerator(
              db.media.id, db.googlePhotosSyncEntries.mediaId));

  $$GooglePhotosSyncEntriesTableProcessedTableManager
      get googlePhotosSyncEntriesRefs {
    final manager = $$GooglePhotosSyncEntriesTableTableManager(
            $_db, $_db.googlePhotosSyncEntries)
        .filter((f) => f.mediaId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_googlePhotosSyncEntriesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$MediaTableFilterComposer extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get originalUri => $composableBuilder(
      column: $table.originalUri, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uri => $composableBuilder(
      column: $table.uri, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbUri => $composableBuilder(
      column: $table.thumbUri, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get accuracyM => $composableBuilder(
      column: $table.accuracyM, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lowAccuracy => $composableBuilder(
      column: $table.lowAccuracy, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get altitudeM => $composableBuilder(
      column: $table.altitudeM, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get activityTag => $composableBuilder(
      column: $table.activityTag, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get observationType => $composableBuilder(
      column: $table.observationType,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sha256Hash => $composableBuilder(
      column: $table.sha256Hash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get evidenceSha256Hash => $composableBuilder(
      column: $table.evidenceSha256Hash,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get capturedAddress => $composableBuilder(
      column: $table.capturedAddress,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get creatorId => $composableBuilder(
      column: $table.creatorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnFilters(column));

  $$SitesTableFilterComposer get siteId {
    final $$SitesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.siteId,
        referencedTable: $db.sites,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SitesTableFilterComposer(
              $db: $db,
              $table: $db.sites,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$MediaTableFilterComposer get linkedMediaId {
    final $$MediaTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.linkedMediaId,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableFilterComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> googlePhotosSyncEntriesRefs(
      Expression<bool> Function($$GooglePhotosSyncEntriesTableFilterComposer f)
          f) {
    final $$GooglePhotosSyncEntriesTableFilterComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.googlePhotosSyncEntries,
            getReferencedColumn: (t) => t.mediaId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$GooglePhotosSyncEntriesTableFilterComposer(
                  $db: $db,
                  $table: $db.googlePhotosSyncEntries,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$MediaTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get originalUri => $composableBuilder(
      column: $table.originalUri, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uri => $composableBuilder(
      column: $table.uri, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbUri => $composableBuilder(
      column: $table.thumbUri, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lat => $composableBuilder(
      column: $table.lat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get lon => $composableBuilder(
      column: $table.lon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get accuracyM => $composableBuilder(
      column: $table.accuracyM, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lowAccuracy => $composableBuilder(
      column: $table.lowAccuracy, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get altitudeM => $composableBuilder(
      column: $table.altitudeM, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get activityTag => $composableBuilder(
      column: $table.activityTag, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get observationType => $composableBuilder(
      column: $table.observationType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sha256Hash => $composableBuilder(
      column: $table.sha256Hash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get evidenceSha256Hash => $composableBuilder(
      column: $table.evidenceSha256Hash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get capturedAddress => $composableBuilder(
      column: $table.capturedAddress,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get creatorId => $composableBuilder(
      column: $table.creatorId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get synced => $composableBuilder(
      column: $table.synced, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get isDeleted => $composableBuilder(
      column: $table.isDeleted, builder: (column) => ColumnOrderings(column));

  $$SitesTableOrderingComposer get siteId {
    final $$SitesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.siteId,
        referencedTable: $db.sites,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SitesTableOrderingComposer(
              $db: $db,
              $table: $db.sites,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$MediaTableOrderingComposer get linkedMediaId {
    final $$MediaTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.linkedMediaId,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableOrderingComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MediaTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get originalUri => $composableBuilder(
      column: $table.originalUri, builder: (column) => column);

  GeneratedColumn<String> get uri =>
      $composableBuilder(column: $table.uri, builder: (column) => column);

  GeneratedColumn<String> get thumbUri =>
      $composableBuilder(column: $table.thumbUri, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<double> get accuracyM =>
      $composableBuilder(column: $table.accuracyM, builder: (column) => column);

  GeneratedColumn<int> get lowAccuracy => $composableBuilder(
      column: $table.lowAccuracy, builder: (column) => column);

  GeneratedColumn<double> get altitudeM =>
      $composableBuilder(column: $table.altitudeM, builder: (column) => column);

  GeneratedColumn<String> get activityTag => $composableBuilder(
      column: $table.activityTag, builder: (column) => column);

  GeneratedColumn<String> get observationType => $composableBuilder(
      column: $table.observationType, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => column);

  GeneratedColumn<String> get sha256Hash => $composableBuilder(
      column: $table.sha256Hash, builder: (column) => column);

  GeneratedColumn<String> get evidenceSha256Hash => $composableBuilder(
      column: $table.evidenceSha256Hash, builder: (column) => column);

  GeneratedColumn<String> get capturedAddress => $composableBuilder(
      column: $table.capturedAddress, builder: (column) => column);

  GeneratedColumn<String> get creatorId =>
      $composableBuilder(column: $table.creatorId, builder: (column) => column);

  GeneratedColumn<int> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<int> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  $$SitesTableAnnotationComposer get siteId {
    final $$SitesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.siteId,
        referencedTable: $db.sites,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SitesTableAnnotationComposer(
              $db: $db,
              $table: $db.sites,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$MediaTableAnnotationComposer get linkedMediaId {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.linkedMediaId,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableAnnotationComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> googlePhotosSyncEntriesRefs<T extends Object>(
      Expression<T> Function($$GooglePhotosSyncEntriesTableAnnotationComposer a)
          f) {
    final $$GooglePhotosSyncEntriesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.googlePhotosSyncEntries,
            getReferencedColumn: (t) => t.mediaId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$GooglePhotosSyncEntriesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.googlePhotosSyncEntries,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$MediaTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MediaTable,
    MediaEntry,
    $$MediaTableFilterComposer,
    $$MediaTableOrderingComposer,
    $$MediaTableAnnotationComposer,
    $$MediaTableCreateCompanionBuilder,
    $$MediaTableUpdateCompanionBuilder,
    (MediaEntry, $$MediaTableReferences),
    MediaEntry,
    PrefetchHooks Function(
        {bool siteId, bool linkedMediaId, bool googlePhotosSyncEntriesRefs})> {
  $$MediaTableTableManager(_$AppDatabase db, $MediaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> siteId = const Value.absent(),
            Value<String> originalUri = const Value.absent(),
            Value<String> uri = const Value.absent(),
            Value<String?> thumbUri = const Value.absent(),
            Value<String?> type = const Value.absent(),
            Value<double> lat = const Value.absent(),
            Value<double> lon = const Value.absent(),
            Value<double?> accuracyM = const Value.absent(),
            Value<int> lowAccuracy = const Value.absent(),
            Value<double?> altitudeM = const Value.absent(),
            Value<String?> activityTag = const Value.absent(),
            Value<String?> observationType = const Value.absent(),
            Value<String?> linkedMediaId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<String> capturedAt = const Value.absent(),
            Value<String?> sha256Hash = const Value.absent(),
            Value<String?> evidenceSha256Hash = const Value.absent(),
            Value<String?> capturedAddress = const Value.absent(),
            Value<String?> creatorId = const Value.absent(),
            Value<int> synced = const Value.absent(),
            Value<int> isDeleted = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaCompanion(
            id: id,
            siteId: siteId,
            originalUri: originalUri,
            uri: uri,
            thumbUri: thumbUri,
            type: type,
            lat: lat,
            lon: lon,
            accuracyM: accuracyM,
            lowAccuracy: lowAccuracy,
            altitudeM: altitudeM,
            activityTag: activityTag,
            observationType: observationType,
            linkedMediaId: linkedMediaId,
            note: note,
            capturedAt: capturedAt,
            sha256Hash: sha256Hash,
            evidenceSha256Hash: evidenceSha256Hash,
            capturedAddress: capturedAddress,
            creatorId: creatorId,
            synced: synced,
            isDeleted: isDeleted,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> siteId = const Value.absent(),
            Value<String> originalUri = const Value.absent(),
            required String uri,
            Value<String?> thumbUri = const Value.absent(),
            Value<String?> type = const Value.absent(),
            required double lat,
            required double lon,
            Value<double?> accuracyM = const Value.absent(),
            Value<int> lowAccuracy = const Value.absent(),
            Value<double?> altitudeM = const Value.absent(),
            Value<String?> activityTag = const Value.absent(),
            Value<String?> observationType = const Value.absent(),
            Value<String?> linkedMediaId = const Value.absent(),
            Value<String?> note = const Value.absent(),
            required String capturedAt,
            Value<String?> sha256Hash = const Value.absent(),
            Value<String?> evidenceSha256Hash = const Value.absent(),
            Value<String?> capturedAddress = const Value.absent(),
            Value<String?> creatorId = const Value.absent(),
            Value<int> synced = const Value.absent(),
            Value<int> isDeleted = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaCompanion.insert(
            id: id,
            siteId: siteId,
            originalUri: originalUri,
            uri: uri,
            thumbUri: thumbUri,
            type: type,
            lat: lat,
            lon: lon,
            accuracyM: accuracyM,
            lowAccuracy: lowAccuracy,
            altitudeM: altitudeM,
            activityTag: activityTag,
            observationType: observationType,
            linkedMediaId: linkedMediaId,
            note: note,
            capturedAt: capturedAt,
            sha256Hash: sha256Hash,
            evidenceSha256Hash: evidenceSha256Hash,
            capturedAddress: capturedAddress,
            creatorId: creatorId,
            synced: synced,
            isDeleted: isDeleted,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$MediaTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {siteId = false,
              linkedMediaId = false,
              googlePhotosSyncEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (googlePhotosSyncEntriesRefs) db.googlePhotosSyncEntries
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (siteId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.siteId,
                    referencedTable: $$MediaTableReferences._siteIdTable(db),
                    referencedColumn:
                        $$MediaTableReferences._siteIdTable(db).id,
                  ) as T;
                }
                if (linkedMediaId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.linkedMediaId,
                    referencedTable:
                        $$MediaTableReferences._linkedMediaIdTable(db),
                    referencedColumn:
                        $$MediaTableReferences._linkedMediaIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (googlePhotosSyncEntriesRefs)
                    await $_getPrefetchedData<MediaEntry, $MediaTable,
                            GooglePhotosSyncTableData>(
                        currentTable: table,
                        referencedTable: $$MediaTableReferences
                            ._googlePhotosSyncEntriesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$MediaTableReferences(db, table, p0)
                                .googlePhotosSyncEntriesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.mediaId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$MediaTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MediaTable,
    MediaEntry,
    $$MediaTableFilterComposer,
    $$MediaTableOrderingComposer,
    $$MediaTableAnnotationComposer,
    $$MediaTableCreateCompanionBuilder,
    $$MediaTableUpdateCompanionBuilder,
    (MediaEntry, $$MediaTableReferences),
    MediaEntry,
    PrefetchHooks Function(
        {bool siteId, bool linkedMediaId, bool googlePhotosSyncEntriesRefs})>;
typedef $$GooglePhotosSyncEntriesTableCreateCompanionBuilder
    = GooglePhotosSyncEntriesCompanion Function({
  required String mediaId,
  Value<String> status,
  Value<String?> googlePhotosMediaId,
  Value<String?> uploadedAt,
  Value<String?> errorMessage,
  Value<int> retryCount,
  Value<String?> lastAttemptAt,
  Value<int> rowid,
});
typedef $$GooglePhotosSyncEntriesTableUpdateCompanionBuilder
    = GooglePhotosSyncEntriesCompanion Function({
  Value<String> mediaId,
  Value<String> status,
  Value<String?> googlePhotosMediaId,
  Value<String?> uploadedAt,
  Value<String?> errorMessage,
  Value<int> retryCount,
  Value<String?> lastAttemptAt,
  Value<int> rowid,
});

final class $$GooglePhotosSyncEntriesTableReferences extends BaseReferences<
    _$AppDatabase, $GooglePhotosSyncEntriesTable, GooglePhotosSyncTableData> {
  $$GooglePhotosSyncEntriesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $MediaTable _mediaIdTable(_$AppDatabase db) => db.media.createAlias(
      $_aliasNameGenerator(db.googlePhotosSyncEntries.mediaId, db.media.id));

  $$MediaTableProcessedTableManager get mediaId {
    final $_column = $_itemColumn<String>('media_id')!;

    final manager = $$MediaTableTableManager($_db, $_db.media)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mediaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$GooglePhotosSyncEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $GooglePhotosSyncEntriesTable> {
  $$GooglePhotosSyncEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get googlePhotosMediaId => $composableBuilder(
      column: $table.googlePhotosMediaId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uploadedAt => $composableBuilder(
      column: $table.uploadedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => ColumnFilters(column));

  $$MediaTableFilterComposer get mediaId {
    final $$MediaTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.mediaId,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableFilterComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$GooglePhotosSyncEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $GooglePhotosSyncEntriesTable> {
  $$GooglePhotosSyncEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get googlePhotosMediaId => $composableBuilder(
      column: $table.googlePhotosMediaId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uploadedAt => $composableBuilder(
      column: $table.uploadedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => ColumnOrderings(column));

  $$MediaTableOrderingComposer get mediaId {
    final $$MediaTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.mediaId,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableOrderingComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$GooglePhotosSyncEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GooglePhotosSyncEntriesTable> {
  $$GooglePhotosSyncEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get googlePhotosMediaId => $composableBuilder(
      column: $table.googlePhotosMediaId, builder: (column) => column);

  GeneratedColumn<String> get uploadedAt => $composableBuilder(
      column: $table.uploadedAt, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
      column: $table.errorMessage, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<String> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => column);

  $$MediaTableAnnotationComposer get mediaId {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.mediaId,
        referencedTable: $db.media,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaTableAnnotationComposer(
              $db: $db,
              $table: $db.media,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$GooglePhotosSyncEntriesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $GooglePhotosSyncEntriesTable,
    GooglePhotosSyncTableData,
    $$GooglePhotosSyncEntriesTableFilterComposer,
    $$GooglePhotosSyncEntriesTableOrderingComposer,
    $$GooglePhotosSyncEntriesTableAnnotationComposer,
    $$GooglePhotosSyncEntriesTableCreateCompanionBuilder,
    $$GooglePhotosSyncEntriesTableUpdateCompanionBuilder,
    (GooglePhotosSyncTableData, $$GooglePhotosSyncEntriesTableReferences),
    GooglePhotosSyncTableData,
    PrefetchHooks Function({bool mediaId})> {
  $$GooglePhotosSyncEntriesTableTableManager(
      _$AppDatabase db, $GooglePhotosSyncEntriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GooglePhotosSyncEntriesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$GooglePhotosSyncEntriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GooglePhotosSyncEntriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> mediaId = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> googlePhotosMediaId = const Value.absent(),
            Value<String?> uploadedAt = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> lastAttemptAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GooglePhotosSyncEntriesCompanion(
            mediaId: mediaId,
            status: status,
            googlePhotosMediaId: googlePhotosMediaId,
            uploadedAt: uploadedAt,
            errorMessage: errorMessage,
            retryCount: retryCount,
            lastAttemptAt: lastAttemptAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String mediaId,
            Value<String> status = const Value.absent(),
            Value<String?> googlePhotosMediaId = const Value.absent(),
            Value<String?> uploadedAt = const Value.absent(),
            Value<String?> errorMessage = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> lastAttemptAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              GooglePhotosSyncEntriesCompanion.insert(
            mediaId: mediaId,
            status: status,
            googlePhotosMediaId: googlePhotosMediaId,
            uploadedAt: uploadedAt,
            errorMessage: errorMessage,
            retryCount: retryCount,
            lastAttemptAt: lastAttemptAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$GooglePhotosSyncEntriesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({mediaId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (mediaId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.mediaId,
                    referencedTable: $$GooglePhotosSyncEntriesTableReferences
                        ._mediaIdTable(db),
                    referencedColumn: $$GooglePhotosSyncEntriesTableReferences
                        ._mediaIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$GooglePhotosSyncEntriesTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $GooglePhotosSyncEntriesTable,
        GooglePhotosSyncTableData,
        $$GooglePhotosSyncEntriesTableFilterComposer,
        $$GooglePhotosSyncEntriesTableOrderingComposer,
        $$GooglePhotosSyncEntriesTableAnnotationComposer,
        $$GooglePhotosSyncEntriesTableCreateCompanionBuilder,
        $$GooglePhotosSyncEntriesTableUpdateCompanionBuilder,
        (GooglePhotosSyncTableData, $$GooglePhotosSyncEntriesTableReferences),
        GooglePhotosSyncTableData,
        PrefetchHooks Function({bool mediaId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SitesTableTableManager get sites =>
      $$SitesTableTableManager(_db, _db.sites);
  $$MediaTableTableManager get media =>
      $$MediaTableTableManager(_db, _db.media);
  $$GooglePhotosSyncEntriesTableTableManager get googlePhotosSyncEntries =>
      $$GooglePhotosSyncEntriesTableTableManager(
          _db, _db.googlePhotosSyncEntries);
}
