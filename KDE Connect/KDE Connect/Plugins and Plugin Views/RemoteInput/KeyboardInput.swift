/*
 * SPDX-FileCopyrightText: 2022 Han Young <hanyoung@protonmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

#if !os(macOS)

import UIKit
import SwiftUI
import CoreImage
import Introspect

/// Matches orb-platform `original` station vibe (`MirrorJourney.css`).
enum StationChrome {
    static let frost = Color.black
    static let ice = Color(red: 185 / 255, green: 220 / 255, blue: 235 / 255)
    static let ink = Color.white
    static let quiet = Color(red: 198 / 255, green: 214 / 255, blue: 220 / 255)
    static let keyFill = Color(white: 0.06)
    static let line = Color(red: 185 / 255, green: 220 / 255, blue: 235 / 255).opacity(0.55)
    static let radius: CGFloat = 0

    static func labelFont(size: CGFloat) -> Font {
        Font.custom("HelveticaNeue-Medium", size: size)
    }

    static func displayFont(size: CGFloat) -> Font {
        Font.custom("HelveticaNeue-Light", size: size)
    }
}

/// Crisp Helvetica plus an ice smudge — the same two-layer haze as
/// orb-platform `drawGrainyText` / JourneyButton, pre-rendered so the
/// iPad 6th gen is not blurring thirty live SwiftUI labels.
enum StationHazeGlyph {
    private static let cache = NSCache<NSString, UIImage>()
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private static let ice = UIColor(red: 185 / 255, green: 220 / 255, blue: 235 / 255, alpha: 1)

    static func image(
        text: String,
        fontSize: CGFloat,
        light: Bool,
        kerning: CGFloat,
        pressed: Bool
    ) -> UIImage {
        let size = max(8, (fontSize * 2).rounded() / 2)
        let key = "\(text)|\(size)|\(light)|\(kerning)|\(pressed)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let rendered = render(
            text: text,
            fontSize: size,
            light: light,
            kerning: kerning,
            pressed: pressed
        )
        cache.setObject(rendered, forKey: key)
        return rendered
    }

    private static func render(
        text: String,
        fontSize: CGFloat,
        light: Bool,
        kerning: CGFloat,
        pressed: Bool
    ) -> UIImage {
        let crispName = light ? "HelveticaNeue-Light" : "HelveticaNeue-Medium"
        let crispFont = UIFont(name: crispName, size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: light ? .light : .medium)
        let smudgeFont = UIFont(name: "HelveticaNeue-Bold", size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .bold)
        let crispColor = pressed ? UIColor.black : UIColor.white.withAlphaComponent(0.88)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: crispFont,
            .kern: kerning,
            .foregroundColor: crispColor,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let blurRadius = max(3.5, fontSize * 0.26)
        let pad = ceil(blurRadius * 2.6)
        let canvas = CGSize(
            width: max(2, ceil(textSize.width + pad * 2)),
            height: max(2, ceil(textSize.height + pad * 2))
        )
        let origin = CGPoint(x: pad, y: pad)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)

        guard !pressed else {
            return renderer.image { _ in
                (text as NSString).draw(at: origin, withAttributes: attrs)
            }
        }

        let smudgeSource = renderer.image { _ in
            (text as NSString).draw(at: origin, withAttributes: [
                .font: smudgeFont,
                .kern: kerning,
                .foregroundColor: ice,
            ])
        }
        let halo = blurred(smudgeSource, radius: blurRadius * 1.55) ?? smudgeSource
        let wet = blurred(smudgeSource, radius: blurRadius) ?? smudgeSource

        return renderer.image { _ in
            halo.draw(in: CGRect(origin: .zero, size: canvas), blendMode: .normal, alpha: 0.55)
            wet.draw(in: CGRect(origin: .zero, size: canvas), blendMode: .plusLighter, alpha: 0.82)
            wet.draw(in: CGRect(origin: .zero, size: canvas), blendMode: .plusLighter, alpha: 0.4)
            (text as NSString).draw(at: origin, withAttributes: attrs)
        }
    }

    private static func blurred(_ image: UIImage, radius: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius * image.scale, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage,
              let cgOut = ciContext.createCGImage(output, from: input.extent)
        else { return nil }
        return UIImage(cgImage: cgOut, scale: image.scale, orientation: .up)
    }
}

struct StationHazeLabel: View {
    let text: String
    var fontSize: CGFloat
    var light: Bool = false
    var kerning: CGFloat = 0
    var pressed: Bool = false

    var body: some View {
        Image(uiImage: rendered)
            .renderingMode(.original)
    }

    private var rendered: UIImage {
        StationHazeGlyph.image(
            text: text,
            fontSize: fontSize,
            light: light,
            kerning: kerning,
            pressed: pressed
        )
    }
}

enum StationIceGrain {
    static let image: UIImage = {
        let size = 96
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 1)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return UIImage() }
        for _ in 0..<1100 {
            let x = CGFloat.random(in: 0..<CGFloat(size))
            let y = CGFloat.random(in: 0..<CGFloat(size))
            ctx.setFillColor(UIColor.white.withAlphaComponent(CGFloat.random(in: 0.05...0.32)).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }()

    static func overlay(opacity: Double) -> some View {
        Image(uiImage: image)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }
}

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
    var submitArmed: Bool = false

    @ObservedObject private var settings = KdeConnectSettings.shared

    private var charRows: [[String]] { settings.keyboardLayout.charRows }
    private var shiftRows: [[String]] { settings.keyboardLayout.shiftRows }

    @State private var shiftActive: Bool = false
    @State private var altActive: Bool = false

    var body: some View {
        GeometryReader { geo in
            let pad: CGFloat = 16
            let gap: CGFloat = 8
            let innerW = max(geo.size.width - pad * 2, 1)
            let innerH = max(geo.size.height - pad * 2, 1)
            let actionW = min(max(innerW * 0.18, 96), 132)
            let leftW = max(innerW - gap - actionW, 1)
            let modifierH = min(max(innerH * 0.13, 52), 68)
            let keysH = max(innerH - modifierH - gap, 1)
            let letterFont = min(keysH * 0.09, 30)
            let modifierFont = min(modifierH * 0.28, 16)
            let actionIcon = min(actionW * 0.28, 28)

            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    HStack(spacing: gap) {
                        ModifierKeyButton(
                            title: settings.keyboardLayout.shortLabel,
                            fontSize: modifierFont
                        ) {
                            settings.keyboardLayout = settings.keyboardLayout.next
                        }
                        ModifierKeyButton(title: "Shift", isActive: shiftActive, fontSize: modifierFont) {
                            shiftActive.toggle()
                            onModifierToggle(.shift, shiftActive)
                        }
                        ModifierKeyButton(title: "Alt", isActive: altActive, fontSize: modifierFont) {
                            altActive.toggle()
                            onModifierToggle(.alt, altActive)
                        }
                        ModifierKeyButton(title: "Tab", fontSize: modifierFont) {
                            onTab()
                        }
                    }
                    .frame(width: leftW, height: modifierH)

                    VStack(spacing: gap) {
                        HStack(spacing: gap) {
                            ForEach(KeyboardLayout.numberRow, id: \.self) { digit in
                                KeyButton(title: digit, fontSize: letterFont) {
                                    onKey(digit)
                                    if shiftActive {
                                        shiftActive = false
                                        onModifierToggle(.shift, false)
                                    }
                                }
                            }
                        }
                        ForEach(charRows.indices, id: \.self) { rowIndex in
                            HStack(spacing: gap) {
                                ForEach(charRows[rowIndex].indices, id: \.self) { colIndex in
                                    let key = charRows[rowIndex][colIndex]
                                    let shifted = (shiftActive && colIndex < shiftRows[rowIndex].count)
                                        ? shiftRows[rowIndex][colIndex] : key
                                    KeyButton(title: shifted, fontSize: letterFont) {
                                        onKey(shifted)
                                        if shiftActive {
                                            shiftActive = false
                                            onModifierToggle(.shift, false)
                                        }
                                    }
                                }
                            }
                        }
                        KeyButton(title: "SPACE", isWide: true, fontSize: letterFont * 0.55, sound: .keySpace) {
                            onSpace()
                        }
                    }
                    .frame(width: leftW, height: keysH)
                }

                VStack(spacing: gap) {
                    SpecialKeyButton(systemImage: "delete.left", iconSize: actionIcon, sound: .keyDelete) {
                        onDelete()
                    }
                    SpecialKeyButton(
                        systemImage: "return",
                        iconSize: actionIcon,
                        sound: .keyReturn,
                        isAccent: true,
                        isArmed: submitArmed
                    ) {
                        onReturn()
                    }
                }
                .frame(width: actionW, height: innerH)
            }
            .padding(pad)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
    }
}

private struct KeyButton: View {
    let title: String
    var isWide: Bool = false
    var scale: CGFloat = 1.0
    var keyScale: CGFloat = 1.0
    var fontSize: CGFloat? = nil
    var sound: SoundEffect? = .keyPress
    let action: () -> Void

    @GestureState private var isPressed: Bool = false

    private var resolvedFont: CGFloat {
        fontSize ?? (title.count > 1 ? 12 : 18) * scale * keyScale
    }

    var body: some View {
        keyLabel
            .background(keyBackground)
            .overlay(StationIceGrain.overlay(opacity: isPressed ? 0.28 : 0.12))
            .overlay(keyBorder)
            .shadow(color: StationChrome.ice.opacity(isPressed ? 0.42 : 0), radius: isPressed ? 16 : 0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
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
        StationHazeLabel(
            text: title,
            fontSize: resolvedFont,
            kerning: title.count > 1 ? resolvedFont * 0.08 : 0,
            pressed: isPressed
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyBackground: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        isPressed ? StationChrome.ice : StationChrome.ice.opacity(0.10),
                        isPressed ? StationChrome.ice : StationChrome.keyFill,
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var keyBorder: some View {
        Rectangle()
            .stroke(isPressed ? StationChrome.ice : StationChrome.line, lineWidth: 1)
    }
}

private struct SpecialKeyButton: View {
    let systemImage: String
    var scale: CGFloat = 1.0
    var keyScale: CGFloat = 1.0
    var iconSize: CGFloat? = nil
    var sound: SoundEffect? = nil
    var isAccent: Bool = false
    var isArmed: Bool = false
    let action: () -> Void

    @GestureState private var isPressed: Bool = false

    var body: some View {
        keyLabel
            .background(keyBackground)
            .overlay(StationIceGrain.overlay(opacity: isPressed ? 0.28 : 0.14))
            .overlay(keyBorder)
            .shadow(
                color: StationChrome.ice.opacity(glowOpacity),
                radius: glowRadius
            )
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeInOut(duration: 0.45), value: isArmed)
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

    private var glowOpacity: Double {
        if isPressed { return 0.8 }
        if isArmed { return 0.55 }
        if isAccent { return 0.28 }
        return 0
    }

    private var glowRadius: CGFloat {
        if isPressed { return 18 }
        if isArmed { return 16 }
        if isAccent { return 8 }
        return 0
    }

    private var keyLabel: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize ?? (18 * scale * keyScale), weight: .medium))
            .foregroundColor(isPressed || isArmed ? StationChrome.frost : StationChrome.ice)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyBackground: some View {
        Rectangle()
            .fill(isPressed || isArmed ? StationChrome.ice : StationChrome.keyFill)
    }

    private var keyBorder: some View {
        Rectangle()
            .stroke((isPressed || isArmed || isAccent) ? StationChrome.ice : StationChrome.line, lineWidth: 1)
    }
}

private struct ModifierKeyButton: View {
    let title: String
    var isActive: Bool = false
    var scale: CGFloat = 1.0
    var fontSize: CGFloat? = nil
    var sound: SoundEffect? = .modifierToggle
    let action: () -> Void

    @GestureState private var isPressed: Bool = false

    var body: some View {
        keyLabel
            .background(keyBackground)
            .overlay(StationIceGrain.overlay(opacity: isPressed ? 0.28 : 0.12))
            .overlay(keyBorder)
            .shadow(color: StationChrome.ice.opacity(isPressed ? 0.42 : 0), radius: isPressed ? 16 : 0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
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
        StationHazeLabel(
            text: title.uppercased(),
            fontSize: fontSize ?? 12 * scale,
            kerning: (fontSize ?? 12 * scale) * 0.1,
            pressed: isActive || isPressed
        )
        .opacity(isActive || isPressed ? 1 : 0.82)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyBackground: some View {
        Rectangle()
            .fill(isPressed || isActive ? StationChrome.ice : StationChrome.keyFill)
    }

    private var keyBorder: some View {
        Rectangle()
            .stroke((isPressed || isActive) ? StationChrome.ice : StationChrome.line, lineWidth: 1)
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

#if DEBUG
@available(iOS 15.0, *)
struct StationKeyboardRootView_Previews: PreviewProvider {
    static var previews: some View {
        StationKeyboardRootView(
            onKey: { _ in },
            onDelete: {},
            onReturn: {},
            onSpace: {},
            onTab: {},
            onModifierToggle: { _, _ in }
        )
        .background(Color.black)
        .previewInterfaceOrientation(.landscapeLeft)
        .previewDevice("iPad (9th generation)")
        .previewDisplayName("Station keyboard")
    }
}
#endif

#endif
