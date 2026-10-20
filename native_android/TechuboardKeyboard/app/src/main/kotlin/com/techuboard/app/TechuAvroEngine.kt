package com.techuboard.app

/**
 * TechuAvro Phonetic transliteration engine in Kotlin.
 * Converts Romanized phonetic Bengali (Avro keyboard layout) into Bengali Unicode.
 */
class TechuAvroUnicode {
    val map = HashMap<String, String>()
    val kars = HashMap<String, String>()
    val jkt = HashMap<String, String>()
    val djkt = HashMap<String, String>()
    val djktt = HashMap<String, String>()

    init {
        map["o"] = "\u0985" // অ
        map["O"] = "\u0993" // ও
        map["a"] = "\u0986" // আ
        map["A"] = "\u0986" // আ
        map["S"] = "\u09B6" // শ
        map["sh"] = "\u09B6" // শ
        map["s"] = "\u09B8" // স
        map["Sh"] = "\u09B7" // ষ
        map["h"] = "\u09B9" // হ
        map["H"] = "\u09B9" // হ
        map["r"] = "\u09B0" // র
        map["R"] = "\u09DC" // ড়
        map["Rh"] = "\u09DD" // ঢ়
        map["k"] = "\u0995" // ক
        map["K"] = "\u0995" // ক
        map["q"] = "\u0995"
        map["qq"] = "\u0981" // ঁ
        map["kh"] = "\u0996" // খ
        map["g"] = "\u0997" // গ
        map["G"] = "\u0997" // গ
        map["gh"] = "\u0998" // ঘ
        map["Ng"] = "\u0999" // ঙ
        map["c"] = "\u099A" // চ
        map["C"] = "\u099A" // চ
        map["ch"] = "\u099B" // ছ
        map["j"] = "\u099C" // জ
        map["jh"] = "\u099D" // ঝ
        map["J"] = "\u099C"
        map["NG"] = "\u099E" // ঞ
        map["T"] = "\u099F" // ট
        map["Th"] = "\u09A0" // ঠ
        map["TH"] = "\u09CE" // ৎ
        map["f"] = "\u09AB" // ফ
        map["F"] = "\u09AB" // ফ
        map["ph"] = "\u09AB" // ফ
        map["i"] = "\u0987" // ই
        map["I"] = "\u0988" // ঈ
        map["e"] = "\u098F" // এ
        map["E"] = "\u098F" // এ
        map["u"] = "\u0989" // উ
        map["U"] = "\u098A" // ঊ
        map["b"] = "\u09AC" // ব
        map["B"] = "\u09AC" // ব
        map["w"] = "\u09AC" // ব
        map["bh"] = "\u09AD" // ভ
        map["V"] = "\u09AD" // ভ
        map["v"] = "\u09AD" // ভ
        map["t"] = "\u09A4" // ত
        map["th"] = "\u09A5" // থ
        map["d"] = "\u09A6" // দ
        map["dh"] = "\u09A7" // ধ
        map["D"] = "\u09A1" // ড
        map["Dh"] = "\u09A2" // ঢ
        map["n"] = "\u09A8" // ন
        map["N"] = "\u09A3" // ণ
        map["z"] = "\u09AF" // য
        map["Z"] = "\u09AF" // য (য-ফলা)
        map["y"] = "\u09DF" // য়
        map["l"] = "\u09B2" // ল
        map["L"] = "\u09B2" // ল
        map["m"] = "\u09AE" // ম
        map["M"] = "\u09AE" // ম
        map["P"] = "\u09AA" // প
        map["p"] = "\u09AA" // প
        map["ng"] = "\u0982" // ং
        map["cb"] = "\u0981" // ঁ
        map["x"] = "\u0995\u09CD\u09B8" // ক্স
        map["OU"] = "\u0994" // ঔ
        map["OI"] = "\u0990" // ঐ
        map["hs"] = "\u09CD" // ্
        map["nj"] = "\u099E\u09CD\u099C" // ঞ্জ
        map["nc"] = "\u099E\u09CD\u099A" // ঞ্চ

        kars["o"] = "" // o kar
        kars["a"] = "\u09BE" // া
        kars["A"] = "\u09BE" // া
        kars["e"] = "\u09C7" // ে
        kars["E"] = "\u09C7" // ে
        kars["O"] = "\u09CB" // ো
        kars["OI"] = "\u09C8" // ৈ
        kars["OU"] = "\u09CC" // ৌ
        kars["i"] = "\u09BF" // ি
        kars["I"] = "\u09C0" // ী
        kars["u"] = "\u09C1" // ু
        kars["U"] = "\u09C2" // ূ
        kars["oo"] = "\u09C1" // ু

        jkt["k"] = "kTtnNslw"
        jkt["g"] = "gnNmlw"
        jkt["ch"] = "w"
        jkt["Ng"] = "gkm"
        jkt["NG"] = "cj"
        jkt["G"] = "gnNmlw"
        jkt["th"] = "w"
        jkt["gh"] = "Nn"
        jkt["c"] = "c"
        jkt["j"] = "jw"
        jkt["T"] = "T"
        jkt["D"] = "D"
        jkt["R"] = "g"
        jkt["N"] = "DNmw"
        jkt["t"] = "tnmwN"
        jkt["d"] = "wdm"
        jkt["dh"] = "wn"
        jkt["n"] = "ndwmtsDT"
        jkt["p"] = "plTtns"
        jkt["f"] = "l"
        jkt["ph"] = "l"
        jkt["b"] = "jdbwl"
        jkt["v"] = "l"
        jkt["bh"] = "l"
        jkt["m"] = "npfwvmlb"
        jkt["l"] = "lwmpkgTDf"
        jkt["Sh"] = "kTNpmf"
        jkt["S"] = "clwnm"
        jkt["sh"] = "clwnm"
        jkt["s"] = "kTtnpfmlw"
        jkt["h"] = "Nnmlw"
        jkt["cb"] = ""
        jkt["jh"] = ""
        jkt["TH"] = ""
        jkt["qq"] = ""
        jkt["ng"] = ""
        jkt["kh"] = ""
        jkt["gg"] = ""
        jkt["dh"] = ""
        jkt["Th"] = ""

        djkt["kh"] = "Ngs"
        djkt["ch"] = "c"
        djkt["Dh"] = "N"
        djkt["ph"] = "mls"
        djkt["dh"] = "gdnbl"
        djkt["bh"] = "dm"
        djkt["Sh"] = "k"
        djkt["th"] = "tns"
        djkt["Th"] = "Nn"
        djkt["jh"] = "j"
        djkt["NG"] = "cj"

        djktt["ch"] = "NG"
        djktt["gh"] = "Ng"
        djktt["Th"] = "Sh"
        djktt["jh"] = "NG"
        djktt["sh"] = "ch"
    }

    fun getDual(x: Char, carry: Char): String? = map["$carry$x"]
    fun get(x: Char): String? = map[x.toString()]
    fun getKar(x: Char): String? = kars[x.toString()]
    fun getDualKar(x: Char, carry: Char): String? = kars["$carry$x"]
    fun getJkt(carry: Char): String? = jkt[carry.toString()]
    fun getDualJkt(sc: Char, carry: Char): String? = jkt["$sc$carry"]
    fun getDjkt(carry: Char, now: Char): String? = djkt["$carry$now"]
    fun getDjktt(carry: Char, now: Char): String? = djktt["$carry$now"]
}

class TechuAvroEngine {
    private val unicode = TechuAvroUnicode()

    private val dictionary = mapOf(
        "ami" to "আমি",
        "amar" to "আমার",
        "amra" to "আমরা",
        "amader" to "আমাদের",
        "apni" to "আপনি",
        "apnar" to "আপনার",
        "apnara" to "আপনারা",
        "apnader" to "আপনাদের",
        "tumi" to "তুমি",
        "tomar" to "তোমার",
        "tomra" to "তোমরা",
        "tomader" to "তোমাদের",
        "kemon" to "কেমন",
        "acho" to "আছো",
        "achen" to "আছেন",
        "achi" to "আছি",
        "achhi" to "আছি",
        "bangla" to "বাংলা",
        "bangladesh" to "বাংলাদেশ",
        "dhonnobad" to "ধন্যবাদ",
        "shonar" to "সোনার",
        "sonar" to "সোনার",
        "bhalobashi" to "ভালোবাসি",
        "valobashi" to "ভালোবাসি",
        "khub" to "খুব",
        "bhalo" to "ভালো",
        "valo" to "ভালো",
        "shob" to "সব",
        "sob" to "সব",
        "kichu" to "কিছু",
        "thik" to "ঠিক",
        "ache" to "আছে",
        "techuboard" to "টেকুবোর্ড",
        "techu" to "টেকু",
        "avro" to "অভ্র",
        "ki" to "কী",
        "keno" to "কেন",
        "kore" to "করে",
        "koro" to "করো",
        "korbo" to "করব",
        "korche" to "করছে",
        "bolte" to "বলতে",
        "bolo" to "বলো",
        "bolun" to "বলুন",
        "somoy" to "সময়",
        "din" to "দিন",
        "ajke" to "আজকে",
        "aaj" to "আজ",
        "kaal" to "কাল",
        "kal" to "কাল",
        "bondhu" to "বন্ধু",
        "bhai" to "ভাই",
        "vai" to "ভাই",
        "ekhon" to "এখন",
        "ar" to "আর",
        "aar" to "আর",
        "shathe" to "সাথে",
        "sathe" to "সাথে",
        "gan" to "গান",
        "gai" to "গাই",
        "hobe" to "হবে",
        "hoyeche" to "হয়েছে",
        "hoise" to "হইছে",
        "onek" to "অনেক",
        "sundor" to "সুন্দর",
        "shundor" to "সুন্দর",
        "dorkar" to "দরকার"
    )

    fun toBangla(engWord: String): String {
        if (engWord.isEmpty()) return ""

        val lower = engWord.lowercase()
        if (dictionary.containsKey(lower)) {
            return dictionary[lower]!!
        }

        val st = StringBuilder()
        var carry = '\u0000'
        var secondCarry = '\u0000'
        var thirdCarry = '\u0000'
        var jukta = false
        var prevJukta = false

        for (i in engWord.indices) {
            var now = engWord[i]

            if (!((now in 'a'..'z') || (now in 'A'..'Z') || (now in '0'..'9'))) {
                st.append(now)
                carry = '\u0000'
                secondCarry = '\u0000'
                thirdCarry = '\u0000'
                jukta = false
                prevJukta = false
                continue
            }

            if ("ABCEFPXKLMVYWQ".contains(now)) {
                now = now.lowercaseChar()
            }

            if (now == 'H' && carry != 'T') {
                now = 'h'
            }

            if ((carry == '\u0000' || isVowel(carry)) && now == 'w') {
                now = 'O'
            }

            if (isVowel(now)) {
                if (carry == 'r' && secondCarry == 'r' && now == 'i') {
                    if (thirdCarry == '\u0000') {
                        deleteTail(st, 2)
                        st.append("\u098B") // ঋ
                    } else {
                        deleteTail(st, 3)
                        st.append("\u09C3") // ৃ
                    }
                    carry = 'i'
                    continue
                }

                val dual = if (secondCarry != '\u0000') unicode.getDualKar(now, carry) else unicode.getDual(now, carry)

                if (dual != null) {
                    if (carry != 'o') deleteTail(st, 1)
                    if (isVowel(secondCarry)) {
                        st.append(unicode.get(carry) ?: "")
                        st.append(unicode.get(now) ?: "")
                    } else {
                        st.append(dual)
                    }
                } else if (now == 'o' && carry != '\u0000') {
                    if (isVowel(carry)) {
                        st.append(unicode.get('O') ?: "")
                    } else {
                        thirdCarry = secondCarry
                        secondCarry = carry
                        carry = now
                        continue
                    }
                } else if (isVowel(carry) || carry == '\u0000') {
                    if (now == 'a' && carry != '\u0000') {
                        st.append(unicode.get('y') ?: "")
                        st.append(unicode.getKar('a') ?: "")
                    } else {
                        st.append(unicode.get(now) ?: "")
                    }
                } else {
                    st.append(unicode.getKar(now) ?: "")
                }
            }

            if (now == 'y' || now == 'Z' || now == 'r') {
                jukta = false
            }

            val tempNoCarry = jukta && (unicode.getDual(now, carry) == null)

            if (isConsonant(now) && isConsonant(carry) && !tempNoCarry) {
                if (now == 'y' || now == 'Z') {
                    if (!(now == 'y' && carry == 'q' && secondCarry == 'q')) now = 'z'
                }

                if (carry == 'g' && now == 'g' && secondCarry != 'N' && secondCarry != 'n') {
                    deleteTail(st, 1)
                    st.append("\u099C\u09CD\u099E") // জ্ঞ
                    prevJukta = jukta
                    jukta = true
                    secondCarry = 'g'
                    continue
                }

                if (secondCarry == 'k' && carry == 'k' && now == 'h') carry = 'S'

                val dual = unicode.getDual(now, carry)
                if (dual != null) {
                    if (thirdCarry == 'g' && secondCarry == 'k' && carry == 'S' && now == 'h') {
                        jukta = false
                        prevJukta = false
                    }

                    val firstOrAfter = isVowel(secondCarry) || secondCarry == '\u0000' || prevJukta

                    if (dualSitsUnder(thirdCarry, secondCarry, carry, now) && !firstOrAfter) {
                        deleteTail(st, 1)
                        if (secondCarry == 'r' && thirdCarry == 'r') deleteTail(st, 1)
                        if (!jukta && secondCarry != '\u0000' && !isVowel(secondCarry)) {
                            st.append("\u09CD")
                        }
                        st.append(dual)
                        prevJukta = jukta
                        jukta = true
                    } else {
                        if (jukta) deleteTail(st, 2)
                        else deleteTail(st, 1)

                        if (secondCarry == 'g' && carry == 'g' && now == 'h') {
                            deleteTail(st, 1)
                            st.append(unicode.get('g') ?: "")
                        }

                        st.append(dual)
                        prevJukta = jukta
                        jukta = false
                    }
                } else {
                    prevJukta = jukta
                    jukta = false

                    if (secondCarry != 'r' && carry == 'r' && now == 'z') {
                        st.append("\u200D\u09CD")
                    } else if (carry == 'r' && secondCarry != 'r') {
                        // no ref
                    } else if (carry == 'r' && secondCarry == 'r' && isConsonant(thirdCarry)) {
                        // no ref
                    } else if (carry == 'r' && secondCarry == 'r' && (isVowel(thirdCarry) || thirdCarry == '\u0000')) {
                        deleteTail(st, 1)
                        st.append("\u09CD")
                    } else if (notJukta(thirdCarry, secondCarry, carry, now)) {
                        // no conjunct
                    } else {
                        st.append("\u09CD")
                        jukta = true
                    }

                    st.append(unicode.get(now) ?: "")
                }
            } else if (isConsonant(now)) {
                if (isVowel(carry) && now == 'Z') st.append("\u09CD")
                if (carry == '\u0000' && now == 'x') st.append(unicode.get('e') ?: "")

                prevJukta = jukta
                jukta = false

                if (now == 'w' && isConsonant(carry) && isConsonant(secondCarry)) {
                    st.append("\u09CD")
                    prevJukta = jukta
                    jukta = true
                }

                if (thirdCarry == 'k' && secondCarry == 'S' && carry == 'h' && (now == 'N' || now == 'm')) {
                    st.append("\u09CD")
                    prevJukta = false
                    jukta = true
                }

                st.append(unicode.get(now) ?: "")
            }

            thirdCarry = secondCarry
            secondCarry = carry
            carry = now
        }

        return sanitizeBangla(st.toString())
    }

    fun sanitizeBangla(input: String): String {
        var s = input
        // 1. Never allow hasanta after anusvara (ং), chandrabindu (ঁ), visarga (ঃ), khanda-ta (ৎ)
        s = s.replace("\u0982\u09CD", "\u0982") // ং্ -> ং
        s = s.replace("\u0981\u09CD", "\u0981") // ঁ্ -> ঁ
        s = s.replace("\u0983\u09CD", "\u0983") // ঃ্ -> ঃ
        s = s.replace("\u09CE\u09CD", "\u09CE") // ৎ্ -> ৎ

        // 2. Double hasanta cleanup
        s = s.replace(Regex("\u09CD+"), "\u09CD")

        // 3. Remove hasanta or ZWNJ before vowel signs (kars) so vowels never break
        s = s.replace(Regex("[\u09CD\u200C]+([\u09BE-\u09CC\u09D7])"), "$1")

        // 4. Common specific ligature fixes
        s = s.replace("বাং্লা", "বাংলা")
        s = s.replace("বাং्लादेश", "বাংলাদেশ")

        return s
    }

    private fun isVowel(c: Char): Boolean = "AEIOUaeiou".contains(c)
    private fun isConsonant(c: Char): Boolean = c.isLetter() && !isVowel(c)

    private fun dualSitsUnder(thirdCarry: Char, secondCarry: Char, carry: Char, now: Char): Boolean {
        if (secondCarry == 'r' && thirdCarry == 'r') return true
        if (secondCarry == 'r') return false

        val djkt = unicode.getDjkt(carry, now)
        if (djkt != null && secondCarry != '\u0000' && djkt.contains(secondCarry)) return true

        val djktt = unicode.getDjktt(carry, now)
        if (djktt != null && djktt.contains("$thirdCarry$secondCarry")) return true

        return false
    }

    private fun notJukta(thirdCarry: Char, secondCarry: Char, carry: Char, now: Char): Boolean {
        if (now == 'r' || now == 'z' || now == 'w') return false

        val dualJkt = unicode.getDualJkt(secondCarry, carry)
        if (dualJkt != null) return !dualJkt.contains(now)

        val jkt = unicode.getJkt(carry)
        if (jkt != null) return !jkt.contains(now)

        return true
    }

    private fun deleteTail(sb: StringBuilder, count: Int) {
        if (sb.length <= count) {
            sb.setLength(0)
        } else {
            sb.setLength(sb.length - count)
        }
    }
}
