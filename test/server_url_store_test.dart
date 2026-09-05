import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

void main() {
  setUp(() {
    DicomServerUrlStore.clear();
  });

  tearDown(() {
    DicomServerUrlStore.clear();
  });

  group('DicomServerUrlStore', () {
    test('returns default server URL when history is empty', () {
      expect(DicomServerUrlStore.getHistory(), equals(['http://localhost:8000']));
      expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://localhost:8000'));
    });

    test('records URL and updates last used URL', () {
      DicomServerUrlStore.recordUrl('http://pacs1.hospital.org:8042/dicom-web');

      expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://pacs1.hospital.org:8042/dicom-web'));
      expect(DicomServerUrlStore.getHistory(), contains('http://pacs1.hospital.org:8042/dicom-web'));
    });

    test('maintains order with newest recorded URL at index 0', () {
      DicomServerUrlStore.recordUrl('http://server-a.com');
      DicomServerUrlStore.recordUrl('http://server-b.com');
      DicomServerUrlStore.recordUrl('http://server-c.com');

      final history = DicomServerUrlStore.getHistory();
      expect(history[0], equals('http://server-c.com'));
      expect(history[1], equals('http://server-b.com'));
      expect(history[2], equals('http://server-a.com'));
      expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://server-c.com'));
    });

    test('caps history to past 5 entries', () {
      for (int i = 1; i <= 7; i++) {
        DicomServerUrlStore.recordUrl('http://server-$i.com');
      }

      final history = DicomServerUrlStore.getHistory();
      expect(history.length, equals(5));
      expect(history, equals([
        'http://server-7.com',
        'http://server-6.com',
        'http://server-5.com',
        'http://server-4.com',
        'http://server-3.com',
      ]));
      expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://server-7.com'));
    });

    test('deduplicates URL by moving existing entry to index 0', () {
      DicomServerUrlStore.recordUrl('http://server-1.com');
      DicomServerUrlStore.recordUrl('http://server-2.com');
      DicomServerUrlStore.recordUrl('http://server-3.com');

      // Re-record server-1
      DicomServerUrlStore.recordUrl('http://server-1.com');

      final history = DicomServerUrlStore.getHistory();
      expect(history.length, equals(3));
      expect(history[0], equals('http://server-1.com'));
      expect(history[1], equals('http://server-3.com'));
      expect(history[2], equals('http://server-2.com'));
    });

    test('trims whitespace and ignores empty URLs', () {
      DicomServerUrlStore.recordUrl('   http://server-trimmed.com   ');
      expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://server-trimmed.com'));

      DicomServerUrlStore.recordUrl('   ');
      expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://server-trimmed.com'));
    });

    test('clear resets history back to default', () {
      DicomServerUrlStore.recordUrl('http://temp-server.com');
      expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://temp-server.com'));

      DicomServerUrlStore.clear();
      expect(DicomServerUrlStore.getHistory(), equals(['http://localhost:8000']));
      expect(DicomServerUrlStore.getLastUsedUrl(), equals('http://localhost:8000'));
    });
  });
}

