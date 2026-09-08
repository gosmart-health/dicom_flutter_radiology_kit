/// Drop-in medical imaging kit for Flutter Web & Desktop.
library dicom_flutter_radiology_kit;

// Client & Buffers
export 'src/client/dicom_web_client.dart';
export 'src/client/multipart_stream.dart';
export 'src/client/qido_models.dart';
export 'src/client/series_buffer.dart';

// Codecs
export 'src/codecs/decoder_interface.dart';
export 'src/codecs/wasm_worker_bridge.dart';
export 'src/codecs/codec_router.dart';

// Imaging
export 'src/imaging/pixel_frame.dart';
export 'src/imaging/pixel_spacing.dart';
export 'src/imaging/presentation_state.dart';
export 'src/imaging/voi_lut.dart';
export 'src/imaging/window_presets.dart';

// Annotations
export 'src/annotations/annotation_model.dart';
export 'src/annotations/annotation_style.dart';
export 'src/annotations/annotation_transform.dart';
export 'src/annotations/annotation_painter.dart';
export 'src/annotations/annotation_controller.dart';
export 'src/annotations/dicom_annotation_layer.dart';
export 'src/annotations/gsps_codec.dart';

// Widgets
export 'src/widgets/dicom_viewport.dart';
export 'src/widgets/viewport_controller.dart';
export 'src/widgets/viewport_gesture_detector.dart';
export 'src/widgets/overlays.dart';
export 'src/widgets/qido_browser_dialog.dart';
export 'src/widgets/dicom_dump_widget.dart';

// Persistence
export 'src/persistence/server_url_store.dart';

// Dictionary & Dump
export 'src/dictionary/dicom_tag_info.dart';
export 'src/dictionary/dicom_dictionary.g.dart';
export 'src/dump/dicom_dump_models.dart';
export 'src/dump/dicom_dump_service.dart';
