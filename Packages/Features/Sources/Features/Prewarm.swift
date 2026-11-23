import ContentPacks
import Foundation
import Quran

/// What a page otherwise computes or loads when opened, done once after launch in the background
///.
/// Everything ends up in caches or in memory and is visible and clearable under Ayarlar → Depolama.
///
/// - Esmâ: the verses for all 99 names (about 0.5 s each in the debug build), remembered on disk.
/// - Quiz: the question pool, otherwise built when the quiz is first opened.
/// - Word-by-word translation: word meanings of all 114 surahs (Quran.com allows caching for one week;
///   `WordTranslations` renews anything older).
public enum Prewarm {
    @MainActor public static func start(contentProvider: (any ContentProvider)?, wordByWord: WordTranslations)
    {
        guard let contentProvider else { return }
        let language = translationLanguage()
        Task.detached(priority: .utility) {
            await DivineNameVerseCache.prepareAll(contentProvider)
            _ = await QuizPoolStore.shared.pool(contentProvider)
            for s in 1...114 {
                _ = await wordByWord.surah(s, language: language)
            }
        }
    }

}
