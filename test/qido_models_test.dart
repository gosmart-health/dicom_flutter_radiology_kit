import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_web_kit/dicom_web_kit.dart';

void main() {
  group('DICOM JSON & QIDO Models', () {
    test('DicomJsonHelper parses person names correctly', () {
      expect(DicomJsonHelper.formatPersonName('DOE^JOHN^^^MD'), 'DOE, JOHN MD');
      expect(DicomJsonHelper.formatPersonName('DOE^JOHN'), 'DOE, JOHN');
      expect(DicomJsonHelper.formatPersonName('SMITH^JANE^A'), 'SMITH, JANE A');
      expect(DicomJsonHelper.formatPersonName('SINGLE'), 'SINGLE');
      expect(DicomJsonHelper.formatPersonName(''), 'Anonymous');
      expect(DicomJsonHelper.formatPersonName(null), 'Anonymous');
    });

    test('DicomJsonHelper formats dates and datetimes to ISO', () {
      expect(DicomJsonHelper.formatIsoDate('20260901'), '2026-09-01');
      expect(DicomJsonHelper.formatIsoDate('19850315'), '1985-03-15');
      expect(DicomJsonHelper.formatIsoDateTime('20260901', '094644'), '2026-09-01T09:46:44');
      expect(DicomJsonHelper.formatIsoDateTime('20260901', '1430'), '2026-09-01T14:30:00');
    });

    test('DicomStudy parses DICOM JSON tag dictionary correctly', () {
      final studyJson = {
        '0020000D': {'vr': 'UI', 'Value': ['1.2.3.4.5.6.7']},
        '00100010': {'vr': 'PN', 'Value': [{'Alphabetic': 'GREEN^JOSEPH^^^MD'}]},
        '00100020': {'vr': 'LO', 'Value': ['GSH-78624794']},
        '00100030': {'vr': 'DA', 'Value': ['19600101']},
        '00080050': {'vr': 'SH', 'Value': ['ACC-12345']},
        '00080020': {'vr': 'DA', 'Value': ['20260901']},
        '00080030': {'vr': 'TM', 'Value': ['094644']},
        '00080061': {'vr': 'CS', 'Value': ['CT']},
        '00081030': {'vr': 'LO', 'Value': ['CT Extremity Lower Right']},
        '00201206': {'vr': 'IS', 'Value': [2]},
        '00201208': {'vr': 'IS', 'Value': [40]},
      };

      final study = DicomStudy.fromJson(studyJson);
      expect(study.studyInstanceUID, '1.2.3.4.5.6.7');
      expect(study.patientName, 'GREEN, JOSEPH MD');
      expect(study.patientId, 'GSH-78624794');
      expect(study.patientBirthDate, '1960-01-01');
      expect(study.accessionNumber, 'ACC-12345');
      expect(study.studyDateTimeIso, '2026-09-01T09:46:44');
      expect(study.modality, 'CT');
      expect(study.studyDescription, 'CT Extremity Lower Right');
      expect(study.numberOfSeries, 2);
      expect(study.numberOfInstances, 40);
    });

    test('DicomSeries parses series metadata correctly', () {
      final seriesJson = {
        '0020000D': {'vr': 'UI', 'Value': ['1.2.3.4.5.6.7']},
        '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4.5.6.7.1']},
        '00080060': {'vr': 'CS', 'Value': ['CT']},
        '00200011': {'vr': 'IS', 'Value': [1]},
        '0008103E': {'vr': 'LO', 'Value': ['Axial 5mm']},
        '00081050': {'vr': 'PN', 'Value': [{'Alphabetic': 'TAYLOR^RICHARD'}]},
        '00201209': {'vr': 'IS', 'Value': [20]},
      };

      final series = DicomSeries.fromJson(seriesJson);
      expect(series.seriesInstanceUID, '1.2.3.4.5.6.7.1');
      expect(series.studyInstanceUID, '1.2.3.4.5.6.7');
      expect(series.modality, 'CT');
      expect(series.seriesNumber, 1);
      expect(series.seriesDescription, 'Axial 5mm');
      expect(series.numberOfInstances, 20);
      expect(series.performingPhysician, 'TAYLOR, RICHARD');
    });

    test('DicomInstanceSummary parses instance metadata tags', () {
      final instanceJson = {
        '00080018': {'vr': 'UI', 'Value': ['1.2.3.4.5.6.7.1.1']},
        '00080016': {'vr': 'UI', 'Value': ['1.2.840.10008.5.1.4.1.1.2']},
        '00200013': {'vr': 'IS', 'Value': [1]},
        '00280010': {'vr': 'US', 'Value': [512]},
        '00280011': {'vr': 'US', 'Value': [512]},
        '00280100': {'vr': 'US', 'Value': [16]},
        '00280101': {'vr': 'US', 'Value': [12]},
        '00280102': {'vr': 'US', 'Value': [11]},
        '00280103': {'vr': 'US', 'Value': [0]},
        '00281052': {'vr': 'DS', 'Value': [-1024.0]},
        '00281053': {'vr': 'DS', 'Value': [1.0]},
        '00281050': {'vr': 'DS', 'Value': [40.0]},
        '00281051': {'vr': 'DS', 'Value': [400.0]},
        '00280004': {'vr': 'CS', 'Value': ['MONOCHROME2']},
      };

      final summary = DicomInstanceSummary.fromJson(instanceJson);
      expect(summary.sopInstanceUID, '1.2.3.4.5.6.7.1.1');
      expect(summary.rows, 512);
      expect(summary.columns, 512);
      expect(summary.bitsAllocated, 16);
      expect(summary.bitsStored, 12);
      expect(summary.isSigned, false);
      expect(summary.rescaleIntercept, -1024.0);
      expect(summary.rescaleSlope, 1.0);
      expect(summary.windowCenter, 40.0);
      expect(summary.windowWidth, 400.0);
    });

    test('DicomWebClient normalizes URLs properly', () {
      expect(DicomWebClient.normalizeBaseUrl('http://localhost:8000'), 'http://localhost:8000/dicomweb');
      expect(DicomWebClient.normalizeBaseUrl('http://localhost:8000/'), 'http://localhost:8000/dicomweb');
      expect(DicomWebClient.normalizeBaseUrl('http://localhost:8000/dicomweb'), 'http://localhost:8000/dicomweb');
      expect(
        DicomWebClient.normalizeBaseUrl('https://server.dcmjs.org/dcm4chee-arc/aets/DCM4CHEE/rs'),
        'https://server.dcmjs.org/dcm4chee-arc/aets/DCM4CHEE/rs',
      );
    });
  });
}

