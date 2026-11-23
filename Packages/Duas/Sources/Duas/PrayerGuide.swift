import Core
import Foundation

/// Prayer guide following Diyanet practice (Hanafi): overview → rakat plan → steps.
///
/// The rakat counts are the common table; the texts (Sübhâneke, Tahiyyât, Salli-Bârik)
/// are set by hand. Everything is listed under „Hoca-Prüfung offen“.
public enum PrayerGuide {
    public enum Kind: String, Sendable, Hashable { case sunnah = "sunnet", fard = "farz", witr = "vitir" }

    /// A prayer within a time, e.g. „4 rekât ilk sünnet“.
    public struct Part: Sendable, Hashable, Identifiable {
        public let id: String
        public let kind: Kind
        public let rakat: Int
        /// Gayr-i müekked: in the first sitting also Salli/Bârik, in the 3rd rakat Sübhâneke again.
        public let gayrMuakkadah: Bool
        public let name: Multilingual
    }

    public struct PrayerTime: Sendable, Hashable, Identifiable {
        public let id: String
        public let name: Multilingual
        public let parts: [Part]
    }

    static func k(
        _ id: String, _ kind: Kind, _ r: Int, _ name: Multilingual, ghayrMuakkadah: Bool = false
    ) -> Part {
        Part(id: id, kind: kind, rakat: r, gayrMuakkadah: ghayrMuakkadah, name: name)
    }

    static let sunnah = Multilingual(tr: "sünnet", de: "Sunna", en: "Sunnah")
    static let firstSunnah = Multilingual(tr: "ilk sünnet", de: "erste Sunna", en: "first Sunnah")
    static let lastSunnah = Multilingual(tr: "son sünnet", de: "letzte Sunna", en: "last Sunnah")
    static let fard = Multilingual(tr: "farz", de: "Pflicht (Fard)", en: "Fard")
    static let witr = Multilingual(tr: "vitir vacip", de: "Witr", en: "Witr")

    public static let prayerTimes: [PrayerTime] = [
        PrayerTime(
            id: "sabah", name: Multilingual(tr: "Sabah namazı", de: "Fajr-Gebet", en: "Fajr prayer"),
            parts: [k("sabah-s", .sunnah, 2, sunnah), k("sabah-f", .fard, 2, fard)]),
        PrayerTime(
            id: "ogle", name: Multilingual(tr: "Öğle namazı", de: "Dhuhr-Gebet", en: "Dhuhr prayer"),
            parts: [
                k("ogle-ilk", .sunnah, 4, firstSunnah), k("ogle-f", .fard, 4, fard),
                k("ogle-son", .sunnah, 2, lastSunnah),
            ]),
        PrayerTime(
            id: "ikindi", name: Multilingual(tr: "İkindi namazı", de: "Asr-Gebet", en: "Asr prayer"),
            parts: [k("ikindi-s", .sunnah, 4, sunnah, ghayrMuakkadah: true), k("ikindi-f", .fard, 4, fard)]),
        PrayerTime(
            id: "aksam", name: Multilingual(tr: "Akşam namazı", de: "Maghrib-Gebet", en: "Maghrib prayer"),
            parts: [k("aksam-f", .fard, 3, fard), k("aksam-s", .sunnah, 2, sunnah)]),
        PrayerTime(
            id: "yatsi", name: Multilingual(tr: "Yatsı namazı", de: "Isha-Gebet", en: "Isha prayer"),
            parts: [
                k("yatsi-ilk", .sunnah, 4, firstSunnah, ghayrMuakkadah: true), k("yatsi-f", .fard, 4, fard),
                k("yatsi-son", .sunnah, 2, lastSunnah), k("yatsi-v", .witr, 3, witr),
            ]),
    ]

    // MARK: Texts

    public struct Recitation: Sendable, Hashable {
        public let id: String
        public let name: Multilingual
        public let arabic: String?
        public let transliteration: String?
        public let meaning: Multilingual?
        /// Quran passage, if the text comes from the Quran (text then from the packages).
        public let verse: ContentKey?
    }

    /// Without „ve celle senâük“: according to Diyanet this is recited only in the funeral prayer (Cenaze-Namaz).
    public static let subhanaka = Recitation(
        id: "subhaneke", name: Multilingual(tr: "Sübhâneke", de: "Subhanaka", en: "Subhanaka"),
        arabic: "سُبْحَانَكَ اللّٰهُمَّ وَبِحَمْدِكَ وَتَبَارَكَ اسْمُكَ وَتَعَالٰى جَدُّكَ وَلَا اِلٰهَ غَيْرُكَ",
        transliteration:
            "Sübhâneke'llâhümme ve bi-hamdik ve tebâreke'smük ve teâlâ ceddük ve lâ ilâhe ğayruk.",
        meaning: Multilingual(
            tr:
                "Allah'ım! Seni her türlü eksiklikten tenzih ederim ve sana hamd ederim. Senin adın mübarektir. Şanın yücedir. Senden başka ilah yoktur.",
            de:
                "O Allah, gepriesen bist Du, und Dir gebührt das Lob. Gesegnet ist Dein Name, erhaben Deine Majestät, und es gibt keinen Gott außer Dir.",
            en:
                "Glory be to You, O Allah, and praise. Blessed is Your name, exalted Your majesty, and there is no god but You."
        ),
        verse: nil)
    public static let taawwudhBasmala = Recitation(
        id: "euzu",
        name: Multilingual(tr: "Eûzü-Besmele", de: "Ta'awwudh und Basmala", en: "Ta'awwudh and Basmala"),
        arabic: "اَعُوذُ بِاللّٰهِ مِنَ الشَّيْطَانِ الرَّج۪يمِ ۞ بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّح۪يمِ",
        transliteration: "Eûzü billâhi mine'ş-şeytâni'r-racîm. Bismillâhirrahmânirrahîm.",
        meaning: Multilingual(
            tr: "Kovulmuş şeytandan Allah'a sığınırım. Rahmân ve Rahîm olan Allah'ın adıyla.",
            de:
                "Ich suche Zuflucht bei Allah vor dem verfluchten Satan. Im Namen Allahs, des Allerbarmers, des Barmherzigen.",
            en:
                "I seek refuge in Allah from the accursed Satan. In the name of Allah, the Most Gracious, the Most Merciful."
        ),
        verse: nil)
    public static let fatiha = Recitation(
        id: "fatiha", name: Multilingual(tr: "Fâtiha", de: "Al-Fatiha", en: "Al-Fatiha"), arabic: nil,
        transliteration: nil,
        meaning: nil,
        verse: .surah(1))
    public static let additionalSurah = Recitation(
        id: "zamm",
        name: Multilingual(
            tr: "Zamm-ı sûre (ör. İhlâs)", de: "Weitere Sure (z. B. Al-Ikhlas)",
            en: "Additional surah (e.g. Al-Ikhlas)"),
        arabic: nil, transliteration: nil, meaning: nil, verse: .surah(112))
    public static let rukuTasbih = Recitation(
        id: "ruku",
        name: Multilingual(
            tr: "Rükû tesbihi (3 kez)", de: "Tasbih im Ruku' (3×)",
            en: "Glorification in bowing (3×)"),
        arabic: "سُبْحَانَ رَبِّيَ الْعَظ۪يمِ", transliteration: "Sübhâne rabbiye'l-azîm",
        meaning: Multilingual(
            tr: "Yüce Rabbimi tenzih ederim.", de: "Gepriesen sei mein Herr, der Allmächtige.",
            en: "Glory be to my Lord, the Magnificent."),
        verse: nil)
    public static let qawmah = Recitation(
        id: "kavme", name: Multilingual(tr: "Rükûdan doğrulurken", de: "Beim Aufrichten", en: "When rising"),
        arabic: "سَمِعَ اللّٰهُ لِمَنْ حَمِدَهُ ۞ رَبَّنَا لَكَ الْحَمْدُ",
        transliteration: "Semi'allâhü li-men hamideh. Rabbenâ leke'l-hamd.",
        meaning: Multilingual(
            tr: "Allah kendisine hamd edeni işitir. Rabbimiz, hamd sanadır.",
            de: "Allah hört den, der Ihn lobt. Unser Herr, Dir gebührt das Lob.",
            en: "Allah hears whoever praises Him. Our Lord, to You is the praise."),
        verse: nil)
    public static let sajdahTasbih = Recitation(
        id: "secde",
        name: Multilingual(
            tr: "Secde tesbihi (3 kez)", de: "Tasbih in der Sajda (3×)",
            en: "Glorification in prostration (3×)"),
        arabic: "سُبْحَانَ رَبِّيَ الْاَعْلٰى", transliteration: "Sübhâne rabbiye'l-a'lâ",
        meaning: Multilingual(
            tr: "En yüce olan Rabbimi tenzih ederim.", de: "Gepriesen sei mein Herr, der Höchste.",
            en: "Glory be to my Lord, the Most High."),
        verse: nil)
    public static let tahiyyat = Recitation(
        id: "tahiyyat", name: Multilingual(tr: "Ettehiyyâtü", de: "At-Tahiyyat", en: "At-Tahiyyat"),
        arabic:
            "اَلتَّحِيَّاتُ لِلّٰهِ وَالصَّلَوَاتُ وَالطَّيِّبَاتُ اَلسَّلَامُ عَلَيْكَ اَيُّهَا النَّبِيُّ وَرَحْمَةُ اللّٰهِ وَبَرَكَاتُهُ اَلسَّلَامُ عَلَيْنَا وَعَلٰى عِبَادِ اللّٰهِ الصَّالِح۪ينَ اَشْهَدُ اَنْ لَا اِلٰهَ اِلَّا اللّٰهُ وَاَشْهَدُ اَنَّ مُحَمَّدًا عَبْدُهُ وَرَسُولُهُ",
        transliteration:
            "Et-tahiyyâtü lillâhi ve's-salevâtü ve't-tayyibât. Es-selâmü aleyke eyyühe'n-nebiyyü ve rahmetullâhi ve berakâtüh. Es-selâmü aleynâ ve alâ ibâdillâhi's-sâlihîn. Eşhedü en lâ ilâhe illallâh ve eşhedü enne Muhammeden abdühû ve rasûlüh.",
        meaning: Multilingual(
            tr:
                "Bütün tahiyyeler, salavat ve güzel sözler Allah'a mahsustur. Ey Peygamber! Allah'ın selâmı, rahmet ve bereketi senin üzerine olsun. Selâm bizim üzerimize ve Allah'ın salih kulları üzerine olsun. Şahitlik ederim ki Allah'tan başka ilah yoktur ve yine şahitlik ederim ki Muhammed O'nun kulu ve elçisidir.",
            de:
                "Alle Grüße, Gebete und guten Worte gebühren Allah. Friede sei mit dir, o Prophet, und die Barmherzigkeit Allahs und Sein Segen. Friede sei mit uns und mit den rechtschaffenen Dienern Allahs. Ich bezeuge, dass es keinen Gott gibt außer Allah, und ich bezeuge, dass Muhammad Sein Diener und Gesandter ist.",
            en:
                "All greetings, prayers and good words are for Allah. Peace be upon you, O Prophet, and the mercy of Allah and His blessings. Peace be upon us and upon the righteous servants of Allah. I bear witness that there is no god but Allah, and I bear witness that Muhammad is His servant and messenger."
        ),
        verse: nil)
    public static let salli = Recitation(
        id: "salli", name: Multilingual(tr: "Allâhümme salli", de: "Salawat (Salli)", en: "Salawat (Salli)"),
        arabic: "اَللّٰهُمَّ صَلِّ عَلٰى مُحَمَّدٍ وَعَلٰى اٰلِ مُحَمَّدٍ كَمَا صَلَّيْتَ عَلٰى اِبْرٰه۪يمَ وَعَلٰى اٰلِ اِبْرٰه۪يمَ اِنَّكَ حَم۪يدٌ مَج۪يدٌ",
        transliteration:
            "Allâhümme salli alâ Muhammedin ve alâ âli Muhammed. Kemâ salleyte alâ İbrâhîme ve alâ âli İbrâhîm. İnneke hamîdün mecîd.",
        meaning: Multilingual(
            tr:
                "Allah'ım! İbrahim'e ve âline rahmet ettiğin gibi Muhammed'e ve âline de rahmet et. Şüphesiz sen övülmeye layık ve şanı yüce olansın.",
            de:
                "O Allah, segne Muhammad und die Familie Muhammads, wie Du Ibrahim und die Familie Ibrahims gesegnet hast. Du bist des Lobes würdig und ruhmreich.",
            en:
                "O Allah, send blessings upon Muhammad and the family of Muhammad as You sent blessings upon Ibrahim and the family of Ibrahim. You are Praiseworthy, Glorious."
        ),
        verse: nil)
    public static let barik = Recitation(
        id: "barik", name: Multilingual(tr: "Allâhümme bârik", de: "Salawat (Barik)", en: "Salawat (Barik)"),
        arabic: "اَللّٰهُمَّ بَارِكْ عَلٰى مُحَمَّدٍ وَعَلٰى اٰلِ مُحَمَّدٍ كَمَا بَارَكْتَ عَلٰى اِبْرٰه۪يمَ وَعَلٰى اٰلِ اِبْرٰه۪يمَ اِنَّكَ حَم۪يدٌ مَج۪يدٌ",
        transliteration:
            "Allâhümme bârik alâ Muhammedin ve alâ âli Muhammed. Kemâ bârekte alâ İbrâhîme ve alâ âli İbrâhîm. İnneke hamîdün mecîd.",
        meaning: Multilingual(
            tr:
                "Allah'ım! İbrahim'e ve âline bereket verdiğin gibi Muhammed'e ve âline de bereket ver. Şüphesiz sen övülmeye layık ve şanı yüce olansın.",
            de:
                "O Allah, gib Muhammad und der Familie Muhammads Segen, wie Du Ibrahim und der Familie Ibrahims Segen gegeben hast. Du bist des Lobes würdig und ruhmreich.",
            en:
                "O Allah, bless Muhammad and the family of Muhammad as You blessed Ibrahim and the family of Ibrahim. You are Praiseworthy, Glorious."
        ),
        verse: nil)
    public static let rabbanaAtina = Recitation(
        id: "rabbena",
        name: Multilingual(
            tr: "Rabbenâ âtinâ, Rabbenağfirlî", de: "Rabbana atina, Rabbanaghfirli",
            en: "Rabbana atina, Rabbanaghfirli"),
        arabic: nil, transliteration: nil, meaning: nil, verse: .verse(surah: 2, verse: 201))
    public static let qunut = Recitation(
        id: "kunut", name: Multilingual(tr: "Kunut duaları", de: "Qunut-Duas", en: "Qunut supplications"),
        arabic: nil, transliteration: nil,
        meaning: Multilingual(
            tr: "Kunut dualarının metni henüz uygulamada yok; bir hocadan öğren.",
            de: "Der Text der Qunut-Duas fehlt noch in der App; lern ihn bei einem Imam oder Lehrer.",
            en: "The text of the Qunut supplications isn't in the app yet; learn it from a teacher."),
        verse: nil)

    // MARK: Steps

    public struct Step: Sendable, Hashable {
        public let rakat: Int
        public let title: Multilingual
        public let explanation: Multilingual?
        public let recitations: [Recitation]
    }

    static func a(
        _ r: Int, _ tr: String, _ de: String, _ en: String, _ o: [Recitation] = [], note: Multilingual? = nil
    ) -> Step {
        Step(rakat: r, title: Multilingual(tr: tr, de: de, en: en), explanation: note, recitations: o)
    }

    /// All steps of a prayer in order; the count runs across all rakat.
    public static func steps(_ k: Part) -> [Step] {
        var l: [Step] = []
        l.append(
            a(
                1, "Niyet", "Absicht", "Intention",
                note: Multilingual(
                    tr: "Kalben hangi namazı kılacağını belirle, örneğin: \(k.name.tr).",
                    de: "Fasse im Herzen die Absicht für dieses Gebet: \(k.name.de).",
                    en: "Make the intention in your heart for this prayer: \(k.name.en).")))
        l.append(
            a(
                1, "İftitah tekbiri", "Eröffnungs-Takbir", "Opening takbir",
                note: Multilingual(
                    tr:
                        "\"Allâhü ekber\" diyerek eller kaldırılır: erkekler kulak hizasına, kadınlar omuz hizasına.",
                    de:
                        "Mit „Allahu akbar“ die Hände heben: Männer bis zu den Ohren, Frauen bis zu den Schultern.",
                    en: "Raise the hands saying \"Allahu akbar\": men to the ears, women to the shoulders.")))
        for r in 1...k.rakat {
            let first = r == 1
            let lastRakat = r == k.rakat
            let thirdGhayr = r == 3 && k.gayrMuakkadah
            var qiyam: [Recitation] = []
            if first || thirdGhayr { qiyam.append(subhanaka) }
            if first { qiyam.append(taawwudhBasmala) }
            qiyam.append(fatiha)
            // Zamm-ı sûre: in sunnah and Vitir in every rakat, in the fard only in the first two.
            if k.kind != .fard || r <= 2 { qiyam.append(additionalSurah) }
            if r > 1 {
                l.append(a(r, "\(r). rekâta kalk", "Aufstehen zum \(r). Rak'a", "Stand for rak'ah \(r)"))
            }
            l.append(
                a(r, "Kıyam ve kıraat", "Stehen (Qiyam) und Rezitation", "Standing and recitation", qiyam))
            if k.kind == .witr && lastRakat {
                l.append(
                    a(
                        r, "Tekbir ve Kunut", "Takbir und Qunut", "Takbir and Qunut", [qunut],
                        note: Multilingual(
                            tr:
                                "Rükûdan önce \"Allâhü ekber\" deyip eller kaldırılır, sonra Kunut duaları okunur.",
                            de:
                                "Vor dem Ruku' „Allahu akbar“ sagen, die Hände heben, dann die Qunut-Duas.",
                            en:
                                "Before bowing, say \"Allahu akbar\" raising the hands, then recite the Qunut."
                        )))
            }
            l.append(a(r, "Rükû", "Verbeugung (Ruku')", "Bowing (Ruku')", [rukuTasbih]))
            l.append(a(r, "Rükûdan doğrulma", "Aufrichten", "Rising", [qawmah]))
            l.append(a(r, "Birinci secde", "Erste Sajda", "First prostration", [sajdahTasbih]))
            l.append(
                a(
                    r, "Celse ve ikinci secde", "Sitzen (Jalsa) und zweite Sajda",
                    "Sitting and second prostration", [sajdahTasbih]))
            if r == 2 && !lastRakat {
                var sitting = [tahiyyat]
                if k.gayrMuakkadah { sitting += [salli, barik] }
                l.append(a(r, "Birinci oturuş", "Erstes Sitzen (Qa'da)", "First sitting", sitting))
            }
            if lastRakat {
                l.append(
                    a(
                        r, "Son oturuş", "Letztes Sitzen (Qa'da)", "Final sitting",
                        [tahiyyat, salli, barik, rabbanaAtina]))
                l.append(
                    a(
                        r, "Selâm", "Salam", "Salam",
                        note: Multilingual(
                            tr: "Önce sağa, sonra sola \"Es-selâmü aleyküm ve rahmetullâh\" denir.",
                            de: "Erst nach rechts, dann nach links „As-salamu alaikum wa rahmatullah“.",
                            en: "Turn right, then left, saying \"As-salamu alaikum wa rahmatullah\".")))
            }
        }
        return l
    }
}
