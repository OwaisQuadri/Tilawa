import Foundation

/// A hardcoded preset for a well-known CDN reciter.
/// To add more reciters, append to `ReciterPreset.all`.
struct ReciterPreset: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let riwayah: Riwayah
    let style: String   // "murattal" | "mujawwad" | "muallim"
    let source: Source

    enum Source {
        case manifestBaseURL(baseURL: String, namingPattern: ReciterNamingPattern, format: String, bitrate: Int? = nil)
        case urlTemplate(template: String, format: String)
    }

    // MARK: - Built-in presets

    static let all: [ReciterPreset] = [
        // MARK: Hafs
        ReciterPreset(
            id: "minshawy-hafs-murattal",
            name: "Muhammad Siddiq Al-Minshawi",
            shortName: "Minshawi",
            riwayah: .hafs,
            style: "murattal",
            source: .manifestBaseURL(
                baseURL: "https://everyayah.com/data/Minshawy_Murattal_128kbps/",
                namingPattern: .surahAyah,
                format: "mp3",
                bitrate: 128
            )
        ),
        ReciterPreset(
            id: "husary-hafs-murattal",
            name: "Mahmoud Khalil Al-Husary",
            shortName: "Husary",
            riwayah: .hafs,
            style: "murattal",
            source: .urlTemplate(
                template: "https://audio-cdn.tarteel.ai/quran/husary/${sss}${aaa}.mp3",
                format: "mp3"
            )
        ),
        ReciterPreset(
            id: "dosari-hafs-murattal",
            name: "Yasser Ibn Rashid Al-Dosari",
            shortName: "Al-Dosari",
            riwayah: .hafs,
            style: "murattal",
            source: .urlTemplate(
                template: "https://audio-cdn.tarteel.ai/quran/yasserAlDosari/${sss}${aaa}.mp3",
                format: "mp3"
            )
        ),
        ReciterPreset(
            id: "alafasy-hafs-murattal",
            name: "Mishary Rashid Alafasy",
            shortName: "Alafasy",
            riwayah: .hafs,
            style: "murattal",
            source: .urlTemplate(
                template: "https://audio-cdn.tarteel.ai/quran/alafasy/${sss}${aaa}.mp3",
                format: "mp3"
            )
        ),
        ReciterPreset(
            id: "hudhaify-hafs-murattal",
            name: "Ali Ibn Abd-ur-Rahman Al-Hudhaify",
            shortName: "Hudhaify",
            riwayah: .hafs,
            style: "murattal",
            source: .manifestBaseURL(
                baseURL: "https://everyayah.com/data/Hudhaify_128kbps/",
                namingPattern: .surahAyah,
                format: "mp3",
                bitrate: 128
            )
        ),
        // MARK: Warsh
        ReciterPreset(
            id: "ibrahim-dosary-warsh-murattal",
            name: "Ibrahim Al-Dosary",
            shortName: "Al-Dosary (Warsh)",
            riwayah: .warsh,
            style: "murattal",
            source: .manifestBaseURL(
                baseURL: "https://everyayah.com/data/warsh/warsh_ibrahim_aldosary_128kbps/",
                namingPattern: .surahAyah,
                format: "mp3",
                bitrate: 128
            )
        ),
    ]
}
