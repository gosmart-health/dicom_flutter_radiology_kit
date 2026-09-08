import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  group('DICOM Data Dictionary Tests', () {
    test('Dictionary contains expected standard tags (> 5,000)', () {
      expect(DicomDictionary.standardTagCount, greaterThan(5000));
    });

    test('Resolves standard tag (0008,0010) matching user requested schema', () {
      final tagInfo = DicomDictionary.lookup('(0008,0010)');
      expect(tagInfo.tag, '(0008,0010)');
      expect(tagInfo.name, 'Recognition Code');
      expect(tagInfo.keyword, 'RecognitionCode');
      expect(tagInfo.valueRepresentation, 'SH');
      expect(tagInfo.valueMultiplicity, '1');
      expect(tagInfo.retired, 'Y');
      expect(tagInfo.id, '00080010');
      expect(tagInfo.isPrivate, isFalse);

      final json = tagInfo.toJson();
      expect(json, {
        'tag': '(0008,0010)',
        'name': 'Recognition Code',
        'keyword': 'RecognitionCode',
        'valueRepresentation': 'SH',
        'valueMultiplicity': '1',
        'retired': 'Y',
        'id': '00080010',
      });
    });

    test('Resolves normalized 8-char hex tag ID "00100010"', () {
      final tagInfo = DicomDictionary.lookup('00100010');
      expect(tagInfo.tag, '(0010,0010)');
      expect(tagInfo.name, "Patient's Name");
      expect(tagInfo.keyword, 'PatientName');
      expect(tagInfo.valueRepresentation, 'PN');
      expect(tagInfo.retired, 'N');
    });

    test('Resolves repeating group wildcards (50xx and 60xx)', () {
      final curve = DicomDictionary.lookup('50000005');
      expect(curve.name, 'Curve Dimensions');
      expect(curve.tag, '(5000,0005)');
      expect(curve.valueRepresentation, 'US');

      final overlay = DicomDictionary.lookup('(6000,0010)');
      expect(overlay.name, 'Overlay Rows');
      expect(overlay.tag, '(6000,0010)');
      expect(overlay.valueRepresentation, 'US');
    });

    test('Resolves Private Creator and Private Data tags', () {
      final creator = DicomDictionary.lookup('(0009,0010)');
      expect(creator.isPrivate, isTrue);
      expect(creator.name, 'Private Creator');
      expect(creator.keyword, 'PrivateCreator');
      expect(creator.valueRepresentation, 'LO');

      final privateData = DicomDictionary.lookup('00191020', vr: 'OB');
      expect(privateData.isPrivate, isTrue);
      expect(privateData.name, 'Private Tag');
      expect(privateData.keyword, 'PrivateTag');
      expect(privateData.valueRepresentation, 'OB');
    });
  });

  group('DicomDumpService Enriched JSON & Structured Dump Tests', () {
    final sampleDicomJson = {
      '00080010': {
        'vr': 'SH',
        'Value': ['TEST_RECOG_001'],
      },
      '00100010': {
        'vr': 'PN',
        'Value': [
          {'Alphabetic': 'DOE^JOHN^J'},
        ],
      },
      '00100020': {
        'vr': 'LO',
        'Value': ['PID-12345'],
      },
      '0020000D': {
        'vr': 'UI',
        'Value': ['1.2.840.113619.2.1.2.3.4'],
      },
      '00081032': {
        'vr': 'SQ',
        'Value': [
          {
            '00080100': {
              'vr': 'SH',
              'Value': ['CODE-123'],
            },
            '00080104': {
              'vr': 'LO',
              'Value': ['Chest CT Examination'],
            },
          }
        ],
      },
      '00091001': {
        'vr': 'LO',
        'Value': ['Custom Private Value'],
      },
    };

    test('dumpJson enriches DICOM JSON with description attribute definition', () {
      final enriched = DicomDumpService.dumpJson(sampleDicomJson);

      expect(enriched.containsKey('00080010'), isTrue);
      final entry00080010 = enriched['00080010'] as Map<String, dynamic>;
      expect(entry00080010['description'], {
        'tag': '(0008,0010)',
        'name': 'Recognition Code',
        'keyword': 'RecognitionCode',
        'valueRepresentation': 'SH',
        'valueMultiplicity': '1',
        'retired': 'Y',
        'id': '00080010',
      });

      // Check nested Sequence enrichment
      final seq = enriched['00081032'] as Map<String, dynamic>;
      final seqItems = seq['Value'] as List;
      expect(seqItems.length, 1);
      final childItem = seqItems[0] as Map<String, dynamic>;
      expect(childItem['00080100']['description']['name'], 'Code Value');
      expect(childItem['00080104']['description']['name'], 'Code Meaning');

      // Check Private tag
      final privateItem = enriched['00091001'] as Map<String, dynamic>;
      expect(privateItem['description']['isPrivate'], isTrue);
      expect(privateItem['description']['name'], 'Private Tag');
    });

    test('dump produces structured DicomDumpResult with formatted values and search', () {
      final result = DicomDumpService.dump(sampleDicomJson);
      expect(result.count, 6);

      final pnEntry = result.entries.firstWhere((e) => e.tagHex == '00100010');
      expect(pnEntry.displayValue, 'DOE^JOHN^J');
      expect(pnEntry.description.name, "Patient's Name");

      final sqEntry = result.entries.firstWhere((e) => e.tagHex == '00081032');
      expect(sqEntry.isSequence, isTrue);
      expect(sqEntry.sequenceItems?.length, 1);
      expect(sqEntry.sequenceItems![0].length, 2);

      // Search functionality
      final searchByName = result.search('Patient');
      expect(searchByName.any((e) => e.tagHex == '00100010'), isTrue);

      final searchByCode = result.search('Chest CT');
      expect(searchByCode.any((e) => e.tagHex == '00080104'), isTrue);

      final searchByPrivate = result.search('Custom Private');
      expect(searchByPrivate.any((e) => e.tagHex == '00091001'), isTrue);
    });
  });
}

