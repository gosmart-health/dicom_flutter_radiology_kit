import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  group('GspsDicomEncoder Tests', () {
    test('UID generator conforms to ITU-T X.667 2.25.x format', () {
      final uid = GspsDicomEncoder.generateDicomUid();
      expect(uid.startsWith('2.25.'), isTrue);
      expect(uid.length, lessThanOrEqualTo(64));
      // Must only contain digits after prefix
      final rest = uid.substring(5);
      expect(RegExp(r'^\d+$').hasMatch(rest), isTrue);
    });

    test('Encodes GSPS Presentation State into valid DICOM Part 10 bytes', () {
      final caliper = CaliperAnnotation(
        id: 'c1',
        start: const Offset(50, 60),
        end: const Offset(120, 150),
        label: 'Lesion Width',
        creatorName: 'Dr. House',
      );

      final circle = CircleAnnotation(
        id: 'circ1',
        center: const Offset(200, 200),
        radius: 30.0,
        label: 'Mass',
        creatorName: 'Dr. House',
      );

      final text = TextAnnotation(
        id: 't1',
        anchor: const Offset(210, 180),
        text: 'Nodule finding',
        creatorName: 'Dr. House',
      );

      final gsps = GspsPresentationState(
        contentLabel: 'TEST_GSPS',
        contentDescription: 'Test clinical annotations',
        contentCreatorName: 'Dr. House',
        annotations: [caliper, circle, text],
      );

      final bytes = gsps.toDicomPart10Bytes(
        studyInstanceUid: '1.2.840.111.222.333',
        seriesInstanceUid: '1.2.840.111.222.333.1',
        sopInstanceUid: '1.2.840.111.222.333.1.5',
        frameNumber: 1,
        patientName: 'TEST^PATIENT',
        patientId: 'PAT-12345',
        studyDate: '20260909',
        studyTime: '120000',
        accessionNumber: 'ACC-001',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(132));

      // 1. Verify 128-byte preamble is all zeros
      for (int i = 0; i < 128; i++) {
        expect(bytes[i], equals(0));
      }

      // 2. Verify DICM magic header at byte 128
      final magic = ascii.decode(bytes.sublist(128, 132));
      expect(magic, equals('DICM'));

      // 3. Verify Group 0002 header (0002,0000) UL
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint16(132, Endian.little), equals(0x0002));
      expect(bd.getUint16(134, Endian.little), equals(0x0000));
      expect(ascii.decode(bytes.sublist(136, 138)), equals('UL'));
      expect(bd.getUint16(138, Endian.little), equals(4));
      final metaLength = bd.getUint32(140, Endian.little);
      expect(metaLength, greaterThan(0));

      // 4. Verify SOP Class UID for GSPS is present in bytes
      final rawStr = String.fromCharCodes(bytes);
      expect(rawStr.contains('1.2.840.10008.5.1.4.1.1.11.1'), isTrue);
      expect(rawStr.contains('1.2.840.10008.1.2.1'), isTrue); // Explicit VR Little Endian
      expect(rawStr.contains('TEST_GSPS'), isTrue);
      expect(rawStr.contains('Dr. House'), isTrue);
      expect(rawStr.contains('Nodule finding'), isTrue);
      expect(rawStr.contains('POLYLINE'), isTrue);
      expect(rawStr.contains('CIRCLE'), isTrue);
    });

    test('Round-trip from standard DICOM JSON to GspsPresentationState', () {
      final dicomJson = {
        '00080018': {'vr': 'UI', 'Value': ['2.25.987654321']},
        '0020000D': {'vr': 'UI', 'Value': ['1.2.3.4.5']},
        '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4.5.1']},
        '00700080': {'vr': 'CS', 'Value': ['WADO_GSPS']},
        '00700081': {'vr': 'LO', 'Value': ['Retrieved state']},
        '00700084': {'vr': 'PN', 'Value': [{'Alphabetic': 'Dr. Specialist'}]},
        '00700082': {'vr': 'DA', 'Value': ['20260909']},
        '00700083': {'vr': 'TM', 'Value': ['083000']},
        '00081115': {
          'vr': 'SQ',
          'Value': [
            {
              '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4.5.1']},
              '00081140': {
                'vr': 'SQ',
                'Value': [
                  {
                    '00081150': {'vr': 'UI', 'Value': ['1.2.840.10008.5.1.4.1.1.2']},
                    '00081155': {'vr': 'UI', 'Value': ['1.2.3.4.5.1.100']},
                    '00081160': {'vr': 'IS', 'Value': ['2']},
                  }
                ]
              }
            }
          ]
        },
        '00700001': {
          'vr': 'SQ',
          'Value': [
            {
              '00700002': {'vr': 'CS', 'Value': ['LAYER1']},
              '00700009': {
                'vr': 'SQ',
                'Value': [
                  {
                    '00700020': {'vr': 'CS', 'Value': ['PIXEL']},
                    '00700021': {'vr': 'US', 'Value': [2]},
                    '00700022': {'vr': 'FL', 'Value': [10.0, 20.0, 80.0, 90.0]},
                    '00700023': {'vr': 'CS', 'Value': ['POLYLINE']},
                    '00700024': {'vr': 'CS', 'Value': ['N']},
                  }
                ]
              },
              '00700008': {
                'vr': 'SQ',
                'Value': [
                  {
                    '00680006': {'vr': 'ST', 'Value': ['Important note']},
                    '00700014': {'vr': 'FL', 'Value': [100.0, 100.0]},
                    '00700015': {'vr': 'CS', 'Value': ['Y']},
                    '00700016': {'vr': 'CS', 'Value': ['PIXEL']},
                  }
                ]
              }
            }
          ]
        }
      };

      final restored = GspsPresentationState.fromDicomJson(dicomJson);
      expect(restored.sopInstanceUid, equals('2.25.987654321'));
      expect(restored.studyInstanceUid, equals('1.2.3.4.5'));
      expect(restored.referencedSeriesUid, equals('1.2.3.4.5.1'));
      expect(restored.referencedSopInstanceUid, equals('1.2.3.4.5.1.100'));
      expect(restored.referencedFrameNumber, equals(2));
      expect(restored.contentLabel, equals('WADO_GSPS'));
      expect(restored.contentCreatorName, equals('Dr. Specialist'));
      expect(restored.annotations.length, equals(2));

      final cal = restored.annotations[0] as CaliperAnnotation;
      expect(cal.start, equals(const Offset(10.0, 20.0)));
      expect(cal.end, equals(const Offset(80.0, 90.0)));

      final txt = restored.annotations[1] as TextAnnotation;
      expect(txt.text, equals('Important note'));
      expect(txt.anchor, equals(const Offset(100.0, 100.0)));
    });

    test('Encodes GSPS file that parses cleanly with dicom-dump CLI', () async {
      final caliper = CaliperAnnotation(
        id: 'c1',
        start: const Offset(50, 60),
        end: const Offset(120, 150),
        label: 'Lesion Width',
        creatorName: 'Dr. House',
      );

      final circle = CircleAnnotation(
        id: 'circ1',
        center: const Offset(222.81, 162.42),
        radius: 35.39,
        label: 'Circle mass',
        creatorName: 'Dr. Radiologist',
      );

      final text = TextAnnotation(
        id: 't1',
        anchor: const Offset(210, 180),
        text: 'Nodule finding',
        creatorName: 'Dr. House',
      );

      final angle = AngleAnnotation(
        id: 'ang1',
        p1: const Offset(10, 100),
        vertex: const Offset(50, 50),
        p2: const Offset(90, 100),
        label: 'Cobb Angle',
        creatorName: 'Dr. House',
      );

      final gsps = GspsPresentationState(
        contentLabel: 'WORKBENCH_PERSIST',
        contentDescription: 'Clinical review marks',
        contentCreatorName: 'Dr. Radiologist',
        annotations: [caliper, circle, text, angle],
      );

      final bytes = GspsDicomEncoder.encodePart10(
        gsps: gsps,
        studyInstanceUid: '2.25.181985773894832491371413605506012585652',
        seriesInstanceUid: '2.25.7760171852783646394485429123781546367',
        sopInstanceUid: '2.25.48928014806509732886906510713826250982',
        frameNumber: 1,
        patientName: 'MOORE_GSH, BETTY',
        patientId: 'GSH-61033769',
        studyDate: '20260909',
        studyTime: '073029',
        accessionNumber: 'GSH-61033770',
      );

      final rawStr = String.fromCharCodes(bytes);
      expect(rawStr.contains('GOSMART_HEALTH_GSPS_V1'), isTrue);

      final tmpDir = await Directory.systemTemp.createTemp('dicom_dump_test');
      final file = File('${tmpDir.path}/test_gsps.dcm');
      await file.writeAsBytes(bytes);

      if (File('/usr/local/bin/dicom-dump').existsSync()) {
        final result = await Process.run('/usr/local/bin/dicom-dump', [file.path]);
        expect(result.exitCode, equals(0), reason: 'dicom-dump failed:\nSTDERR:\n${result.stderr}\nSTDOUT:\n${result.stdout}');
        expect(result.stdout.toString(), contains('WORKBENCH_PERSIST'));
        expect(result.stdout.toString(), contains('GOSMART_HEALTH_GSPS_V1'));
      }
      await tmpDir.delete(recursive: true);
    });

    test('Hydrates Caliper and Angle semantics with 100% fidelity from GOSMART_HEALTH_GSPS_V1 private tag', () {
      final originalCaliper = CaliperAnnotation(
        id: 'cal_custom_99',
        start: const Offset(45.5, 80.2),
        end: const Offset(120.8, 200.4),
        label: 'Tumor Diameter',
        creatorName: 'Dr. Oncologist',
      );

      final originalAngle = AngleAnnotation(
        id: 'angle_custom_42',
        p1: const Offset(30.0, 150.0),
        vertex: const Offset(80.0, 90.0),
        p2: const Offset(140.0, 150.0),
        label: 'Patellar Angle',
        creatorName: 'Dr. Orthopedist',
      );

      final gsps = GspsPresentationState(
        contentLabel: 'SEMANTIC_TEST',
        annotations: [originalCaliper, originalAngle],
      );
      final encodedBytes = gsps.toDicomPart10Bytes(
        studyInstanceUid: '1.2.3',
        seriesInstanceUid: '1.2.3.4',
        sopInstanceUid: '1.2.3.4.5',
      );
      expect(String.fromCharCodes(encodedBytes).contains('GOSMART_HEALTH_GSPS_V1'), isTrue);

      final dicomJson = {
        '00080018': {'vr': 'UI', 'Value': ['2.25.99999']},
        '0020000D': {'vr': 'UI', 'Value': ['1.2.3']},
        '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4']},
        '00700080': {'vr': 'CS', 'Value': ['SEMANTIC_TEST']},
        '00790010': {'vr': 'LO', 'Value': ['GOSMART_HEALTH_GSPS_V1']},
        '00791001': {
          'vr': 'UT',
          'Value': [
            jsonEncode([
              originalCaliper.toJson(),
              originalAngle.toJson(),
            ])
          ]
        },
      };

      final restored = GspsPresentationState.fromDicomJson(dicomJson);
      expect(restored.annotations.length, equals(2));

      expect(restored.annotations[0], isA<CaliperAnnotation>());
      final cal = restored.annotations[0] as CaliperAnnotation;
      expect(cal.id, equals('cal_custom_99'));
      expect(cal.label, equals('Tumor Diameter'));
      expect(cal.start, equals(const Offset(45.5, 80.2)));
      expect(cal.end, equals(const Offset(120.8, 200.4)));
      expect(cal.creatorName, equals('Dr. Oncologist'));

      expect(restored.annotations[1], isA<AngleAnnotation>());
      final ang = restored.annotations[1] as AngleAnnotation;
      expect(ang.id, equals('angle_custom_42'));
      expect(ang.label, equals('Patellar Angle'));
      expect(ang.vertex, equals(const Offset(80.0, 90.0)));
      expect(ang.p1, equals(const Offset(30.0, 150.0)));
      expect(ang.p2, equals(const Offset(140.0, 150.0)));
      expect(ang.creatorName, equals('Dr. Orthopedist'));
    });

    test('Encodes companion measurement readouts in TextObjectSequence with PixelSpacing', () {
      final caliper = CaliperAnnotation(
        id: 'cal1',
        start: const Offset(10, 20),
        end: const Offset(110, 20), // 100 px horizontally
        label: 'Length',
      );
      final angle = AngleAnnotation(
        id: 'ang1',
        p1: const Offset(10, 10),
        vertex: const Offset(10, 50),
        p2: const Offset(50, 50), // 90 degree angle
        label: 'Right Angle',
      );

      final gsps = GspsPresentationState(annotations: [caliper, angle]);
      const spacing = PixelSpacing(rowSpacing: 0.5, columnSpacing: 0.5);

      final textObjs = gsps.toTextObjects(
        includeMeasurementReadouts: true,
        pixelSpacing: spacing,
      );

      expect(textObjs.length, equals(2));
      // Caliper: 100 px * 0.5 mm = 50.0 mm
      expect(textObjs[0].unformattedTextValue, equals('Length: 50.0 mm'));
      expect(textObjs[0].anchorPoint, equals(const Offset(60.0, 20.0))); // Midpoint

      // Angle: 90.0°
      expect(textObjs[1].unformattedTextValue, equals('Right Angle: 90.0°'));
      expect(textObjs[1].anchorPoint, equals(const Offset(10.0, 50.0))); // Vertex
    });

    test('Reconstructs Caliper and Angle labels from companion TextObjects in fallback standard GSPS', () {
      // Standard DICOM GSPS (no private tags), with 2-pt POLYLINE and companion TextObject near midpoint
      final dicomJson = {
        '00080018': {'vr': 'UI', 'Value': ['2.25.11111']},
        '00700001': {
          'vr': 'SQ',
          'Value': [
            {
              '00700002': {'vr': 'CS', 'Value': ['LAYER1']},
              '00700009': {
                'vr': 'SQ',
                'Value': [
                  {
                    '00700020': {'vr': 'CS', 'Value': ['PIXEL']},
                    '00700021': {'vr': 'US', 'Value': [2]},
                    '00700022': {'vr': 'FL', 'Value': [10.0, 20.0, 110.0, 20.0]},
                    '00700023': {'vr': 'CS', 'Value': ['POLYLINE']},
                  },
                  {
                    '00700020': {'vr': 'CS', 'Value': ['PIXEL']},
                    '00700021': {'vr': 'US', 'Value': [3]},
                    '00700022': {'vr': 'FL', 'Value': [10.0, 10.0, 10.0, 50.0, 50.0, 50.0]},
                    '00700023': {'vr': 'CS', 'Value': ['POLYLINE']},
                  }
                ]
              },
              '00700008': {
                'vr': 'SQ',
                'Value': [
                  {
                    '00700006': {'vr': 'ST', 'Value': ['Length: 50.0 mm']},
                    '00700014': {'vr': 'FL', 'Value': [60.0, 20.0]}, // At midpoint of caliper
                  },
                  {
                    '00700006': {'vr': 'ST', 'Value': ['Right Angle: 90.0°']},
                    '00700014': {'vr': 'FL', 'Value': [10.0, 50.0]}, // At vertex of angle
                  },
                  {
                    '00700006': {'vr': 'ST', 'Value': ['Independent Note']},
                    '00700014': {'vr': 'FL', 'Value': [250.0, 250.0]}, // Far away standalone note
                  }
                ]
              }
            }
          ]
        }
      };

      final restored = GspsPresentationState.fromDicomJson(dicomJson);
      // Expected: Caliper with label 'Length: 50.0 mm', Angle with label 'Right Angle: 90.0°', and 1 standalone TextAnnotation
      expect(restored.annotations.length, equals(3));

      expect(restored.annotations[0], isA<CaliperAnnotation>());
      final cal = restored.annotations[0] as CaliperAnnotation;
      expect(cal.label, equals('Length: 50.0 mm'));

      expect(restored.annotations[1], isA<AngleAnnotation>());
      final ang = restored.annotations[1] as AngleAnnotation;
      expect(ang.label, equals('Right Angle: 90.0°'));

      expect(restored.annotations[2], isA<TextAnnotation>());
      final txt = restored.annotations[2] as TextAnnotation;
      expect(txt.text, equals('Independent Note'));
    });

    test('DicomDictionary recognizes private tags 00790010 and 00791001', () {
      final tagCreator = DicomDictionary.lookup('(0079,0010)');
      expect(tagCreator.name, equals('Private Creator (GoSmart Health GSPS)'));
      expect(tagCreator.isPrivate, isTrue);

      final tagSemantics = DicomDictionary.lookup('00791001');
      expect(tagSemantics.name, equals('GoSmart Health GSPS Tool Semantics'));
      expect(tagSemantics.isPrivate, isTrue);
    });

    test('DicomDumpService formats 00791001 displayValue with tool summary', () {
      final dicomJson = {
        '00791001': {
          'vr': 'UT',
          'Value': [
            jsonEncode([
              {'type': 'caliper', 'id': 'c1'},
              {'type': 'caliper', 'id': 'c2'},
              {'type': 'angle', 'id': 'a1'},
            ])
          ]
        }
      };

      final dumpResult = DicomDumpService.dump(dicomJson);
      expect(dumpResult.entries.length, equals(1));
      expect(dumpResult.entries.first.displayValue, equals('3 Tool(s): 2 caliper, 1 angle'));
    });
  });
}

