import 'package:flutter/material.dart';
import 'viewport_controller.dart';

/// Clinical DICOM HUD overlays displaying patient demographics, tags, orientation markers, scale,
/// and image index (e.g. Img: 2/128).
class ViewportOverlays extends StatelessWidget {
  final ViewportController controller;

  const ViewportOverlays({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        return IgnorePointer(
          child: Stack(
            children: [
              // Top Left Overlay: Patient & Study Info
              Positioned(
                top: 12,
                left: 12,
                child: _buildOverlayText([
                  if (controller.patientName.isNotEmpty) controller.patientName,
                  if (controller.patientId.isNotEmpty) 'ID: ${controller.patientId}',
                  if (controller.studyDescription.isNotEmpty) controller.studyDescription,
                ]),
              ),

              // Top Right Overlay: Series & Modality Info
              Positioned(
                top: 12,
                right: 12,
                child: _buildOverlayText([
                  if (controller.seriesDescription.isNotEmpty) controller.seriesDescription,
                  if (controller.currentFrame != null)
                    'Dim: ${controller.currentFrame!.width}x${controller.currentFrame!.height}',
                ], crossAxisAlignment: CrossAxisAlignment.end),
              ),

              // Bottom Left Overlay: Window Level Status & Zoom
              Positioned(
                bottom: 12,
                left: 12,
                child: _buildOverlayText([
                  'W: ${controller.windowWidth.toInt()} L: ${controller.windowCenter.toInt()}',
                  if (controller.activePreset != null) 'Preset: ${controller.activePreset!.name}',
                  'Zoom: ${(controller.zoom * 100).toInt()}%',
                ]),
              ),

              // Bottom Right Overlay: Frame / Slice Number (e.g. Img: 2/128 or 2/128)
              if (controller.frameIndex != null)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: _buildOverlayText([
                    controller.totalFrames != null
                        ? 'Img: ${controller.frameIndex} / ${controller.totalFrames}'
                        : 'Img: ${controller.frameIndex}',
                  ], crossAxisAlignment: CrossAxisAlignment.end),
                ),

              // Anatomical Orientation Markers (A / P / L / R)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(child: _buildOrientationMarker('A')),
              ),
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(child: _buildOrientationMarker('P')),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 12,
                child: Center(child: _buildOrientationMarker('R')),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 12,
                child: Center(child: _buildOrientationMarker('L')),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverlayText(List<String> lines, {CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.start}) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: lines
          .map(
            (text) => Text(
              text,
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontSize: 12,
                fontFamily: 'monospace',
                shadows: [
                  Shadow(blurRadius: 3.0, color: Colors.black, offset: Offset(1, 1)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildOrientationMarker(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.yellowAccent,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(blurRadius: 3.0, color: Colors.black, offset: Offset(1, 1)),
        ],
      ),
    );
  }
}
