import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import '../imaging/pixel_spacing.dart';
import 'gsps_codec.dart';

/// Pure Dart DICOM Part 10 binary serializer for Grayscale Softcopy Presentation State (GSPS).
///
/// Encodes GSPS instances into valid DICOM Part 10 binary files conforming to
/// DICOM PS 3.3 (Annex A.33) and PS 3.10 with Explicit VR Little Endian transfer syntax.
class GspsDicomEncoder {
  static const String gspsSopClassUid = '1.2.840.10008.5.1.4.1.1.11.1';
  static const String explicitVrLittleEndian = '1.2.840.10008.1.2.1';
  static const String implementationClassUid = '1.2.826.0.1.3680043.9.7711.1';
  static const String implementationVersionName = 'DICOM_FLUTTER_1';

  /// Private Creator Identification code for GoSmart Health presentation state semantics.
  static const String privateCreatorTag = 'GOSMART_HEALTH_GSPS_V1';
  static const int privateGroup = 0x0079;
  static const int privateCreatorElement = 0x0010;
  static const int privateSemanticsElement = 0x1001;

  /// Generates a globally unique DICOM UID conforming to ITU-T X.667 / ISO/IEC 9834-8 (2.25.x).
  static String generateDicomUid() {
    final rnd = math.Random.secure();
    var n = BigInt.zero;
    for (int i = 0; i < 16; i++) {
      n = (n << 8) | BigInt.from(rnd.nextInt(256));
    }
    return '2.25.$n';
  }

  /// Encodes a [GspsPresentationState] and its associated study/series/frame context
  /// into standard DICOM Part 10 binary bytes (`.dcm`).
  static Uint8List encodePart10({
    required GspsPresentationState gsps,
    required String studyInstanceUid,
    required String seriesInstanceUid,
    required String sopInstanceUid,
    int? frameNumber, // 1-indexed in DICOM
    PixelSpacing? pixelSpacing,
    String? patientName,
    String? patientId,
    String? patientBirthDate,
    String? patientSex,
    String? studyDate,
    String? studyTime,
    String? accessionNumber,
    String? presentationSeriesUid,
    String? presentationSopUid,
  }) {
    final prSopUid = presentationSopUid ?? gsps.sopInstanceUid ?? generateDicomUid();
    final prSeriesUid = presentationSeriesUid ?? generateDicomUid();

    // 1. Build File Meta Information (Group 0002)
    final metaBuilder = _DicomElementBuilder(isLittleEndian: true);
    // (0002,0001) OB FileMetaInformationVersion: 0x00, 0x01
    metaBuilder.writeOb(0x0002, 0x0001, Uint8List.fromList([0x00, 0x01]));
    // (0002,0002) UI MediaStorageSOPClassUID
    metaBuilder.writeUi(0x0002, 0x0002, gspsSopClassUid);
    // (0002,0003) UI MediaStorageSOPInstanceUID
    metaBuilder.writeUi(0x0002, 0x0003, prSopUid);
    // (0002,0010) UI TransferSyntaxUID
    metaBuilder.writeUi(0x0002, 0x0010, explicitVrLittleEndian);
    // (0002,0012) UI ImplementationClassUID
    metaBuilder.writeUi(0x0002, 0x0012, implementationClassUid);
    // (0002,0013) SH ImplementationVersionName
    metaBuilder.writeSh(0x0002, 0x0013, implementationVersionName);

    final metaBytes = metaBuilder.toBytes();

    // 2. Build Main Dataset Elements (sorted by tag group and element)
    final dsBuilder = _DicomElementBuilder(isLittleEndian: true);

    // Group 0008: Identification
    dsBuilder.writeCs(0x0008, 0x0005, 'ISO_IR 192'); // Specific Character Set (UTF-8)
    dsBuilder.writeUi(0x0008, 0x0016, gspsSopClassUid); // SOP Class UID
    dsBuilder.writeUi(0x0008, 0x0018, prSopUid); // SOP Instance UID

    final now = gsps.creationDateTime;
    final nowDa = _formatDa(now);
    final nowTm = _formatTm(now);

    dsBuilder.writeDa(0x0008, 0x0020, studyDate ?? nowDa); // Study Date
    dsBuilder.writeTm(0x0008, 0x0030, studyTime ?? nowTm); // Study Time
    dsBuilder.writeSh(0x0008, 0x0050, accessionNumber ?? ''); // Accession Number
    dsBuilder.writeCs(0x0008, 0x0060, 'PR'); // Modality = PR (Presentation State)

    // (0008,1115) SQ ReferencedSeriesSequence
    final refSeriesItem = _DicomElementBuilder(isLittleEndian: true);
    final refImageBytesList = <Uint8List>[];

    if (gsps.frameStates.isNotEmpty) {
      for (final fs in gsps.frameStates) {
        refImageBytesList.add(_buildReferencedImageItem(
          sopInstanceUid: fs.referencedSopInstanceUid,
          frameNumber: fs.referencedFrameNumber,
        ));
      }
    } else {
      refImageBytesList.add(_buildReferencedImageItem(
        sopInstanceUid: sopInstanceUid,
        frameNumber: frameNumber,
      ));
    }

    // In ReferencedSeriesSequence item: (0008,1140) must come before (0020,000E)
    refSeriesItem.writeSequence(0x0008, 0x1140, refImageBytesList);
    refSeriesItem.writeUi(0x0020, 0x000E, seriesInstanceUid);
    dsBuilder.writeSequence(0x0008, 0x1115, [refSeriesItem.toBytes()]);

    // Group 0010: Patient
    dsBuilder.writePn(0x0010, 0x0010, patientName ?? 'ANONYMOUS');
    dsBuilder.writeLo(0x0010, 0x0020, patientId ?? 'ANON-ID');
    dsBuilder.writeDa(0x0010, 0x0030, patientBirthDate ?? '');
    dsBuilder.writeCs(0x0010, 0x0040, patientSex ?? '');

    // Group 0020: Study & Series
    dsBuilder.writeUi(0x0020, 0x000D, studyInstanceUid); // Study Instance UID
    dsBuilder.writeUi(0x0020, 0x000E, prSeriesUid); // Series Instance UID
    dsBuilder.writeIs(0x0020, 0x0011, '99'); // Series Number
    dsBuilder.writeIs(0x0020, 0x0013, (frameNumber ?? 1).toString()); // Instance Number

    // Group 0028: Softcopy VOI LUT Module (0028,3110) & Top-level Window Center (0028,1050) / Width (0028,1051)
    final topWc = gsps.windowCenter ??
        (gsps.frameStates.isNotEmpty ? gsps.frameStates.first.windowCenter : null);
    final topWw = gsps.windowWidth ??
        (gsps.frameStates.isNotEmpty ? gsps.frameStates.first.windowWidth : null);
    final topExp = gsps.windowCenterWidthExplanation ??
        (gsps.frameStates.isNotEmpty
            ? gsps.frameStates.first.windowCenterWidthExplanation
            : null);

    if (topWc != null && topWw != null) {
      dsBuilder.writeDs(0x0028, 0x1050, topWc.toString());
      dsBuilder.writeDs(0x0028, 0x1051, topWw.toString());
      if (topExp != null && topExp.isNotEmpty) {
        dsBuilder.writeLo(0x0028, 0x1055, topExp);
      }
    }

    final voiItems = <Uint8List>[];
    if (gsps.frameStates.isNotEmpty) {
      for (final fs in gsps.frameStates) {
        final wc = fs.windowCenter ?? gsps.windowCenter;
        final ww = fs.windowWidth ?? gsps.windowWidth;
        final exp = fs.windowCenterWidthExplanation ?? gsps.windowCenterWidthExplanation;
        if (wc != null && ww != null) {
          final voiItem = _DicomElementBuilder(isLittleEndian: true);
          final refImgItem = _buildReferencedImageItem(
            sopInstanceUid: fs.referencedSopInstanceUid,
            frameNumber: fs.referencedFrameNumber,
          );
          voiItem.writeSequence(0x0008, 0x1140, [refImgItem]);
          voiItem.writeDs(0x0028, 0x1050, wc.toString());
          voiItem.writeDs(0x0028, 0x1051, ww.toString());
          if (exp != null && exp.isNotEmpty) {
            voiItem.writeLo(0x0028, 0x1055, exp);
          }
          voiItems.add(voiItem.toBytes());
        }
      }
    } else if (gsps.windowCenter != null && gsps.windowWidth != null) {
      final voiItem = _DicomElementBuilder(isLittleEndian: true);
      final refImgItem = _buildReferencedImageItem(
        sopInstanceUid: sopInstanceUid,
        frameNumber: frameNumber,
      );
      voiItem.writeSequence(0x0008, 0x1140, [refImgItem]);
      voiItem.writeDs(0x0028, 0x1050, gsps.windowCenter!.toString());
      voiItem.writeDs(0x0028, 0x1051, gsps.windowWidth!.toString());
      if (gsps.windowCenterWidthExplanation != null &&
          gsps.windowCenterWidthExplanation!.isNotEmpty) {
        voiItem.writeLo(0x0028, 0x1055, gsps.windowCenterWidthExplanation!);
      }
      voiItems.add(voiItem.toBytes());
    }

    if (voiItems.isNotEmpty) {
      dsBuilder.writeSequence(0x0028, 0x3110, voiItems);
    }

    // Group 0070: Presentation State & Graphic Annotation Modules (strictly ascending tags)
    // 1. (0070,0001) SQ GraphicAnnotationSequence
    final annotationItems = <Uint8List>[];

    if (gsps.frameStates.isNotEmpty) {
      for (final fs in gsps.frameStates) {
        final gObjs =
            GspsPresentationState.annotationsToGraphicObjects(fs.annotations);
        final tObjs = GspsPresentationState.annotationsToTextObjects(
          fs.annotations,
          includeMeasurementReadouts: true,
          pixelSpacing: pixelSpacing,
        );
        if (gObjs.isNotEmpty || tObjs.isNotEmpty) {
          final annItem = _DicomElementBuilder(isLittleEndian: true);
          final refImgItem = _buildReferencedImageItem(
            sopInstanceUid: fs.referencedSopInstanceUid,
            frameNumber: fs.referencedFrameNumber,
          );
          annItem.writeSequence(0x0008, 0x1140, [refImgItem]);
          annItem.writeCs(0x0070, 0x0002, 'LAYER1');

          if (tObjs.isNotEmpty) {
            final tItemBytesList = <Uint8List>[];
            for (final t in tObjs) {
              final tItem = _DicomElementBuilder(isLittleEndian: true);
              tItem.writeSt(0x0070, 0x0006, t.unformattedTextValue);
              if (t.anchorPoint != null) {
                tItem.writeFlList(
                  0x0070,
                  0x0014,
                  [t.anchorPoint!.dx, t.anchorPoint!.dy],
                );
                tItem.writeCs(
                  0x0070,
                  0x0015,
                  t.anchorPointVisible ? 'Y' : 'N',
                );
                tItem.writeCs(
                  0x0070,
                  0x0016,
                  t.anchorUnits,
                );
              }
              tItemBytesList.add(tItem.toBytes());
            }
            annItem.writeSequence(0x0070, 0x0008, tItemBytesList);
          }

          if (gObjs.isNotEmpty) {
            final gItemBytesList = <Uint8List>[];
            for (final g in gObjs) {
              final gItem = _DicomElementBuilder(isLittleEndian: true);
              gItem.writeCs(0x0070, 0x0020, g.units);
              gItem.writeUs(0x0070, 0x0021, g.numberOfPoints);
              gItem.writeFlList(0x0070, 0x0022, g.graphicData);
              gItem.writeCs(0x0070, 0x0023, g.graphicType);
              gItem.writeCs(0x0070, 0x0024, g.filled ? 'Y' : 'N');
              gItemBytesList.add(gItem.toBytes());
            }
            annItem.writeSequence(0x0070, 0x0009, gItemBytesList);
          }

          annotationItems.add(annItem.toBytes());
        }
      }
    }

    if (annotationItems.isEmpty) {
      final gObjs = gsps.toGraphicObjects();
      final tObjs = gsps.toTextObjects(
        includeMeasurementReadouts: true,
        pixelSpacing: pixelSpacing,
      );

      if (gObjs.isNotEmpty || tObjs.isNotEmpty) {
        final annItem = _DicomElementBuilder(isLittleEndian: true);
        final refImgList = <Uint8List>[];
        if (gsps.frameStates.isNotEmpty) {
          for (final fs in gsps.frameStates) {
            refImgList.add(_buildReferencedImageItem(
              sopInstanceUid: fs.referencedSopInstanceUid,
              frameNumber: fs.referencedFrameNumber,
            ));
          }
        } else {
          refImgList.add(_buildReferencedImageItem(
            sopInstanceUid: sopInstanceUid,
            frameNumber: frameNumber,
          ));
        }

        annItem.writeSequence(0x0008, 0x1140, refImgList);
        annItem.writeCs(0x0070, 0x0002, 'LAYER1');

        if (tObjs.isNotEmpty) {
          final tItemBytesList = <Uint8List>[];
          for (final t in tObjs) {
            final tItem = _DicomElementBuilder(isLittleEndian: true);
            tItem.writeSt(0x0070, 0x0006, t.unformattedTextValue);
            if (t.anchorPoint != null) {
              tItem.writeFlList(
                0x0070,
                0x0014,
                [t.anchorPoint!.dx, t.anchorPoint!.dy],
              );
              tItem.writeCs(
                0x0070,
                0x0015,
                t.anchorPointVisible ? 'Y' : 'N',
              );
              tItem.writeCs(
                0x0070,
                0x0016,
                t.anchorUnits,
              );
            }
            tItemBytesList.add(tItem.toBytes());
          }
          annItem.writeSequence(0x0070, 0x0008, tItemBytesList);
        }

        if (gObjs.isNotEmpty) {
          final gItemBytesList = <Uint8List>[];
          for (final g in gObjs) {
            final gItem = _DicomElementBuilder(isLittleEndian: true);
            gItem.writeCs(0x0070, 0x0020, g.units);
            gItem.writeUs(0x0070, 0x0021, g.numberOfPoints);
            gItem.writeFlList(0x0070, 0x0022, g.graphicData);
            gItem.writeCs(0x0070, 0x0023, g.graphicType);
            gItem.writeCs(0x0070, 0x0024, g.filled ? 'Y' : 'N');
            gItemBytesList.add(gItem.toBytes());
          }
          annItem.writeSequence(0x0070, 0x0009, gItemBytesList);
        }

        annotationItems.add(annItem.toBytes());
      }
    }

    if (annotationItems.isNotEmpty) {
      dsBuilder.writeSequence(0x0070, 0x0001, annotationItems);
    }

    // 1.5 (0070,005A) SQ DisplayedAreaSelectionSequence
    final dispItems = <Uint8List>[];
    if (gsps.frameStates.isNotEmpty) {
      for (final fs in gsps.frameStates) {
        final zoomVal = fs.zoom ?? gsps.zoom ?? 1.0;
        final dispItem = _DicomElementBuilder(isLittleEndian: true);
        final refImgItem = _buildReferencedImageItem(
          sopInstanceUid: fs.referencedSopInstanceUid,
          frameNumber: fs.referencedFrameNumber,
        );
        dispItem.writeSequence(0x0008, 0x1140, [refImgItem]);
        dispItem.writeSlList(0x0070, 0x0052, [1, 1]);
        dispItem.writeSlList(0x0070, 0x0053, [512, 512]);
        dispItem.writeCs(0x0070, 0x0100, 'MAGNIFY');
        dispItem.writeFlList(0x0070, 0x0103, [zoomVal]);
        dispItems.add(dispItem.toBytes());
      }
    } else {
      final zoomVal = gsps.zoom ?? 1.0;
      final dispItem = _DicomElementBuilder(isLittleEndian: true);
      final refImgItem = _buildReferencedImageItem(
        sopInstanceUid: sopInstanceUid,
        frameNumber: frameNumber,
      );
      dispItem.writeSequence(0x0008, 0x1140, [refImgItem]);
      dispItem.writeSlList(0x0070, 0x0052, [1, 1]);
      dispItem.writeSlList(0x0070, 0x0053, [512, 512]);
      dispItem.writeCs(0x0070, 0x0100, 'MAGNIFY');
      dispItem.writeFlList(0x0070, 0x0103, [zoomVal]);
      dispItems.add(dispItem.toBytes());
    }

    dsBuilder.writeSequence(0x0070, 0x005A, dispItems);

    // 2. (0070,0060) SQ GraphicLayerSequence
    final layerItem = _DicomElementBuilder(isLittleEndian: true);
    layerItem.writeCs(0x0070, 0x0002, 'LAYER1');
    layerItem.writeIs(0x0070, 0x0062, '1');
    dsBuilder.writeSequence(0x0070, 0x0060, [layerItem.toBytes()]);

    // 3. (0070,0080)-(0070,0084) Presentation State identification
    dsBuilder.writeCs(0x0070, 0x0080, gsps.contentLabel); // Content Label
    if (gsps.contentDescription != null) {
      dsBuilder.writeLo(0x0070, 0x0081, gsps.contentDescription!); // Content Description
    }
    dsBuilder.writeDa(0x0070, 0x0082, nowDa); // Presentation Creation Date
    dsBuilder.writeTm(0x0070, 0x0083, nowTm); // Presentation Creation Time
    if (gsps.contentCreatorName != null) {
      dsBuilder.writePn(0x0070, 0x0084, gsps.contentCreatorName!); // Content Creator Name
    }

    // 4. Group 0079: Private Application Semantics (GOSMART_HEALTH_GSPS_V1)
    // Allows high-fidelity reconstruction of interactive tool semantics (Caliper, Angle, VOI LUT, Zoom, Pan, etc.)
    final semanticsPayload = {
      if (gsps.frameStates.isNotEmpty)
        'frameStates': gsps.frameStates.map((f) => f.toJson()).toList(),
      if (gsps.windowCenter != null) 'windowCenter': gsps.windowCenter,
      if (gsps.windowWidth != null) 'windowWidth': gsps.windowWidth,
      if (gsps.windowCenterWidthExplanation != null)
        'windowCenterWidthExplanation': gsps.windowCenterWidthExplanation,
      if (gsps.zoom != null) 'zoom': gsps.zoom,
      if (gsps.panOffset != null) 'panDx': gsps.panOffset!.dx,
      if (gsps.panOffset != null) 'panDy': gsps.panOffset!.dy,
      'annotations': gsps.annotations.map((a) => a.toJson()).toList(),
    };
    final annotationsJson = jsonEncode(semanticsPayload);
    dsBuilder.writeLo(privateGroup, privateCreatorElement, privateCreatorTag);
    dsBuilder.writeUt(privateGroup, privateSemanticsElement, annotationsJson);

    final datasetBytes = dsBuilder.toBytes();

    // 3. Assemble complete Part 10 file:
    // - 128 bytes 0x00 preamble
    // - 4 bytes ASCII 'DICM'
    // - (0002,0000) UL FileMetaInformationGroupLength
    // - Group 0002 elements
    // - Dataset elements
    final fileBuilder = BytesBuilder(copy: false);
    fileBuilder.add(Uint8List(128)); // 128 zero-byte preamble
    fileBuilder.add(ascii.encode('DICM')); // Magic word DICM

    // Write (0002,0000) UL with length of metaBytes
    final groupLengthHeader = _DicomElementBuilder(isLittleEndian: true);
    groupLengthHeader.writeUl(0x0002, 0x0000, metaBytes.length);
    fileBuilder.add(groupLengthHeader.toBytes());
    fileBuilder.add(metaBytes);
    fileBuilder.add(datasetBytes);

    return fileBuilder.toBytes();
  }

  static Uint8List _buildReferencedImageItem({
    required String sopInstanceUid,
    int? frameNumber,
    String sopClassUid = '1.2.840.10008.5.1.4.1.1.2',
  }) {
    final refImageItem = _DicomElementBuilder(isLittleEndian: true);
    refImageItem.writeUi(0x0008, 0x1150, sopClassUid);
    refImageItem.writeUi(0x0008, 0x1155, sopInstanceUid);
    if (frameNumber != null && frameNumber > 0) {
      refImageItem.writeIs(0x0008, 0x1160, frameNumber.toString());
    }
    return refImageItem.toBytes();
  }

  static String _formatDa(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static String _formatTm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h$m$s';
  }
}

/// Helper for serializing DICOM elements using Explicit VR Little Endian.
class _DicomElementBuilder {
  final BytesBuilder _builder = BytesBuilder(copy: false);
  final bool isLittleEndian;

  _DicomElementBuilder({this.isLittleEndian = true});

  Uint8List toBytes() => _builder.toBytes();

  void writeUi(int group, int element, String value) {
    _writeStringElement(group, element, 'UI', value, padWithNull: true);
  }

  void writeCs(int group, int element, String value) {
    _writeStringElement(group, element, 'CS', value);
  }

  void writeDs(int group, int element, String value) {
    _writeStringElement(group, element, 'DS', value);
  }

  void writeSh(int group, int element, String value) {
    _writeStringElement(group, element, 'SH', value);
  }

  void writeLo(int group, int element, String value) {
    _writeStringElement(group, element, 'LO', value);
  }

  void writePn(int group, int element, String value) {
    _writeStringElement(group, element, 'PN', value);
  }

  void writeSt(int group, int element, String value) {
    _writeStringElement(group, element, 'ST', value);
  }

  void writeUt(int group, int element, String value) {
    List<int> bytes = utf8.encode(value);
    if (bytes.length.isOdd) {
      bytes = List<int>.from(bytes)..add(0x20); // space padding for text
    }
    _writeHeaderLongLength(group, element, 'UT', bytes.length);
    _builder.add(Uint8List.fromList(bytes));
  }

  void writeDa(int group, int element, String value) {
    _writeStringElement(group, element, 'DA', value);
  }

  void writeTm(int group, int element, String value) {
    _writeStringElement(group, element, 'TM', value);
  }

  void writeIs(int group, int element, String value) {
    _writeStringElement(group, element, 'IS', value);
  }

  void writeUs(int group, int element, int value) {
    _writeHeaderShortLength(group, element, 'US', 2);
    final bd = ByteData(2);
    bd.setUint16(0, value, isLittleEndian ? Endian.little : Endian.big);
    _builder.add(bd.buffer.asUint8List());
  }

  void writeUl(int group, int element, int value) {
    _writeHeaderShortLength(group, element, 'UL', 4);
    final bd = ByteData(4);
    bd.setUint32(0, value, isLittleEndian ? Endian.little : Endian.big);
    _builder.add(bd.buffer.asUint8List());
  }

  void writeOb(int group, int element, Uint8List data) {
    // OB has 2 reserved bytes and a 32-bit length
    final paddedLen = data.length + (data.length.isOdd ? 1 : 0);
    _writeHeaderLongLength(group, element, 'OB', paddedLen);
    _builder.add(data);
    if (data.length.isOdd) {
      _builder.addByte(0x00);
    }
  }

  void writeFlList(int group, int element, List<double> floats) {
    final len = floats.length * 4;
    _writeHeaderShortLength(group, element, 'FL', len);
    final bd = ByteData(len);
    for (int i = 0; i < floats.length; i++) {
      bd.setFloat32(i * 4, floats[i], isLittleEndian ? Endian.little : Endian.big);
    }
    _builder.add(bd.buffer.asUint8List());
  }

  void writeSlList(int group, int element, List<int> values) {
    final len = values.length * 4;
    _writeHeaderShortLength(group, element, 'SL', len);
    final bd = ByteData(len);
    for (int i = 0; i < values.length; i++) {
      bd.setInt32(i * 4, values[i], isLittleEndian ? Endian.little : Endian.big);
    }
    _builder.add(bd.buffer.asUint8List());
  }

  void writeSequence(int group, int element, List<Uint8List> items) {
    final paddedItems = <Uint8List>[];
    int totalItemsLength = 0;
    for (final item in items) {
      var itemBytes = item;
      if (itemBytes.length.isOdd) {
        final b = BytesBuilder(copy: false);
        b.add(itemBytes);
        b.addByte(0x00);
        itemBytes = b.toBytes();
      }
      paddedItems.add(itemBytes);
      totalItemsLength += 8 + itemBytes.length;
    }

    // SQ uses 2 reserved bytes + 32-bit length
    _writeHeaderLongLength(group, element, 'SQ', totalItemsLength);

    for (final item in paddedItems) {
      // Item tag: (FFFE,E000)
      final tagBd = ByteData(8);
      tagBd.setUint16(0, 0xFFFE, Endian.little);
      tagBd.setUint16(2, 0xE000, Endian.little);
      tagBd.setUint32(4, item.length, Endian.little);
      _builder.add(tagBd.buffer.asUint8List());
      _builder.add(item);
    }
  }

  void _writeStringElement(
    int group,
    int element,
    String vr,
    String value, {
    bool padWithNull = false,
  }) {
    List<int> bytes = utf8.encode(value);
    if (bytes.length.isOdd) {
      bytes = List<int>.from(bytes)..add(padWithNull ? 0x00 : 0x20);
    }
    _writeHeaderShortLength(group, element, vr, bytes.length);
    _builder.add(Uint8List.fromList(bytes));
  }

  void _writeHeaderShortLength(int group, int element, String vr, int length) {
    final bd = ByteData(8);
    bd.setUint16(0, group, isLittleEndian ? Endian.little : Endian.big);
    bd.setUint16(2, element, isLittleEndian ? Endian.little : Endian.big);
    bd.setUint8(4, vr.codeUnitAt(0));
    bd.setUint8(5, vr.codeUnitAt(1));
    bd.setUint16(6, length, isLittleEndian ? Endian.little : Endian.big);
    _builder.add(bd.buffer.asUint8List());
  }

  void _writeHeaderLongLength(int group, int element, String vr, int length) {
    final bd = ByteData(12);
    bd.setUint16(0, group, isLittleEndian ? Endian.little : Endian.big);
    bd.setUint16(2, element, isLittleEndian ? Endian.little : Endian.big);
    bd.setUint8(4, vr.codeUnitAt(0));
    bd.setUint8(5, vr.codeUnitAt(1));
    bd.setUint16(6, 0, Endian.little); // 2 reserved bytes 0x0000
    bd.setUint32(8, length, isLittleEndian ? Endian.little : Endian.big);
    _builder.add(bd.buffer.asUint8List());
  }
}

