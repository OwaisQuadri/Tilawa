import SwiftUI

struct MushafTheme: Equatable, Hashable, Sendable {
    let name: String
    let backgroundColor: Color
    let textColor: Color
    let highlightColor: Color
    let headerColor: Color
    let pageBorderColor: Color

    /// Follows system dark/light mode using standard adaptive colors.
    static let standard = MushafTheme(
        name: "Default",
        backgroundColor: Color("Theme/Standard/Background"),
        textColor: Color("Theme/Standard/Text"),
        highlightColor: Color("Theme/Standard/Highlight"),
        headerColor: Color("Theme/Standard/Header"),
        pageBorderColor: Color("Theme/Standard/PageBorder")
    )

    /// Warm paper tone in light mode; dark warm brown in dark mode.
    static let sepia = MushafTheme(
        name: "Sepia",
        backgroundColor: Color("Theme/Sepia/Background"),
        textColor: Color("Theme/Sepia/Text"),
        highlightColor: Color("Theme/Sepia/Highlight"),
        headerColor: Color("Theme/Sepia/Header"),
        pageBorderColor: Color("Theme/Sepia/PageBorder")
    )
}
