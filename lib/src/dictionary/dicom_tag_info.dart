/// Model representing an attribute definition from the DICOM standard data dictionary.
class DicomTagInfo {
  /// Standard DICOM tag string in "(GGGG,EEEE)" format, e.g. "(0008,0010)".
  final String tag;

  /// Human-readable name, e.g. "Recognition Code".
  final String name;

  /// DICOM keyword, e.g. "RecognitionCode".
  final String keyword;

  /// Value Representation (VR), e.g. "SH", "CS", "SQ".
  final String valueRepresentation;

  /// Value Multiplicity (VM), e.g. "1", "1-n", "2".
  final String valueMultiplicity;

  /// Whether the tag is retired in the current standard ("Y" or "N").
  final String retired;

  /// 8-character normalized hexadecimal ID without parentheses or commas, e.g. "00080010".
  final String id;

  /// Whether this tag is a DICOM Private Tag (odd group number).
  final bool isPrivate;

  const DicomTagInfo({
    required this.tag,
    required this.name,
    required this.keyword,
    required this.valueRepresentation,
    required this.valueMultiplicity,
    required this.retired,
    required this.id,
    this.isPrivate = false,
  });

  /// Serializes to a JSON-compatible map matching the standard attribute entry format.
  Map<String, dynamic> toJson() {
    return {
      'tag': tag,
      'name': name,
      'keyword': keyword,
      'valueRepresentation': valueRepresentation,
      'valueMultiplicity': valueMultiplicity,
      'retired': retired,
      'id': id,
      if (isPrivate) 'isPrivate': true,
    };
  }

  /// Deserializes from a JSON map.
  factory DicomTagInfo.fromJson(Map<String, dynamic> json) {
    return DicomTagInfo(
      tag: json['tag'] as String? ?? '',
      name: json['name'] as String? ?? '',
      keyword: json['keyword'] as String? ?? '',
      valueRepresentation: json['valueRepresentation'] as String? ?? 'UN',
      valueMultiplicity: json['valueMultiplicity'] as String? ?? '1',
      retired: json['retired'] as String? ?? 'N',
      id: json['id'] as String? ?? '',
      isPrivate: json['isPrivate'] as bool? ?? false,
    );
  }

  @override
  String toString() => '$tag $name [$keyword] VR=$valueRepresentation VM=$valueMultiplicity';
}

