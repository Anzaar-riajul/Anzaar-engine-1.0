package com.techuboard.app

/**
 * TechuMorphologicalEngine
 * 
 * Computational Morphology & Inflection Engine for Bengali Language.
 * 
 * Dynamically synthesizes legitimate inflections, case markers, articles,
 * and spoken/standard verb conjugations from root stems without bloating
 * dictionary size.
 */
class TechuMorphologicalEngine {

    // Common Bengali Verb Roots (ধাতু)
    private val verbRoots = mapOf(
        "কর" to VerbClass.CONSONANT_STEM,      // করা (to do)
        "বল" to VerbClass.CONSONANT_STEM,      // বলা (to speak)
        "দেখ" to VerbClass.CONSONANT_STEM,     // দেখা (to see)
        "শোন" to VerbClass.VOWEL_SHIFT_STEM,   // শোনা (to listen)
        "লিখ" to VerbClass.CONSONANT_STEM,     // লেখা (to write)
        "পড়" to VerbClass.CONSONANT_STEM,      // পড়া (to read)
        "জান" to VerbClass.CONSONANT_STEM,     // জানা (to know)
        "পার" to VerbClass.CONSONANT_STEM,     // পারা (to be able to)
        "থাক" to VerbClass.CONSONANT_STEM,     // থাকা (to stay)
        "চল" to VerbClass.CONSONANT_STEM,      // চলা (to walk/run)
        "বস" to VerbClass.CONSONANT_STEM,      // বসা (to sit)
        "ভাব" to VerbClass.CONSONANT_STEM,     // ভাবা (to think)
        "ধর" to VerbClass.CONSONANT_STEM,      // ধরা (to catch)
        "খা" to VerbClass.OPEN_VOWEL_STEM,     // খাওয়া (to eat)
        "যা" to VerbClass.IRREGULAR_YA,        // যাওয়া (to go)
        "আস" to VerbClass.CONSONANT_STEM,      // আসা (to come)
        "দে" to VerbClass.GIVE_TAKE_STEM,      // দেওয়া (to give)
        "নে" to VerbClass.GIVE_TAKE_STEM,      // নেওয়া (to take)
        "হ" to VerbClass.BE_STEM               // হওয়া (to be/become)
    )

    private enum class VerbClass {
        CONSONANT_STEM,
        VOWEL_SHIFT_STEM,
        OPEN_VOWEL_STEM,
        GIVE_TAKE_STEM,
        IRREGULAR_YA,
        BE_STEM
    }

    // Standard Noun & Pronoun Case Endings / Definite Articles
    private val nounSuffixes = listOf(
        // Definite Articles (নির্দেশক)
        "টা", "টি", "গুলো", "গুলি", "খান", "খানি",
        // Case Markers (বিভক্তি)
        "র", "এর", "কে", "রে", "তে", "এ", "য়ে", "য়",
        // Compound Inflections (যৌগিক রূপ)
        "টার", "টাকে", "টাতে", "টির", "টিকে", "টিতে",
        "গুলোর", "গুলোকে", "গুলোতে", "গুলির", "গুলিকে", "গুলিতে"
    )

    /**
     * Expands a stem or root into its natural Bengali inflections.
     */
    fun expandMorphology(stem: String): List<String> {
        val trimmed = stem.trim()
        if (trimmed.length < 2) return emptyList()

        val results = mutableListOf<String>()

        // 1. Check if stem is a known verb root or derivative
        val verbRoot = verbRoots.keys.firstOrNull { trimmed.startsWith(it) || it.startsWith(trimmed) }
        if (verbRoot != null) {
            results.addAll(conjugateVerb(verbRoot))
        }

        // 2. Synthesize Noun/Pronoun Inflections
        for (suffix in nounSuffixes) {
            val inflected = attachNounSuffix(trimmed, suffix)
            if (inflected.isNotEmpty()) {
                results.add(inflected)
            }
        }

        return results.distinct()
    }

    private fun attachNounSuffix(stem: String, suffix: String): String {
        val lastChar = stem.last()
        val endsWithVowelKar = isBengaliKar(lastChar)

        return when (suffix) {
            "এর" -> if (endsWithVowelKar) stem + "র" else stem + "ের"
            "র" -> if (endsWithVowelKar) stem + "র" else stem + "ের"
            "এ" -> if (endsWithVowelKar) stem + "য়ে" else stem + "ে"
            "য়" -> if (endsWithVowelKar) stem + "য়" else stem + "ে"
            "তে" -> stem + "তে"
            else -> stem + suffix
        }
    }

    private fun isBengaliKar(ch: Char): Boolean {
        return ch in '\u09BE'..'\u09CC' // া, ি, ী, ু, ূ, ৃ, ে, ৈ, ো, ৌ
    }

    /**
     * Generates all spoken, colloquial, and standard tenses for a root verb.
     */
    fun conjugateVerb(root: String): List<String> {
        return when (root) {
            "কর" -> listOf(
                "করি", "করো", "করেন", "করে", "করিস",
                "করছি", "করছো", "করছেন", "করছে", "করছিস",
                "করতেছি", "করতেছো", "করতেছেন", "করতেছে",
                "করলাম", "করলে", "করলেন", "করলো", "করলি",
                "করছিলাম", "করছিলে", "করছিলেন", "করছিল", "করছিলি",
                "করতাম", "করতে", "করতেন", "করতো", "করতিস",
                "করবো", "করবে", "করবেন", "করবি",
                "করেছি", "করেছো", "করেছেন", "করেছে",
                "করতে", "করলে", "করা", "করার", "করানো", "করিয়ে"
            )
            "বল" -> listOf(
                "বলি", "বলো", "বলেন", "বলে", "বলিস",
                "বলছি", "বলছো", "বলছেন", "বলছে", "বলছিস",
                "বলতেছি", "বলতেছো", "বলতেছেন", "বলতেছে",
                "বললাম", "বললে", "বললেন", "বললো", "বললি",
                "বলছিলাম", "বলছিলে", "বলছিলেন", "বলছিল",
                "বলবো", "বলবে", "বলবেন", "বলবি",
                "বলেছি", "বলেছো", "বলেছেন", "বলেছে",
                "বলতে", "বললে", "বলা", "বলার"
            )
            "দেখ" -> listOf(
                "দেখি", "দেখো", "দেখেন", "দেখে", "দেখিস",
                "দেখছি", "দেখছো", "দেখছেন", "দেখছে",
                "দেখতেছি", "দেখতেছো", "দেখতেছেন", "দেখতেছে",
                "দেখলাম", "দেখলে", "দেখলেন", "দেখলো",
                "দেখছিলাম", "দেখছিলে", "দেখছিলেন", "দেখছিল",
                "দেখবো", "দেখবে", "দেখবেন", "দেখবি",
                "দেখেছি", "দেখেছো", "দেখেছেন", "দেখেছে",
                "দেখতে", "দেখলে", "দেখা", "দেখার", "দেখানো"
            )
            "খা" -> listOf(
                "খাই", "খাও", "খান", "খায়", "খাস",
                "খাচ্ছি", "খাচ্ছো", "খাচ্ছেন", "খাচ্ছে",
                "খেলাম", "খেলে", "খেলেন", "খেলো", "খেলি",
                "খাচ্ছিলাম", "খাচ্ছিলে", "খাচ্ছিলেন", "খাচ্ছিল",
                "খাবো", "খাবে", "খাবেন", "খাবি",
                "খেয়েছি", "খেয়েছো", "খেয়েছেন", "খেয়েছে",
                "খেতে", "খেলে", "খাওয়া", "খাওয়ার"
            )
            "যা" -> listOf(
                "যাই", "যাও", "যান", "যায়", "যাস",
                "যাচ্ছি", "যাচ্ছো", "যাচ্ছেন", "যাচ্ছে",
                "গেলাম", "গেলে", "গেলেন", "গেলো", "গেলি",
                "যাচ্ছিলাম", "যাচ্ছিলে", "যাচ্ছিলেন", "যাচ্ছিল",
                "যাবো", "যাবে", "যাবেন", "যাবি",
                "গিয়েছি", "গিয়েছো", "গিয়েছেন", "গিয়েছে",
                "যেতে", "গেলে", "যাওয়া", "যাওয়ার"
            )
            "আস" -> listOf(
                "আসি", "এসো", "আসুন", "আসে", "আয়",
                "আসছি", "আসছো", "আসছেন", "আসছে",
                "এলাম", "এলে", "এলেন", "এলো", "এলি",
                "আসছিলাম", "আসছিলে", "আসছিলেন", "আসছিল",
                "আসবো", "আসবে", "আসবেন", "আসবি",
                "এসেছি", "এসেছো", "এসেছেন", "এসেছে",
                "আসতে", "আসলে", "আসা", "আসার"
            )
            "থাক" -> listOf(
                "থাকি", "থাকো", "থাকেন", "থাকে", "থাকিস",
                "থাকছি", "থাকছো", "থাকছেন", "থাকছে",
                "থাকলাম", "থাকলে", "থাকলেন", "থাকলো",
                "থাকছিলাম", "থাকছিলে", "থাকছিলেন", "থাকছিল",
                "থাকবো", "থাকবে", "থাকবেন", "থাকবি",
                "থেকেছি", "থেকেছো", "থেকেছেন", "থেকেছে",
                "থাকতে", "থাকলে", "থাকা", "থাকার"
            )
            "হ" -> listOf(
                "হই", "হও", "হন", "হয়", "হস",
                "হচ্ছি", "হচ্ছো", "হচ্ছেন", "হচ্ছে",
                "হলাম", "হলে", "হলেন", "হলো", "হলি",
                "হচ্ছিলাম", "হচ্ছিলে", "হচ্ছিলেন", "হচ্ছিল",
                "হবো", "হবে", "হবেন", "হবি",
                "হয়েছি", "হয়েছো", "হয়েছেন", "হয়েছে",
                "হতে", "হলে", "হওয়া", "হওয়ার"
            )
            else -> listOf(
                root + "ি", root + "ো", root + "েন", root + "ে",
                root + "ছি", root + "ছেন", root + "লাম", root + "লেন",
                root + "বো", root + "বে", root + "বেন", root + "তে", root + "লে"
            )
        }
    }
}
