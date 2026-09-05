import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../imaging/pixel_frame.dart';
import '../imaging/voi_lut.dart';
import 'viewport_controller.dart';
import 'viewport_gesture_detector.dart';
import 'overlays.dart';

/// Flutter StatefulWidget for rendering DICOM frames with zero-jank CanvasKit/Skwasm support.
class DicomViewport extends StatefulWidget {
  final ViewportController controller;
  final bool showOverlay;

  /// Optional inner padding/inset applied when auto-fitting frames inside the viewport bounds.
  final EdgeInsets inset;

  const DicomViewport({
    super.key,
    required this.controller,
    this.showOverlay = true,
    this.inset = const EdgeInsets.all(4.0),
  });

  @override
  State<DicomViewport> createState() => _DicomViewportState();
}

class _DicomViewportState extends State<DicomViewport> {
  ui.Image? _renderedImage;
  PixelFrame? _lastFrame;
  double? _lastCenter;
  double? _lastWidth;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _updateRenderedImage();
  }

  @override
  void didUpdateWidget(covariant DicomViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _updateRenderedImage();
    }
  }

  final List<ui.Image> _disposableImages = [];

  void _disposeImageLater(ui.Image? image) {
    if (image == null) return;
    if (kIsWeb) {
      // On Flutter Web with Skwasm, manual ui.Image.dispose() deallocates
      // the underlying SkImage from the WASM linear memory heap while
      // worker rasterizers (surface_renderPicturesOnWorker) may still be executing,
      // leading to "RuntimeError: memory access out of bounds".
      // SkwasmImage uses DomFinalizationRegistry to automatically and safely
      // collect the image once Dart GC reclaims it.
      return;
    }
    _disposableImages.add(image);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final img in _disposableImages) {
        try {
          img.dispose();
        } catch (_) {}
      }
      _disposableImages.clear();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    if (!kIsWeb) {
      for (final img in _disposableImages) {
        try {
          img.dispose();
        } catch (_) {}
      }
      _disposableImages.clear();
      _renderedImage?.dispose();
    }
    super.dispose();
  }

  bool _isRendering = false;
  bool _needsRender = false;

  void _onControllerChanged() {
    _updateRenderedImage();
  }

  Future<void> _updateRenderedImage() async {
    if (_isRendering) {
      _needsRender = true;
      return;
    }
    _isRendering = true;

    try {
      do {
        _needsRender = false;
        final frame = widget.controller.currentFrame;
        final center = widget.controller.windowCenter;
        final width = widget.controller.windowWidth;

        if (frame == null) {
          if (_renderedImage != null) {
            final oldImage = _renderedImage;
            setState(() {
              _renderedImage = null;
            });
            _disposeImageLater(oldImage);
          }
          continue;
        }

        if (frame == _lastFrame && center == _lastCenter && width == _lastWidth && _renderedImage != null) {
          continue;
        }

        _lastFrame = frame;
        _lastCenter = center;
        _lastWidth = width;

        final sw = Stopwatch()..start();
        final rgbaBytes = VoiLut.applyVoiLut(
          frame: frame,
          windowCenter: center,
          windowWidth: width,
        );

        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          rgbaBytes,
          frame.width,
          frame.height,
          ui.PixelFormat.rgba8888,
          (ui.Image img) {
            completer.complete(img);
          },
        );

        final ui.Image newImage = await completer.future;
        sw.stop();

        if (mounted) {
          final oldImage = _renderedImage;
          setState(() {
            _renderedImage = newImage;
          });
          _disposeImageLater(oldImage);
        } else {
          if (!kIsWeb) {
            newImage.dispose();
          }
        }
      } while (_needsRender);
    } catch (e) {
      debugPrint('[DICOM-VIEWPORT] Error rendering frame: $e');
    } finally {
      _isRendering = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: Container(
        color: Colors.black,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, child) {
            return ViewportGestureDetector(
              controller: widget.controller,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ViewportPainter(
                        image: _renderedImage,
                        zoom: widget.controller.zoom,
                        panOffset: widget.controller.panOffset,
                        inset: widget.inset,
                      ),
                    ),
                  ),
                  if (widget.showOverlay)
                    Positioned.fill(
                      child: ViewportOverlays(controller: widget.controller),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ViewportPainter extends CustomPainter {
  final ui.Image? image;
  final double zoom;
  final Offset panOffset;
  final EdgeInsets inset;

  _ViewportPainter({
    required this.image,
    required this.zoom,
    required this.panOffset,
    required this.inset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null || size.isEmpty) return;

    // Strict clipping to the viewport bounds
    canvas.clipRect(Offset.zero & size);

    // Compute aspect-ratio-preserving fit scale
    final availableWidth = (size.width - inset.horizontal).clamp(1.0, double.infinity);
    final availableHeight = (size.height - inset.vertical).clamp(1.0, double.infinity);
    final double scaleX = availableWidth / image!.width;
    final double scaleY = availableHeight / image!.height;
    final double fitScale = math.min(scaleX, scaleY);
    final double effectiveScale = fitScale * zoom;

    canvas.save();
    canvas.translate(size.width / 2.0 + panOffset.dx, size.height / 2.0 + panOffset.dy);
    canvas.scale(effectiveScale, effectiveScale);
    canvas.translate(-image!.width / 2.0, -image!.height / 2.0);

    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..isAntiAlias = true;

    canvas.drawImage(image!, Offset.zero, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ViewportPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.zoom != zoom ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.inset != inset;
  }
}

