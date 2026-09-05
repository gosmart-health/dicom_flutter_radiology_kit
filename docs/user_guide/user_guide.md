# DICOM Flutter Radiology Kit — User Guide

Welcome to the `dicom_flutter_radiology_kit` user guide. This guide outlines the multimodal viewport controls, mouse bindings, and touch gestures designed for clinical review workstations on desktop and touch-screen devices (tablets and mobile).

---

## 1. Viewport Interaction Model

The radiology viewport supports two primary interaction paradigms:
1. **Desktop Workstation Mode:** Aligned with general industrial PACS conventions, enabling both rapid one-handed mouse operation (crucial when using dictation microphones) and standard keyboard modifier shortcuts.
2. **Mobile & Tablet Touch Mode:** Built to strictly follow **Apple iOS / iPadOS Human Interface Guidelines (HIG)**, preventing collisions with operating system-level multi-touch gestures (e.g., 3-finger copy/paste/undo on iOS).

```
 ┌─────────────────────────────────────────────────────────────────────────┐
 │                      Viewport Interaction Modes                         │
 │                                                                         │
 │   Desktop (Mouse & Modifiers)            Mobile & Tablet (Touch)        │
 │   ───────────────────────────            ───────────────────────        │
 │   • Left Drag: Window/Level              • 1-Finger Drag: Win/Level     │
 │   • Right Drag / Shift+Left: Zoom        • 2-Finger Pinch: Smooth Zoom  │
 │   • Middle Drag / Ctrl+Left: Pan         • 2-Finger Drag: Canvas Pan    │
 │   • Wheel: Slice Stack Scroll            • Double Tap: Reset View       │
 │   • Double Click: Reset View                                            │
 └─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Desktop Mouse & Keyboard Controls

### Quick Reference Matrix

| Function | Primary (One-Handed Mouse) | Secondary (Keyboard Modifiers) | Action / Direction |
| :--- | :--- | :--- | :--- |
| **Window / Level (W/L)** | **Left Click + Drag** | — | • **Horizontal ($\Delta x$):** Drag **Right** widens window (lower contrast); drag **Left** narrows window (higher contrast).<br>• **Vertical ($\Delta y$):** Drag **Up** increases brightness (decreases Window Center); drag **Down** decreases brightness (increases Window Center). |
| **Zoom** | **Right Click + Drag** | **Shift + Left Click Drag** | • Drag **Up** $\rightarrow$ Zoom In (enlarge image).<br>• Drag **Down** $\rightarrow$ Zoom Out (shrink image).<br>• Smooth continuous scaling clamped between $0.1\times$ and $20.0\times$. |
| **Pan** | **Middle Click (Wheel) Drag** | **Ctrl + Left Click Drag** *(Win/Linux)*<br>**Cmd (⌘) + Left Click Drag** *(macOS)* | Translates the canvas offset $(\Delta x, \Delta y)$ following cursor movement. |
| **Stack Scroll** | **Mouse Wheel / Trackpad Scroll** | — | • Scroll **Up** $\rightarrow$ Next slice / frame in series.<br>• Scroll **Down** $\rightarrow$ Previous slice / frame in series. |
| **Reset View** | **Double Click Left Mouse** | — | Resets Zoom to $1.0\times$, Pan to $(0,0)$, and restores default/active Window Preset. |

### Design Notes & Clinical PACS Alignment
- **One-Handed Workflow:** In clinical practice, radiologists often hold a dictation microphone in their non-dominant hand. The ability to perform Window/Level (Left button), Zoom (Right button), and Pan (Middle button) entirely with the mouse eliminates constant keyboard reaching.
- **Cross-Platform macOS Compatibility:** On macOS, `Ctrl + Left Click` is reserved by the OS as a secondary click (right-click / context menu). On Mac desktops and web browsers, the Pan shortcut automatically recognizes the **Command (`⌘` / Meta)** key in addition to `Ctrl`.

---

## 3. Mobile & Tablet Touch Gestures

### Touch Interaction Matrix

| Gesture | Action | Description |
| :--- | :--- | :--- |
| **1-Finger Drag** | **Window / Level** | Adjusts brightness and contrast.<br>• Drag **Left / Right**: Modifies Window Width (contrast).<br>• Drag **Up / Down**: Modifies Window Center (brightness). |
| **2-Finger Pinch / Spread** | **Continuous Zoom** | Dynamic zoom centered at the touch centroid.<br>• Spread fingers apart to zoom in.<br>• Pinch fingers together to zoom out. |
| **2-Finger Drag** | **Canvas Pan** | Dragging two fingers in parallel moves the viewport canvas across the screen. |
| **Combined 2-Finger Pan & Zoom** | **Pan + Zoom** | Allows simultaneous focal zooming and canvas panning with smooth native physics. |
| **Double Tap (1 Finger)** | **Reset View** | Instantly resets zoom, canvas pan offset, and windowing presets to default. |
| **Slice Scrubber / Edge Slider** | **Stack Scroll** | Drag the dedicated vertical scrubber on the right edge or series slider to traverse frames. |

### Apple Human Interface Guidelines (HIG) Safety Note
> [!IMPORTANT]
> **Why 2-finger touch is used instead of 3-finger gestures on iOS / iPadOS:**  
> In iPadOS and iOS, three-finger gestures are hardwired system-level commands:
> - **3-Finger Pinch:** System "Copy"
> - **3-Finger Spread:** System "Paste"
> - **3-Finger Swipe Left/Right:** System "Undo / Redo"
> - **4-Finger Swipe:** System App Switcher
>
> Using 3-finger gestures in a web or mobile medical viewer triggers system banners and gesture cancellations. Standardizing on **1-finger W/L** and **2-finger Pan/Zoom** aligns with general industrial mobile radiology conventions and ensures 100% gesture reliability on touch-screen devices.

---

## 4. Window & Level (VOI LUT) Behavior

Window/Level adjustments dynamically modify the scalar-to-display transfer function:
- **Window Width ($W$):** Controls image contrast. Narrowing $W$ increases contrast between similar tissue densities; widening $W$ displays a broader range of Hounsfield Units (HU).
- **Window Center / Level ($C$):** Controls image brightness. Dragging upwards lowers $C$, shifting the window to lower HU values (making the image brighter). Dragging downwards raises $C$, making the image darker.

Presets (Soft Tissue, Bone, Lung, Brain, Abdomen, Angio) can be applied from the clinical toolbar to instantly calibrate $C$ and $W$ for specific anatomical review protocols.


---

## 5. Multi-Viewport Layouts & Image Number Overlays

### Grid Formats ([1, 2, 4, 9] on 1)
Clinical reading workflows frequently require viewing adjacent slices simultaneously to track anatomical lesions or vascular structures across continuous axial planes.

The viewer supports 4 standard layout arrangements accessible directly from the top toolbar grid button (`Icons.grid_view_rounded`):
- **1 on 1 (1×1):** Standard single viewport focusing on frame $i$.
- **2 on 1 (1×2):** Dual side-by-side viewport displaying frames $[i, i+1]$.
- **4 on 1 (2×2):** Quad layout displaying frames $[i, i+1, i+2, i+3]$.
- **9 on 1 (3×3):** $3 \times 3$ matrix displaying frames $[i, i+1, \dots, i+8]$.

### Synchronized Slice Stepping
When scrolling through the stack via mouse wheel, trackpad, or gesture in **any** grid cell:
- The base series index advances by **1 slice at a time**.
- For example, in **4 on 1** format: `[1, 2, 3, 4]` $\rightarrow$ scroll down $\rightarrow$ `[2, 3, 4, 5]`.
- This ensures radiologists do not miss subtle focal nodules between adjacent slices.

### Image Index HUD Overlay
Each active cell displays its exact clinical frame position in the bottom-right corner:
- `Img: 2 / 128` (Current frame 2 of 128 total frames in the series).

### Per-Frame Presentation State Persistence
Adjustments to Window/Level ($C/W$), Zoom, or Pan made on an individual frame are cached per-frame. Navigating forward and back preserves each frame's tailored presentation settings. The architecture exposes `onPresentationChanged` event hooks to broadcast updates directly to downstream servers (e.g. FirePACS) for real-time multi-reader collaboration and session persistence.
