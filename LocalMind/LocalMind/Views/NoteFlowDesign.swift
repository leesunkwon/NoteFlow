import SwiftUI
import UIKit

// 앱 전반에서 반복해서 쓰는 색상, 반경, 햅틱 스타일을 한곳에 모읍니다.
enum NoteFlowDesign {
    static let ink = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
    static let charcoal = Color(red: 57 / 255, green: 57 / 255, blue: 59 / 255)
    static let mute = Color(red: 112 / 255, green: 112 / 255, blue: 114 / 255)
    static let canvas = Color.white
    static let softCloud = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let hairline = Color(red: 202 / 255, green: 202 / 255, blue: 203 / 255)
    static let hairlineSoft = Color(red: 229 / 255, green: 229 / 255, blue: 229 / 255)
    static let sale = Color(red: 211 / 255, green: 0, blue: 5 / 255)
    static let success = Color(red: 0, green: 125 / 255, blue: 72 / 255)

    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 16
    static let radiusLarge: CGFloat = 24
    static let radiusPill: CGFloat = 30
}

@MainActor
enum NoteFlowHaptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
