import SwiftUI

/// Colors of the tajweed rules (cpfair identifiers), each light and dark.
///
/// Grouped as in common tajweed Mushafs: Medd red to dark red, Gunne and İdğam
/// green, İhfa violet, İklab blue, Kalkale yellow; silent letters toned down to gray.
public enum TajweedColors {
    public static let rules = [
        "madd_2", "madd_246", "madd_muttasil", "madd_munfasil", "madd_6", "ghunnah", "idghaam_ghunnah",
        "idghaam_no_ghunnah", "idghaam_shafawi", "idghaam_mutajanisayn", "idghaam_mutaqaribayn", "ikhfa",
        "ikhfa_shafawi", "iqlab", "qalqalah", "hamzat_wasl", "lam_shamsiyyah", "silent",
    ]

    public static func color(_ rule: String, dark: Bool) -> Color {
        let (lightValue, darkValue): (UInt32, UInt32) =
            switch rule {
            case "madd_2": (0xB03A2E, 0xFF8A7A)
            case "madd_246": (0xC85A00, 0xFFA45C)
            case "madd_muttasil": (0x8E1B1B, 0xFF6464)
            case "madd_munfasil": (0xA0302A, 0xFF7468)
            case "madd_6": (0x6E0D25, 0xFF5C8A)
            case "ghunnah": (0x1E7A45, 0x5DDC8F)
            case "idghaam_ghunnah": (0x0E6B5A, 0x4FD6B5)
            case "idghaam_no_ghunnah", "idghaam_shafawi", "idghaam_mutajanisayn", "idghaam_mutaqaribayn":
                (0x4F6E5A, 0x9CC7AA)
            case "ikhfa", "ikhfa_shafawi": (0x6C3483, 0xC9A0DC)
            case "iqlab": (0x1F5F8B, 0x7DBEF0)
            case "qalqalah": (0x9A7B00, 0xF2CF4A)
            default: (0x8A9096, 0x737B83)
            }
        return Color(hex: dark ? darkValue : lightValue)
    }
}
