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

    private let keyRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(keyRows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(keyRows[rowIndex], id: \.self) { key in
                        KeyButton(title: key) {
                            onKey(key)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                SpecialKeyButton(systemImage: "delete.left") {
                    onDelete()
                }
                .frame(width: 64)

                KeyButton(title: "space", isWide: true) {
                    onSpace()
                }

                SpecialKeyButton(systemImage: "return") {
                    onReturn()
                }
                .frame(width: 64)
            }
        }
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

        static let modifierBarColor = UIColor(white: 0.08, alpha: 1.0)
        static let modifierSelectedColor = UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.8)
        static let modifierTextColor = UIColor(red: 0.6, green: 0.7, blue: 0.9, alpha: 1.0)
        static let modifierSelectedTextColor = UIColor.white
        static let panelBgColor = UIColor(white: 0.04, alpha: 1.0)

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

        private func modifierPressed(_ button: UIButton, type: RemoteInput.KeyModifier) {
            button.isSelected.toggle()
            if button.isSelected {
                button.backgroundColor = Self.modifierSelectedColor
                currentModifiers.append(type)
            } else {
                button.backgroundColor = Self.modifierBarColor
                currentModifiers.removeAll { $0 == type }
            }
        }

        @objc func ctrlPressed(_ button: UIButton) {
            modifierPressed(button, type: .control)
        }
        @objc func shiftPressed(_ button: UIButton) {
            modifierPressed(button, type: .shift)
        }
        @objc func altPressed(_ button: UIButton) {
            modifierPressed(button, type: .alt)
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
            }
        )
        let hostingController = UIHostingController(rootView: keyboardRootView)
        hostingController.view.backgroundColor = UIColor(white: 0.04, alpha: 1.0)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.hostingController = hostingController
        view.inputView = hostingController.view

        // Modifier bar as input accessory (sits above the keyboard)
        let createButton: (String, @escaping (UIButton) -> Void) -> UIButton = { name, actionHandler in
            let button = UIButton()
            button.setTitle(name, for: .normal)
            button.setTitleColor(Coordinator.modifierTextColor, for: .normal)
            button.setTitleColor(UIColor(white: 0.3, alpha: 1.0), for: .highlighted)
            button.setTitleColor(Coordinator.modifierSelectedTextColor, for: .selected)
            button.backgroundColor = Coordinator.modifierBarColor
            button.layer.cornerRadius = 8
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = 0
            let action = UIAction { _ in actionHandler(button) }
            button.addAction(action, for: .touchUpInside)
            return button
        }

        let tab = createButton("Tab") { sender in context.coordinator.tabPressed(sender) }
        let ctrl = createButton("Ctrl") { sender in context.coordinator.ctrlPressed(sender) }
        let shift = createButton("Shift") { sender in context.coordinator.shiftPressed(sender) }
        let alt = createButton("Alt") { sender in context.coordinator.altPressed(sender) }

        let panel = UIStackView()
        panel.backgroundColor = Coordinator.panelBgColor
        panel.distribution = .fillEqually
        panel.spacing = 8
        panel.frame = CGRect(x: 0, y: 0, width: 0, height: 30)
        panel.addArrangedSubview(tab)
        panel.addArrangedSubview(ctrl)
        panel.addArrangedSubview(shift)
        panel.addArrangedSubview(alt)

        view.inputAccessoryView = panel

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
