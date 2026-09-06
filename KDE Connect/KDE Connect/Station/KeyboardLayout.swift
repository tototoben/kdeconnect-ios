/*
 * SPDX-FileCopyrightText: 2026 station-mode contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import Foundation

/// Multi-language keyboard layouts (3 letter rows, no number row).
/// Based on simple-keyboard-layouts data, simplified to letter keys only.
/// Each layout provides both `charRows` (default) and `shiftRows` (shift active)
/// so that non-Latin scripts and umlauts work correctly with the shift key.
enum KeyboardLayout: String, CaseIterable, Codable {
    case english
    case german
    case french
    case swedish
    case turkish
    case russian
    case arabic

    /// Display name for the layout switcher UI.
    var displayName: String {
        switch self {
        case .english:  return "English (QWERTY)"
        case .german:   return "Deutsch (QWERTZ)"
        case .french:   return "Français (AZERTY)"
        case .swedish:  return "Svenska"
        case .turkish:  return "Türkçe"
        case .russian:  return "Русский"
        case .arabic:   return "العربية"
        }
    }

    /// Short label for the layout button (fits in the modifiers panel).
    var shortLabel: String {
        switch self {
        case .english:  return "EN"
        case .german:   return "DE"
        case .french:   return "FR"
        case .swedish:  return "SV"
        case .turkish:  return "TR"
        case .russian:  return "RU"
        case .arabic:   return "AR"
        }
    }

    /// Three rows of default (lowercase) letters, top to bottom.
    var charRows: [[String]] {
        switch self {
        case .english:
            return [
                ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                ["z", "x", "c", "v", "b", "n", "m"],
            ]
        case .german:
            return [
                ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                ["y", "x", "c", "v", "b", "n", "m"],
            ]
        case .french:
            return [
                ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
                ["w", "x", "c", "v", "b", "n"],
            ]
        case .swedish:
            return [
                ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ö"],
                ["z", "x", "c", "v", "b", "n", "m", "å", "ä"],
            ]
        case .turkish:
            return [
                ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                ["a", "s", "d", "f", "g", "h", "j", "k", "l", "i"],
                ["z", "x", "c", "v", "b", "n", "m", "ç", "ş", "ğ"],
            ]
        case .russian:
            return [
                ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з"],
                ["ф", "ы", "в", "а", "п", "р", "о", "л", "д"],
                ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"],
            ]
        case .arabic:
            return [
                ["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح"],
                ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك"],
                ["ظ", "ط", "ذ", "د", "ز", "ر", "و", "ة", "ى"],
            ]
        }
    }

    /// Three rows of shifted (uppercase / alternate) letters, top to bottom.
    /// For Latin layouts this is uppercase. For Cyrillic/Arabic it's the
    /// shifted variant (Cyrillic uppercase, Arabic has no case so stays same).
    var shiftRows: [[String]] {
        switch self {
        case .english:
            return [
                ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
                ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
                ["Z", "X", "C", "V", "B", "N", "M"],
            ]
        case .german:
            return [
                ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "Ü"],
                ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ö", "Ä"],
                ["Y", "X", "C", "V", "B", "N", "M"],
            ]
        case .french:
            return [
                ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"],
                ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"],
                ["W", "X", "C", "V", "B", "N"],
            ]
        case .swedish:
            return [
                ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
                ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ö"],
                ["Z", "X", "C", "V", "B", "N", "M", "Å", "Ä"],
            ]
        case .turkish:
            return [
                ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
                ["A", "S", "D", "F", "G", "H", "J", "K", "L", "İ"],
                ["Z", "X", "C", "V", "B", "N", "M", "Ç", "Ş", "Ğ"],
            ]
        case .russian:
            return [
                ["Й", "Ц", "У", "К", "Е", "Н", "Г", "Ш", "Щ", "З"],
                ["Ф", "Ы", "В", "А", "П", "Р", "О", "Л", "Д"],
                ["Я", "Ч", "С", "М", "И", "Т", "Ь", "Б", "Ю"],
            ]
        case .arabic:
            return [
                ["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح"],
                ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك"],
                ["ظ", "ط", "ذ", "د", "ز", "ر", "و", "ة", "ى"],
            ]
        }
    }

    /// Next layout in the cycle (for the switcher button).
    var next: KeyboardLayout {
        let all = KeyboardLayout.allCases
        guard let idx = all.firstIndex(of: self) else { return .english }
        return all[(idx + 1) % all.count]
    }
}
