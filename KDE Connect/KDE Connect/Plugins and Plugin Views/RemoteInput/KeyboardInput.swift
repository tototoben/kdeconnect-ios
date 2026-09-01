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

    private let charRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    private let numpadRows: [[String]] = [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
    ]

    @State private var ctrlActive: Bool = false
    @State private var shiftActive: Bool = false
    @State private var altActive: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Left: modifier numpad
            VStack(spacing: 6) {
                ModifierKeyButton(title: "Ctrl", isActive: ctrlActive) {
                    ctrlActive.toggle()
                    onModifierToggle(.control, ctrlActive)
                }
                ModifierKeyButton(title: "Shift", isActive: shiftActive) {
                    shiftActive.toggle()
                    onModifierToggle(.shift, shiftActive)
                }
                ModifierKeyButton(title: "Alt", isActive: altActive) {
                    altActive.toggle()
                    onModifierToggle(.alt, altActive)
                }
                ModifierKeyButton(title: "Tab") {
                    onTab()
                }
            }
            .frame(width: 70)

            // Center: character keys
            VStack(spacing: 8) {
                ForEach(charRows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 6) {
                        ForEach(charRows[rowIndex], id: \.self) { key in
                            KeyButton(title: key) {
                                onKey(key)
                            }
                            .frame(minWidth: 44)
                        }
                    }
                }
                HStack(spacing: 6) {
                    KeyButton(title: "space", isWide: true) {
                        onSpace()
                    }

                    SpecialKeyButton(systemImage: "return") {
                        onReturn()
                    }
                    .frame(width: 64)
                }
            }

            // Right: number numpad (3x3 grid + 0 + backspace)
            VStack(spacing: 6) {
                ForEach(numpadRows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 6) {
                        ForEach(numpadRows[rowIndex], id: \.self) { num in
                            KeyButton(title: num) {
                                onKey(num)
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    KeyButton(title: "0") {
                        onKey("0")
                    }
                    .frame(width: 64)

                    SpecialKeyButton(systemImage: "delete.left") {
                        onDelete()
                    }
                }
            }
            .frame(width: 160)
        }
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color(white: 0.04))
    }
}

private struct KeyButton: View {
    let title: String
    var isWide: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.18))
                )
        }
        .buttonStyle(KeyPressStyle())
    }
}

private struct SpecialKeyButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color(red: 0.6, green: 0.7, blue: 0.9))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.10))
                )
        }
        .buttonStyle(KeyPressStyle())
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color(white: 0.32) : Color.clear)
            )
            .animation(.spring(response: 0.15, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ModifierKeyButton: View {
    let title: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? .white : Color(red: 0.6, green: 0.7, blue: 0.9))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color(red: 0.2, green: 0.5, blue: 0.9, opacity: 0.8) : Color(white: 0.10))
                )
        }
        .buttonStyle(KeyPressStyle())
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
    onTab: @escaping () -> Void = {}
) -> some View {
    return _KeyboardListenerPlaceholderView(onInsertText: onInsertText,
                                            onDeleteBackward: onDeleteBackward,
                                            onReturn: onReturn,
                                            onTab: onTab)
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
            }
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
