/*
 * SPDX-FileCopyrightText: 2022 Han Young <hanyoung@protonmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#if !os(macOS)

import UIKit
import SwiftUI
import Introspect

extension View {
    public func introspectKeyboardListener(customize: @escaping (KeyboardListener) -> Void) -> some View {
        introspect(selector: TargetViewSelector.siblingContainingOrAncestorOrAncestorChild, customize: customize)
    }
}

public protocol KeyboardListenerDelegate: AnyObject {
    func onInsertText(_ text: String)
    func onDeleteBackward()
    func onReturn()
}

// MARK: - Custom dark keyboard (SwiftUI)

struct StationKeyboardRootView: View {
    let onKey: (String) -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void
    let onSpace: () -> Void
    let onTab: () -> Void
    let onModifierToggle: (RemoteInput.KeyModifier, Bool) -> Void
    var scale: CGFloat = 1.0

    @ObservedObject private var settings = KdeConnectSettings.shared

    private var charRows: [[String]] { settings.keyboardLayout.charRows }
    private var shiftRows: [[String]] { settings.keyboardLayout.shiftRows }

    private let numpadRows: [[String]] = [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
    ]

    @State private var shiftActive: Bool = false
    @State private var altActive: Bool = false

    // In-progress gesture state (resets to zero when gesture ends)
    @GestureState private var modifiersDrag: CGSize = .zero
    @GestureState private var charactersDrag: CGSize = .zero
    @GestureState private var numpadDrag: CGSize = .zero
    @GestureState private var actionsDrag: CGSize = .zero

    // Scaling mode: double-tap to enter, drag up/down to scale, release to exit
    @State private var scalingPanel: ScalingPanel = .none

    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 3.0

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let spacing = 12 * scale
            let modW = 70 * scale * settings.keyboardModifiersScale
            let charW = 560 * scale * settings.keyboardCharactersScale
            let numW = 160 * scale * settings.keyboardNumpadScale
            let actW = 70 * scale * settings.keyboardActionsScale
            let totalW = modW + spacing + charW + spacing + numW + spacing + actW
            let modX = -totalW / 2 + modW / 2
            let charX: CGFloat = 0
            let numX = totalW / 2 - numW / 2 - actW - spacing
            let actX = totalW / 2 - actW / 2

            ZStack {
                // Modifiers panel
                panelContainer(
                    content: modifiersPanelContent,
                    dragHandle: AnyView(DragHandle(scale: scale * settings.keyboardModifiersScale)),
                    defaultX: modX,
                    committedOffset: $settings.keyboardModifiersOffset,
                    dragState: $modifiersDrag,
                    committedScale: $settings.keyboardModifiersScale,
                    scalingPanel: .modifiers,
                    activeScalingPanel: $scalingPanel,
                    panelWidth: 70,
                    panelHeight: 200,
                    viewSize: viewSize
                )

                // Characters panel
                panelContainer(
                    content: charactersPanelContent,
                    dragHandle: AnyView(DragHandle(scale: scale * settings.keyboardCharactersScale)),
                    defaultX: charX,
                    committedOffset: $settings.keyboardCharactersOffset,
                    dragState: $charactersDrag,
                    committedScale: $settings.keyboardCharactersScale,
                    scalingPanel: .characters,
                    activeScalingPanel: $scalingPanel,
                    panelWidth: 560,
                    panelHeight: 240,
                    viewSize: viewSize
                )

                // Numpad panel
                panelContainer(
                    content: numpadPanelContent,
                    dragHandle: AnyView(DragHandle(scale: scale * settings.keyboardNumpadScale)),
                    defaultX: numX,
                    committedOffset: $settings.keyboardNumpadOffset,
                    dragState: $numpadDrag,
                    committedScale: $settings.keyboardNumpadScale,
                    scalingPanel: .numpad,
                    activeScalingPanel: $scalingPanel,
                    panelWidth: 160,
                    panelHeight: 200,
                    viewSize: viewSize
                )

                // Actions panel (enter + delete)
                panelContainer(
                    content: actionsPanelContent,
                    dragHandle: AnyView(DragHandle(scale: scale * settings.keyboardActionsScale)),
                    defaultX: actX,
                    committedOffset: $settings.keyboardActionsOffset,
                    dragState: $actionsDrag,
                    committedScale: $settings.keyboardActionsScale,
                    scalingPanel: .actions,
                    activeScalingPanel: $scalingPanel,
                    panelWidth: 70,
                    panelHeight: 200,
                    viewSize: viewSize
                )
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Panel container with handle-only drag

    private func panelContainer(
        content: AnyView,
        dragHandle: AnyView,
        defaultX: CGFloat,
        committedOffset: Binding<CGSize>,
        dragState: GestureState<CGSize>,
        committedScale: Binding<CGFloat>,
        scalingPanel: ScalingPanel,
        activeScalingPanel: Binding<ScalingPanel>,
        panelWidth: CGFloat,
        panelHeight: CGFloat,
        viewSize: CGSize
    ) -> some View {
        let controlsVisible = settings.showKeyboardControls
        let isScaling = activeScalingPanel.wrappedValue == scalingPanel
        let scaleAdjust = isScaling ? dragState.wrappedValue.height * 0.005 : 0
        let liveScale = min(max(committedScale.wrappedValue + scaleAdjust, minScale), maxScale)
        let effectiveScale = scale * liveScale
        let panelSize = CGSize(width: panelWidth * effectiveScale, height: panelHeight * effectiveScale)
        let dragOffset = isScaling ? CGSize.zero : dragState.wrappedValue
        let contentOffset = CGSize(
            width: defaultX + committedOffset.wrappedValue.width + dragOffset.width,
            height: committedOffset.wrappedValue.height + dragOffset.height
        )
        let clampedContent = clampOffset(contentOffset, panelSize: panelSize, viewSize: viewSize)
        let committedOnly = CGSize(
            width: defaultX + committedOffset.wrappedValue.width,
            height: committedOffset.wrappedValue.height
        )
        let isDragging = !isScaling && (abs(dragState.wrappedValue.width) > 1 || abs(dragState.wrappedValue.height) > 1)
        let handleHeight = 24 * effectiveScale
        let s = scale * committedScale.wrappedValue
        let clampedHandle = clampOffset(committedOnly,
            panelSize: CGSize(width: panelWidth * s, height: panelHeight * s),
            viewSize: viewSize)

        let handleWidth = panelWidth * effectiveScale
        let handleView = dragHandle
            .frame(width: handleWidth, height: handleHeight)
            .contentShape(Rectangle())

        let visualHandle = dragHandle
            .frame(width: handleWidth, height: handleHeight)

        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Color.clear.frame(height: controlsVisible ? handleHeight : 0)
                content
            }
            .scaleEffect(isScaling ? liveScale / committedScale.wrappedValue : 1.0, anchor: .top)
            .offset(clampedContent)

            if controlsVisible {
                // Visual handle rides along with the content during drag
                visualHandle
                    .opacity(isDragging ? 1 : 0)
                    .offset(clampedContent)
                    .allowsHitTesting(false)

                // Gesture handle stays at committed position (no feedback loop)
                handleView
                    .opacity(isDragging ? 0 : 1)
                    .offset(clampedHandle)
                    .gesture(
                        DragGesture()
                            .updating(dragState) { gesture, state, _ in
                                state = gesture.translation
                            }
                            .onEnded { gesture in
                                if activeScalingPanel.wrappedValue == scalingPanel {
                                    let newScale = committedScale.wrappedValue + gesture.translation.height * 0.005
                                    committedScale.wrappedValue = min(max(newScale, minScale), maxScale)
                                    activeScalingPanel.wrappedValue = .none
                                } else {
                                    let raw = CGSize(
                                        width: committedOffset.wrappedValue.width + gesture.translation.width,
                                        height: committedOffset.wrappedValue.height + gesture.translation.height
                                    )
                                    let s = scale * committedScale.wrappedValue
                                    committedOffset.wrappedValue = clampOffset(raw,
                                        panelSize: CGSize(width: panelWidth * s, height: panelHeight * s),
                                        viewSize: viewSize)
                                }
                            }
                    )
            }
        }
        .onTapGesture(count: 2) {
            if controlsVisible {
                if activeScalingPanel.wrappedValue == scalingPanel {
                    activeScalingPanel.wrappedValue = .none
                } else {
                    activeScalingPanel.wrappedValue = scalingPanel
                }
            }
        }
        .overlay(
            Group {
                if isScaling {
                    RoundedRectangle(cornerRadius: 10 * effectiveScale)
                        .stroke(Color(red: 0.3, green: 0.6, blue: 1.0, opacity: 0.6), lineWidth: 2)
                        .allowsHitTesting(false)
                        .offset(clampedContent)
                        .frame(width: panelWidth * effectiveScale, height: panelHeight * effectiveScale)
                }
            }
        )
    }

    // MARK: - Viewport clamping

    private func clampOffset(_ offset: CGSize, panelSize: CGSize, viewSize: CGSize) -> CGSize {
        let xRange = viewSize.width - panelSize.width
        let yRange = viewSize.height - panelSize.height
        let clampedX: CGFloat = xRange <= 0 ? 0 : min(max(offset.width, -xRange / 2), xRange / 2)
        let clampedY: CGFloat = yRange <= 0 ? 0 : min(max(offset.height, -yRange / 2), yRange / 2)
        return CGSize(width: clampedX, height: clampedY)
    }

    // MARK: - Panels

    private var modifiersPanelContent: AnyView {
        let s = scale * settings.keyboardModifiersScale
        return AnyView(VStack(spacing: 6 * s) {
            ModifierKeyButton(title: settings.keyboardLayout.shortLabel, scale: s) {
                settings.keyboardLayout = settings.keyboardLayout.next
            }
            ModifierKeyButton(title: "Shift", isActive: shiftActive, scale: s) {
                shiftActive.toggle()
                onModifierToggle(.shift, shiftActive)
            }
            ModifierKeyButton(title: "Alt", isActive: altActive, scale: s) {
                altActive.toggle()
                onModifierToggle(.alt, altActive)
            }
            ModifierKeyButton(title: "Tab", scale: s) {
                onTab()
            }
        }
        .frame(width: 70 * s)
        .padding(.all, 6 * s)
        .background(Color(white: 0.04))
        .cornerRadius(10 * s))
    }

    private var charactersPanelContent: AnyView {
        let s = scale * settings.keyboardCharactersScale
        let ks: CGFloat = 1.5
        return AnyView(VStack(spacing: 8 * s) {
            ForEach(charRows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6 * s) {
                    ForEach(charRows[rowIndex].indices, id: \.self) { colIndex in
                        let key = charRows[rowIndex][colIndex]
                        let shifted = (shiftActive && colIndex < shiftRows[rowIndex].count)
                            ? shiftRows[rowIndex][colIndex] : key
                        KeyButton(title: shifted, scale: s, keyScale: ks) {
                            onKey(shifted)
                            if shiftActive {
                                shiftActive = false
                                onModifierToggle(.shift, false)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6 * s) {
                KeyButton(title: "space", isWide: true, scale: s, keyScale: ks, sound: .keySpace) {
                    onSpace()
                }
            }
        }
        .frame(width: 560 * s)
        .padding(.all, 6 * s)
        .background(Color(white: 0.04))
        .cornerRadius(10 * s))
    }

    private var numpadPanelContent: AnyView {
        let s = scale * settings.keyboardNumpadScale
        let keyWidth: CGFloat = 46
        return AnyView(VStack(spacing: 6 * s) {
            ForEach(numpadRows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6 * s) {
                    ForEach(numpadRows[rowIndex], id: \.self) { num in
                        KeyButton(title: num, scale: s) {
                            onKey(num)
                        }
                    }
                }
            }
            HStack(spacing: 6 * s) {
                KeyButton(title: "0", scale: s) {
                    onKey("0")
                }
                .frame(width: keyWidth * s)
            }
        }
        .frame(width: 160 * s)
        .padding(.all, 6 * s)
        .background(Color(white: 0.04))
        .cornerRadius(10 * s))
    }

    private var actionsPanelContent: AnyView {
        let s = scale * settings.keyboardActionsScale
        return AnyView(VStack(spacing: 6 * s) {
            SpecialKeyButton(systemImage: "delete.left", scale: s, sound: .keyDelete) {
                onDelete()
            }
            SpecialKeyButton(systemImage: "return", scale: s, sound: .keyReturn) {
                onReturn()
            }
        }
        .frame(width: 70 * s)
        .padding(.all, 6 * s)
        .background(Color(white: 0.04))
        .cornerRadius(10 * s))
    }
}

private enum ScalingPanel {
    case none, modifiers, characters, numpad, actions
}

private struct DragHandle: View {
    var scale: CGFloat = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 2 * scale)
            .fill(Color.white.opacity(0.2))
            .frame(width: 30 * scale, height: 4 * scale)
    }
}

private struct KeyButton: View {
    let title: String
    var isWide: Bool = false
    var scale: CGFloat = 1.0
    var keyScale: CGFloat = 1.0
    var sound: SoundEffect? = .keyPress
    let action: () -> Void

    @GestureState private var isPressed: Bool = false

    var body: some View {
        keyLabel
            .background(keyBackground)
            .overlay(keyBorder)
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.1, dampingFraction: 0.8), value: isPressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if let sound = sound { SoundManager.shared.play(sound) }
                        action()
                    }
            )
    }

    private var keyLabel: some View {
        Text(title)
            .font(.system(size: 18 * scale * keyScale, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 42 * scale * keyScale)
    }

    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: 6 * scale)
            .fill(isPressed ? Color(red: 0.3, green: 0.6, blue: 1.0, opacity: 0.5) : Color(white: 0.18))
    }

    private var keyBorder: some View {
        RoundedRectangle(cornerRadius: 6 * scale)
            .stroke(isPressed ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1.5 * scale)
    }
}

private struct SpecialKeyButton: View {
    let systemImage: String
    var scale: CGFloat = 1.0
    var keyScale: CGFloat = 1.0
    var sound: SoundEffect? = nil
    let action: () -> Void

    @GestureState private var isPressed: Bool = false

    var body: some View {
        keyLabel
            .background(keyBackground)
            .overlay(keyBorder)
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.1, dampingFraction: 0.8), value: isPressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if let sound = sound { SoundManager.shared.play(sound) }
                        action()
                    }
            )
    }

    private var keyLabel: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18 * scale * keyScale, weight: .medium))
            .foregroundColor(Color(red: 0.6, green: 0.7, blue: 0.9))
            .frame(maxWidth: .infinity, minHeight: 42 * scale * keyScale)
    }

    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: 6 * scale)
            .fill(isPressed ? Color(red: 0.4, green: 0.5, blue: 0.9, opacity: 0.6) : Color(white: 0.10))
    }

    private var keyBorder: some View {
        RoundedRectangle(cornerRadius: 6 * scale)
            .stroke(isPressed ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1.5 * scale)
    }
}

private struct ModifierKeyButton: View {
    let title: String
    var isActive: Bool = false
    var scale: CGFloat = 1.0
    var sound: SoundEffect? = .modifierToggle
    let action: () -> Void

    @GestureState private var isPressed: Bool = false

    var body: some View {
        keyLabel
            .background(keyBackground)
            .overlay(keyBorder)
            .scaleEffect(isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.1, dampingFraction: 0.8), value: isPressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if let sound = sound { SoundManager.shared.play(sound) }
                        action()
                    }
            )
    }

    private var keyLabel: some View {
        Text(title)
            .font(.system(size: 14 * scale, weight: .medium))
            .foregroundColor(isActive ? .white : Color(red: 0.6, green: 0.7, blue: 0.9))
            .frame(maxWidth: .infinity, minHeight: 42 * scale)
    }

    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: 6 * scale)
            .fill(isPressed ? Color(red: 0.3, green: 0.6, blue: 1.0, opacity: 0.4)
                           : (isActive ? Color(red: 0.2, green: 0.5, blue: 0.9, opacity: 0.8) : Color(white: 0.10)))
    }

    private var keyBorder: some View {
        RoundedRectangle(cornerRadius: 6 * scale)
            .stroke(isPressed ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1.5 * scale)
    }
}

// MARK: - KeyboardListener (hosts custom keyboard via inputView)

public class KeyboardListener: UIView, UIKeyInput {
    public var hasText: Bool { false }
    public override var canBecomeFirstResponder: Bool { true }
    public weak var delegate: KeyboardListenerDelegate?
    public var keyboardAppearance: UIKeyboardAppearance = .dark

    private var _inputAccessoryView: UIView?
    public override var inputAccessoryView: UIView? {
        get { _inputAccessoryView }
        set { _inputAccessoryView = newValue }
    }

    private var _inputView: UIView?
    public override var inputView: UIView? {
        get { _inputView }
        set { _inputView = newValue }
    }

    public func insertText(_ text: String) {
        if let delegate = delegate {
            if text == "\n" {
                delegate.onReturn()
            } else {
                delegate.onInsertText(text)
            }
        }
    }

    public func deleteBackward() {
        delegate?.onDeleteBackward()
    }
}

// This naming is intentional to mimic a SwiftUI View
// swiftlint:disable:next identifier_name
func KeyboardListenerPlaceholderView(
    onInsertText: @escaping (String, [RemoteInput.KeyModifier]) -> Void = { _, _ in },
    onDeleteBackward: @escaping () -> Void = {},
    onReturn: @escaping () -> Void = {},
    onTab: @escaping () -> Void = {},
    keyboardScale: CGFloat = 1.0
) -> some View {
    return _KeyboardListenerPlaceholderView(onInsertText: onInsertText,
                                            onDeleteBackward: onDeleteBackward,
                                            onReturn: onReturn,
                                            onTab: onTab,
                                            keyboardScale: keyboardScale)
    .frame(width: 0, height: 0)
}

fileprivate struct _KeyboardListenerPlaceholderView: UIViewRepresentable {
    class Coordinator: NSObject, KeyboardListenerDelegate {
        private var parent: _KeyboardListenerPlaceholderView
        private var currentModifiers: [RemoteInput.KeyModifier] = []
        fileprivate var hostingController: UIHostingController<StationKeyboardRootView>?

        init(_ parent: _KeyboardListenerPlaceholderView) {
            self.parent = parent
        }

        func onInsertText(_ text: String) {
            parent.onInsertText(text, currentModifiers)
            resetModifiers()
        }

        func onDeleteBackward() {
            parent.onDeleteBackward()
            resetModifiers()
        }

        func onReturn() {
            parent.onReturn()
            resetModifiers()
        }

        private func resetModifiers() {
            currentModifiers.removeAll()
        }

        func setModifier(_ type: RemoteInput.KeyModifier, isOn: Bool) {
            if isOn {
                currentModifiers.append(type)
            } else {
                currentModifiers.removeAll { $0 == type }
            }
        }

        @objc func tabPressed(_ button: UIButton) {
            parent.onTab()
        }
    }

    typealias UIViewType = KeyboardListener
    let onInsertText: (String, [RemoteInput.KeyModifier]) -> Void
    let onDeleteBackward: () -> Void
    let onReturn: () -> Void
    let onTab: () -> Void
    let keyboardScale: CGFloat

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeUIView(context: Context) -> KeyboardListener {
        let view = KeyboardListener()
        view.delegate = context.coordinator

        // Custom dark keyboard (SwiftUI) replacing the system keyboard
        let keyboardRootView = StationKeyboardRootView(
            onKey: { key in
                context.coordinator.onInsertText(key)
            },
            onDelete: {
                context.coordinator.onDeleteBackward()
            },
            onReturn: {
                context.coordinator.onReturn()
            },
            onSpace: {
                context.coordinator.onInsertText(" ")
            },
            onTab: {
                context.coordinator.tabPressed(UIButton())
            },
            onModifierToggle: { modifier, isOn in
                context.coordinator.setModifier(modifier, isOn: isOn)
            },
            scale: keyboardScale
        )
        let hostingController = UIHostingController(rootView: keyboardRootView)
        hostingController.view.backgroundColor = UIColor(white: 0.04, alpha: 1.0)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.hostingController = hostingController
        view.inputView = hostingController.view

        // Auto-focus: become first responder on next run loop
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }

        return view
    }

    func updateUIView(_ uiView: KeyboardListener, context: Context) {
        // do nothing
    }
}

#endif
