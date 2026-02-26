import Foundation

/// The 20 canonical riwayaat from the 7 mutawatir qira'at (plus 3 mashhur completing the 10).
/// Stored as String rawValue in @Model fields for CloudKit compatibility.
enum Riwayah: String, CaseIterable, Codable {

    // ── Asim (عاصم) ────────────────────────────────────────────
    case hafs    = "hafs"     // رواية حفص — most widely used globally
    case shuabah = "shuabah"  // رواية شعبة

    // ── Nafi (نافع) ────────────────────────────────────────────
    case warsh  = "warsh"    // رواية ورش — dominant in North/West Africa
    case qaloon = "qaloon"   // رواية قالون — dominant in Libya, Tunisia

    // ── Ibn Kathir (ابن كثير) ───────────────────────────────────
    case bazzi  = "bazzi"    // رواية البزي
    case qunbul = "qunbul"   // رواية قنبل

    // ── Abu Amr al-Basri (أبو عمرو البصري) ─────────────────────
    case dooriAbuAmr = "doori_abu_amr"  // رواية الدوري عن أبي عمرو
    case soosi       = "soosi"          // رواية السوسي

    // ── Ibn Amir al-Shami (ابن عامر الشامي) ─────────────────────
    case hisham     = "hisham"      // رواية هشام
    case ibnDhakwan = "ibn_dhakwan" // رواية ابن ذكوان

    // ── Hamza (حمزة) ───────────────────────────────────────────
    case khalafAnHamza = "khalaf_an_hamza"  // رواية خلف عن حمزة
    case khallad       = "khallad"          // رواية خلاد

    // ── Al-Kisai (الكسائي) ─────────────────────────────────────
    case abulHarith   = "abul_harith"    // رواية أبي الحارث
    case dooriAlKisai = "doori_al_kisai" // رواية الدوري عن الكسائي

    // ── Abu Jafar (أبو جعفر) — from the 10 qira'at ─────────────
    case ibnWardan = "ibn_wardan"  // رواية ابن وردان
    case ibnJammaz = "ibn_jammaz"  // رواية ابن جماز

    // ── Yaqub al-Hadrami (يعقوب الحضرمي) ──────────────────────
    case ruways = "ruways"  // رواية رويس
    case rawh   = "rawh"    // رواية روح

    // ── Khalaf al-Ashir (خلف العاشر) ───────────────────────────
    case ishaq = "ishaq"  // رواية إسحاق
    case idris = "idris"  // رواية إدريس

    // MARK: - Display metadata

    var displayName: String {
        switch self {
        case .hafs:           return "Hafs 'an 'Asim"
        case .shuabah:        return "Shu'bah 'an 'Asim"
        case .warsh:          return "Warsh 'an Nafi'"
        case .qaloon:         return "Qaloon 'an Nafi'"
        case .bazzi:          return "Al-Bazzi 'an Ibn Kathir"
        case .qunbul:         return "Qunbul 'an Ibn Kathir"
        case .dooriAbuAmr:    return "Ad-Doori 'an Abi 'Amr"
        case .soosi:          return "As-Soosi 'an Abi 'Amr"
        case .hisham:         return "Hisham 'an Ibn 'Amir"
        case .ibnDhakwan:     return "Ibn Dhakwan 'an Ibn 'Amir"
        case .khalafAnHamza:  return "Khalaf 'an Hamza"
        case .khallad:        return "Khallad 'an Hamza"
        case .abulHarith:     return "Abu'l-Harith 'an al-Kisa'i"
        case .dooriAlKisai:   return "Ad-Doori 'an al-Kisa'i"
        case .ibnWardan:      return "Ibn Wardan 'an Abi Ja'far"
        case .ibnJammaz:      return "Ibn Jammaz 'an Abi Ja'far"
        case .ruways:         return "Ruways 'an Ya'qub"
        case .rawh:           return "Rawh 'an Ya'qub"
        case .ishaq:          return "Ishaq 'an Khalaf al-'Ashir"
        case .idris:          return "Idris 'an Khalaf al-'Ashir"
        }
    }

    var qira_ah: String {
        switch self {
        case .hafs, .shuabah:             return "Asim"
        case .warsh, .qaloon:             return "Nafi"
        case .bazzi, .qunbul:             return "Ibn Kathir"
        case .dooriAbuAmr, .soosi:        return "Abu Amr"
        case .hisham, .ibnDhakwan:        return "Ibn Amir"
        case .khalafAnHamza, .khallad:    return "Hamza"
        case .abulHarith, .dooriAlKisai:  return "Al-Kisai"
        case .ibnWardan, .ibnJammaz:      return "Abu Jafar"
        case .ruways, .rawh:              return "Yaqub"
        case .ishaq, .idris:              return "Khalaf al-Ashir"
        }
    }
}
