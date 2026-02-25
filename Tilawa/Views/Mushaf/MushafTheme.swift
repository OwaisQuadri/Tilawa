import SwiftUI

struct MushafTheme: Equatable, Hashable, Sendable {
    let name: String
    let backgroundColor: Color
    let textColor: Color
    let highlightColor: Color
    let headerColor: Color
    let pageBorderColor: Color

    static let light = MushafTheme(
        name: "Light",
        backgroundColor: Color(.systemBackground),
        textColor: Color(.label),
        highlightColor: Color(.systemYellow).opacity(0.3),
        headerColor: Color(.systemBrown).opacity(0.1),
        pageBorderColor: .black
    )

    static let dark = MushafTheme(
        name: "Dark",
        backgroundColor: Color(white: 0.1),
        textColor: Color(white: 0.9),
        highlightColor: Color(.systemOrange).opacity(0.3),
        headerColor: Color(white: 0.15),
        pageBorderColor: Color(white: 0.25)
    )

    static let sepia = MushafTheme(
        name: "Sepia",
        backgroundColor: Color(red: 0.96, green: 0.93, blue: 0.87),
        textColor: Color(red: 0.26, green: 0.20, blue: 0.14),
        highlightColor: Color(.systemOrange).opacity(0.25),
        headerColor: Color(red: 0.90, green: 0.85, blue: 0.78),
        pageBorderColor: Color(red: 0.78, green: 0.72, blue: 0.64)
    )
}
