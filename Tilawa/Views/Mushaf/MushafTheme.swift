import UIKit

struct MushafTheme: Equatable, Sendable {
    let name: String
    let backgroundColor: UIColor
    let textColor: UIColor
    let highlightColor: UIColor
    let headerColor: UIColor
    let pageBorderColor: UIColor

    static let light = MushafTheme(
        name: "Light",
        backgroundColor: .systemBackground,
        textColor: .label,
        highlightColor: UIColor.systemYellow.withAlphaComponent(0.3),
        headerColor: UIColor.systemBrown.withAlphaComponent(0.1),
        pageBorderColor: UIColor.separator
    )

    static let dark = MushafTheme(
        name: "Dark",
        backgroundColor: UIColor(white: 0.1, alpha: 1),
        textColor: UIColor(white: 0.9, alpha: 1),
        highlightColor: UIColor.systemOrange.withAlphaComponent(0.3),
        headerColor: UIColor(white: 0.15, alpha: 1),
        pageBorderColor: UIColor(white: 0.25, alpha: 1)
    )

    static let sepia = MushafTheme(
        name: "Sepia",
        backgroundColor: UIColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1),
        textColor: UIColor(red: 0.26, green: 0.20, blue: 0.14, alpha: 1),
        highlightColor: UIColor.systemOrange.withAlphaComponent(0.25),
        headerColor: UIColor(red: 0.90, green: 0.85, blue: 0.78, alpha: 1),
        pageBorderColor: UIColor(red: 0.78, green: 0.72, blue: 0.64, alpha: 1)
    )
}
