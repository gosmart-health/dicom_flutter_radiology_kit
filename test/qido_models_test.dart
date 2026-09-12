import 'package:flutter_test/flutter_test.dart';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

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
      expect(DicomJsonHelper.formatIsoDateTime('20260901', '094644'),
          '2026-09-01T09:46:44');
      expect(DicomJsonHelper.formatIsoDateTime('20260901', '1430'),
          '2026-09-01T14:30:00');
    });

    test('DicomStudy parses DICOM JSON tag dictionary correctly', () {
      final studyJson = {
        '0020000D': {
          'vr': 'UI',
          'Value': ['1.2.3.4.5.6.7']
        },
        '00100010': {
          'vr': 'PN',
          'Value': [
            {'Alphabetic': 'GREEN^JOSEPH^^^MD'}
          ]
        },
        '00100020': {
          'vr': 'LO',
          'Value': ['GSH-78624794']
        },
        '00100030': {
          'vr': 'DA',
          'Value': ['19600101']
        },
        '00080050': {
          'vr': 'SH',
          'Value': ['ACC-12345']
        },
        '00080020': {
          'vr': 'DA',
          'Value': ['20260901']
        },
        '00080030': {
          'vr': 'TM',
          'Value': ['094644']
        },
        '00080061': {
          'vr': 'CS',
          'Value': ['CT']
        },
        '00081030': {
          'vr': 'LO',
          'Value': ['CT Extremity Lower Right']
        },
        '00201206': {
          'vr': 'IS',
          'Value': [2]
        },
        '00201208': {
          'vr': 'IS',
          'Value': [40]
        },
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
        '0020000D': {
          'vr': 'UI',
          'Value': ['1.2.3.4.5.6.7']
        },
        '0020000E': {
          'vr': 'UI',
          'Value': ['1.2.3.4.5.6.7.1']
        },
        '00080060': {
          'vr': 'CS',
          'Value': ['CT']
        },
        '00200011': {
          'vr': 'IS',
          'Value': [1]
        },
        '0008103E': {
          'vr': 'LO',
          'Value': ['Axial 5mm']
        },
        '00081050': {
          'vr': 'PN',
          'Value': [
            {'Alphabetic': 'TAYLOR^RICHARD'}
          ]
        },
        '00201209': {
          'vr': 'IS',
          'Value': [20]
        },
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

    test('DicomSeries parses PresentationCreationDate (0070,0082) and PresentationCreationTime (0070,0083)', () {
      final prSeriesJson = {
        '0020000D': {
          'vr': 'UI',
          'Value': ['1.2.3.4.5.6.7']
        },
        '0020000E': {
          'vr': 'UI',
          'Value': ['1.2.3.4.5.6.7.PR1']
        },
        '00080060': {
          'vr': 'CS',
          'Value': ['PR']
        },
        '00200011': {
          'vr': 'IS',
          'Value': [101]
        },
        '0008103E': {
          'vr': 'LO',
          'Value': ['GSPS PR Annotations']
        },
        '00700082': {
          'vr': 'DA',
          'Value': ['20260909']
        },
        '00700083': {
          'vr': 'TM',
          'Value': ['164053']
        },
      };

      final series = DicomSeries.fromJson(prSeriesJson);
      expect(series.presentationCreationDate, '20260909');
      expect(series.presentationCreationTime, '164053');
      expect(series.presentationCreationDateTimeIso, '2026-09-09T16:40:53');
      expect(series.dateTimeIso, '2026-09-09T16:40:53');
      expect(series.dateTimeSortKey, '20260909164053');
    });

    test('DicomInstanceSummary parses instance metadata tags', () {
      final instanceJson = {
        '00080018': {
          'vr': 'UI',
          'Value': ['1.2.3.4.5.6.7.1.1']
        },
        '00080016': {
          'vr': 'UI',
          'Value': ['1.2.840.10008.5.1.4.1.1.2']
        },
        '00200013': {
          'vr': 'IS',
          'Value': [1]
        },
        '00280010': {
          'vr': 'US',
          'Value': [512]
        },
        '00280011': {
          'vr': 'US',
          'Value': [512]
        },
        '00280100': {
          'vr': 'US',
          'Value': [16]
        },
        '00280101': {
          'vr': 'US',
          'Value': [12]
        },
        '00280102': {
          'vr': 'US',
          'Value': [11]
        },
        '00280103': {
          'vr': 'US',
          'Value': [0]
        },
        '00281052': {
          'vr': 'DS',
          'Value': [-1024.0]
        },
        '00281053': {
          'vr': 'DS',
          'Value': [1.0]
        },
        '00281050': {
          'vr': 'DS',
          'Value': [40.0]
        },
        '00281051': {
          'vr': 'DS',
          'Value': [400.0]
        },
        '00280004': {
          'vr': 'CS',
          'Value': ['MONOCHROME2'],
        },
        '00280030': {
          'vr': 'DS',
          'Value': [0.661468, 0.661468],
        },
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
      expect(summary.pixelSpacing, isNotNull);
      expect(summary.pixelSpacing!.rowSpacing, closeTo(0.661468, 1e-6));
      expect(summary.pixelSpacing!.columnSpacing, closeTo(0.661468, 1e-6));
    });

    test('DicomInstanceSummary parses various Pixel Spacing and fallback formats', () {
      // String list
      final json1 = {
        '00280030': {
          'vr': 'DS',
          'Value': ['0.75', '0.85']
        }
      };
      final s1 = DicomInstanceSummary.fromJson(json1);
      expect(s1.pixelSpacing?.rowSpacing, closeTo(0.75, 1e-6));
      expect(s1.pixelSpacing?.columnSpacing, closeTo(0.85, 1e-6));

      // Single string with backslash
      final json2 = {
        '00280030': {
          'vr': 'DS',
          'Value': ['0.5\\0.5']
        }
      };
      final s2 = DicomInstanceSummary.fromJson(json2);
      expect(s2.pixelSpacing?.rowSpacing, closeTo(0.5, 1e-6));
      expect(s2.pixelSpacing?.columnSpacing, closeTo(0.5, 1e-6));

      // Fallback: Imager Pixel Spacing (0018,1164)
      final json3 = {
        '00181164': {
          'vr': 'DS',
          'Value': [0.14, 0.14]
        }
      };
      final s3 = DicomInstanceSummary.fromJson(json3);
      expect(s3.pixelSpacing?.rowSpacing, closeTo(0.14, 1e-6));
      expect(s3.pixelSpacing?.columnSpacing, closeTo(0.14, 1e-6));

      // Fallback: Shared Functional Groups Sequence (5200,9229)
      final json4 = {
        '52009229': {
          'vr': 'SQ',
          'Value': [
            {
              '00289110': {
                'vr': 'SQ',
                'Value': [
                  {
                    '00280030': {
                      'vr': 'DS',
                      'Value': [0.625, 0.625]
                    }
                  }
                ]
              }
            }
          ]
        }
      };
      final s4 = DicomInstanceSummary.fromJson(json4);
      expect(s4.pixelSpacing?.rowSpacing, closeTo(0.625, 1e-6));
      expect(s4.pixelSpacing?.columnSpacing, closeTo(0.625, 1e-6));
    });

    test('DicomWebClient normalizes URLs properly', () {
      expect(DicomWebClient.normalizeBaseUrl('http://localhost:8000'),
          'http://localhost:8000/dicomweb');
      expect(DicomWebClient.normalizeBaseUrl('http://localhost:8000/'),
          'http://localhost:8000/dicomweb');
      expect(
        DicomWebClient.normalizeBaseUrl(
            'https://server.dcmjs.org/dcm4chee-arc/aets/DCM4CHEE/rs'),
        'https://server.dcmjs.org/dcm4chee-arc/aets/DCM4CHEE/rs',
      );
    });

    test('DicomSeries.isImageSeries detects image vs non-image presentation state series', () {
      final ctSeries = DicomSeries.fromJson({
        '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4.1']},
        '00080060': {'vr': 'CS', 'Value': ['CT']},
      });
      expect(ctSeries.isImageSeries, isTrue);

      final prSeries = DicomSeries.fromJson({
        '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4.2']},
        '00080060': {'vr': 'CS', 'Value': ['PR']},
      });
      expect(prSeries.isImageSeries, isFalse);

      final srSeries = DicomSeries.fromJson({
        '0020000E': {'vr': 'UI', 'Value': ['1.2.3.4.3']},
        '00080060': {'vr': 'CS', 'Value': ['SR']},
      });
      expect(srSeries.isImageSeries, isFalse);
    });

    test('DicomInstanceSummary.isImage identifies GSPS as non-image', () {
      final imgInst = DicomInstanceSummary.fromJson({
        '00080018': {'vr': 'UI', 'Value': ['1.2.3.4.1.1']},
        '00080016': {'vr': 'UI', 'Value': ['1.2.840.10008.5.1.4.1.1.2']}, // CT Image
        '00080060': {'vr': 'CS', 'Value': ['CT']},
      });
      expect(imgInst.isImage, isTrue);

      final gspsInst = DicomInstanceSummary.fromJson({
        '00080018': {'vr': 'UI', 'Value': ['1.2.3.4.2.1']},
        '00080016': {'vr': 'UI', 'Value': ['1.2.840.10008.5.1.4.1.1.11.1']}, // GSPS
        '00080060': {'vr': 'CS', 'Value': ['PR']},
      });
      expect(gspsInst.isImage, isFalse);
    });
  });
}
