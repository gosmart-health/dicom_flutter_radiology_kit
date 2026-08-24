import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../imaging/pixel_frame.dart';
import '../imaging/voi_lut.dart';
import 'viewport_controller.dart';
import 'overlays.dart';

/// Flutter StatefulWidget for rendering DICOM frames with zero-jank CanvasKit/Skwasm support.
class DicomViewport extends StatefulWidget {
  final ViewportController controller;
  final bool showOverlay;

  const DicomViewport({
    super.key,
    required this.controller,
    this.showOverlay = true,
  });

  @override
  State<DicomViewport> createState() => _DicomViewportState();
}

class _DicomViewportState extends State<DicomViewport> {
  ui.Image? _renderedImage;
  double? _lastCenter;
  double? _lastWidth;
  PixelFrame? _lastFrame;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _updateRenderedImage();
  }

  @override
  void didUpdateWidget(DicomViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _updateRenderedImage();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _renderedImage?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _updateRenderedImage();
  }

  Future<void> _updateRenderedImage() async {
    final frame = widget.controller.currentFrame;
    final center = widget.controller.windowCenter;
    final width = widget.controller.windowWidth;

    if (frame == null) {
      if (_renderedImage != null) {
        setState(() {
          _renderedImage?.dispose();
          _renderedImage = null;
        });
      }
      return;
    }

    if (frame == _lastFrame && center == _lastCenter && width == _lastWidth && _renderedImage != null) {
      return;
    }

    _lastFrame = frame;
    _lastCenter = center;
    _lastWidth = width;

    final rgbaBytes = VoiLut.applyVoiLut(
      frame: frame,
      windowCenter: center,
      windowWidth: width,
    );

    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(rgbaBytes);
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: frame.width,
      height: frame.height,
      rowBytes: frame.width * 4,
      pixelFormat: ui.PixelFormat.rgba8888,
    );

    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    final ui.Image newImage = frameInfo.image;

    if (mounted) {
      setState(() {
        _renderedImage?.dispose();
        _renderedImage = newImage;
      });
    } else {
      newImage.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, child) {
          return GestureDetector(
            onPanUpdate: (details) {
              // Right-click drag or drag to window-level
              if (details.delta.dx != 0 || details.delta.dy != 0) {
                final newWidth = widget.controller.windowWidth + details.delta.dx * 2.0;
                final newCenter = widget.controller.windowCenter - details.delta.dy * 2.0;
                widget.controller.setWindowLevel(newCenter, newWidth);
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ViewportPainter(
                      image: _renderedImage,
                      zoom: widget.controller.zoom,
                      panOffset: widget.controller.panOffset,
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
    );
  }
}

class _ViewportPainter extends CustomPainter {
  final ui.Image? image;
  final double zoom;
  final Offset panOffset;

  _ViewportPainter({
    required this.image,
    required this.zoom,
    required this.panOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;

    canvas.save();
    canvas.translate(size.width / 2 + panOffset.dx, size.height / 2 + panOffset.dy);
    canvas.scale(zoom, zoom);
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
        oldDelegate.panOffset != panOffset;
  }
}
