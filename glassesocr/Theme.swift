// filename: theme.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis
// date: may 7 2026

import SwiftUI

/// visual identity for glasses ocr
///
/// palette: muted teal green over off white surface
/// mono accents pair with ocr / typewriter feel
/// matches slideshow design
///
/// to swap in courier prime / maven pro instead of system fallbacks:
///   1. add ttf files to xcode project
///   2. register them under uiappfonts in info.plist
///   3. set theme.usecustomfonts to true
/// font helpers below pick them up automatically;
/// otherwise they fall back to closest system designs
/// (.monospaced for courier, default sans for maven)
enum Theme {

    // MARK: colors

    // primary muted teal green, used for ctas and headings
    static let primary = Color(red: 94 / 255, green: 139 / 255, blue: 126 / 255)
    // darker variant for accent text on light backgrounds
    static let primaryDark = Color(red: 63 / 255, green: 107 / 255, blue: 92 / 255)
    // soft tint for secondary buttons, borders, icon backgrounds
    static let primaryLight = Color(red: 168 / 255, green: 201 / 255, blue: 189 / 255)
    // app wide neutral surface, off white with hint of green
    static let surface = Color(red: 245 / 255, green: 247 / 255, blue: 244 / 255)
    // elevated surface for cards and panels
    static let surfaceElevated = Color(red: 252 / 255, green: 253 / 255, blue: 251 / 255)
    // subtle dividers and stroke outlines
    static let stroke = Color(red: 217 / 255, green: 226 / 255, blue: 222 / 255)

    // status colors picked to coexist with muted palette
    // (default reds and greens looked too saturated next to teal)
    static let danger = Color(red: 191 / 255, green: 71 / 255, blue: 71 / 255)
    static let success = Color(red: 70 / 255, green: 138 / 255, blue: 95 / 255)

    // MARK: fonts

    // flip to true once maven pro / courier prime are registered in info.plist
    // until then, helpers below return system equivalents
    static let useCustomFonts = false

    // large display text used for screen titles
    static func display(_ size: CGFloat = 34, weight: Font.Weight = .semibold) -> Font {
        useCustomFonts
            ? .custom("MavenPro-\(weight.mavenSuffix)", size: size)
            : .system(size: size, weight: weight, design: .default)
    }

    // body text in default sans serif design
    static func body(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
        useCustomFonts
            ? .custom("MavenPro-\(weight.mavenSuffix)", size: size)
            : .system(size: size, weight: weight, design: .default)
    }

    // monospaced text used for results, labels, technical readouts
    // (typewriter feel reinforces ocr theme)
    static func mono(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
        useCustomFonts
            ? .custom("CourierPrime-\(weight.courierSuffix)", size: size)
            : .system(size: size, weight: weight, design: .monospaced)
    }
}

// helpers that map font.weight values to font filename suffixes
// (only used when usecustomfonts is true)
private extension Font.Weight {

    // maven pro ships full weight range
    var mavenSuffix: String {
        switch self {
        case .black, .heavy:        return "Black"
        case .bold:                 return "Bold"
        case .semibold:             return "SemiBold"
        case .medium:               return "Medium"
        case .light, .thin, .ultraLight: return "Regular"
        default:                    return "Regular"
        }
    }

    // courier prime ships only regular and bold (plus italics)
    // so heavier weights collapse to bold
    var courierSuffix: String {
        switch self {
        case .bold, .heavy, .black, .semibold: return "Bold"
        default:                                return "Regular"
        }
    }
}

// MARK: reusable view modifiers

extension View {

    // card style panel with elevated background and subtle stroke
    // used for result panels, photo previews, etc
    func themedCard(padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }

    // primary cta button: filled teal, white text
    // applied to the label view inside a Button
    func themedPrimaryButton() -> some View {
        self
            .font(Theme.body(17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // secondary tinted button: light teal pill, dark teal text
    // for less prominent actions like skip or stop
    func themedSecondaryButton() -> some View {
        self
            .font(Theme.body(15, weight: .medium))
            .foregroundStyle(Theme.primaryDark)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Theme.primaryLight.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
