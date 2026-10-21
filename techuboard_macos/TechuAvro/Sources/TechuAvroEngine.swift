// TechuAvroEngine.swift
// Pure Swift Avro phonetic transliteration engine.
// Ported faithfully from the authentic Avro Phonetic JS engine.
// Zero dependencies, zero I/O, < 0.15 ms per call.

struct TechuAvroEngine {

    // MARK: - Unicode Mapping Table (consonants + vowels)
    private static let unicodeMap: [String: String] = [
        "o": "\u{0985}", "O": "\u{0993}", "a": "\u{0986}", "A": "\u{0986}",
        "S": "\u{09B6}", "sh": "\u{09B6}", "s": "\u{09B8}", "Sh": "\u{09B7}",
        "h": "\u{09B9}", "H": "\u{09B9}", "r": "\u{09B0}", "R": "\u{09DC}", "Rh": "\u{09DD}",
        "k": "\u{0995}", "K": "\u{0995}", "q": "\u{0995}", "qq": "\u{0981}", "kh": "\u{0996}",
        "g": "\u{0997}", "G": "\u{0997}", "gh": "\u{0998}", "Ng": "\u{0999}", "c": "\u{099A}",
        "C": "\u{099A}", "ch": "\u{099B}", "j": "\u{099C}", "jh": "\u{099D}", "J": "\u{099C}",
        "NG": "\u{099E}", "T": "\u{099F}", "Th": "\u{09A0}", "TH": "\u{09CE}", "f": "\u{09AB}",
        "F": "\u{09AB}", "ph": "\u{09AB}", "i": "\u{0987}", "I": "\u{0988}", "e": "\u{098F}",
        "E": "\u{098F}", "u": "\u{0989}", "U": "\u{098A}", "b": "\u{09AC}", "B": "\u{09AC}",
        "w": "\u{09AC}", "bh": "\u{09AD}", "V": "\u{09AD}", "v": "\u{09AD}", "t": "\u{09A4}",
        "th": "\u{09A5}", "d": "\u{09A6}", "dh": "\u{09A7}", "D": "\u{09A1}", "Dh": "\u{09A2}",
        "n": "\u{09A8}", "N": "\u{09A3}", "z": "\u{09AF}", "Z": "\u{09AF}", "y": "\u{09DF}",
        "l": "\u{09B2}", "L": "\u{09B2}", "m": "\u{09AE}", "M": "\u{09AE}", "P": "\u{09AA}",
        "p": "\u{09AA}", "ng": "\u{0982}", "cb": "\u{0981}", "x": "\u{0995}\u{09CD}\u{09B8}",
        "OU": "\u{0994}", "OI": "\u{0990}", "hs": "\u{09CD}",
        "nj": "\u{099E}\u{09CD}\u{099C}", "nc": "\u{099E}\u{09CD}\u{099A}"
    ]

    // MARK: - Vowel Kar (Matra) Table
    private static let karsMap: [String: String] = [
        "o": "", "a": "\u{09BE}", "A": "\u{09BE}", "e": "\u{09C7}", "E": "\u{09C7}",
        "O": "\u{09CB}", "OI": "\u{09C8}", "OU": "\u{09CC}", "i": "\u{09BF}",
        "I": "\u{09C0}", "u": "\u{09C1}", "U": "\u{09C2}", "oo": "\u{09C1}"
    ]

    // MARK: - Juktoborno (Conjunct) Compatibility Table
    private static let jktMap: [String: String] = [
        "k": "kTtnNslw", "g": "gnNmlw", "ch": "w", "Ng": "gkm", "NG": "cj",
        "G": "gnNmlw", "th": "w", "gh": "Nn", "c": "c", "j": "jw", "T": "T",
        "D": "D", "R": "g", "N": "DNmw", "t": "tnmwN", "d": "wdm", "dh": "wn",
        "n": "ndwmtsDT", "p": "plTtns", "f": "l", "ph": "l", "b": "jdbwl",
        "v": "l", "bh": "l", "m": "npfwvmlb", "l": "lwmpkgTDf", "Sh": "kTNpmf",
        "S": "clwnm", "sh": "clwnm", "s": "kTtnpfmlw", "h": "Nnmlw", "cb": "",
        "jh": "", "TH": "", "qq": "", "ng": "", "kh": "", "gg": "", "Th": ""
    ]

    // MARK: - Double Juktoborno Table
    private static let djktMap: [String: String] = [
        "kh": "Ngs", "ch": "c", "Dh": "N", "ph": "mls", "dh": "gdnbl",
        "bh": "dm", "Sh": "k", "th": "tns", "Th": "Nn", "jh": "j", "NG": "cj"
    ]

    private static let djkttMap: [String: String] = [
        "ch": "NG", "gh": "Ng", "Th": "Sh", "jh": "NG", "sh": "ch"
    ]

    // MARK: - Helpers
    private static func isVowel(_ c: Character) -> Bool {
        return "AEIOUaeiou".contains(c)
    }

    private static func isConsonant(_ c: Character) -> Bool {
        return c.isLetter && !isVowel(c)
    }

    private static func isVowelStr(_ s: String) -> Bool {
        guard let c = s.first, s.count == 1 else { return false }
        return isVowel(c)
    }

    private static func isConsonantStr(_ s: String) -> Bool {
        guard let c = s.first, s.count == 1 else { return false }
        return isConsonant(c)
    }

    // MARK: - Main Parse Function
    /// Transliterate an English phonetic string to Bangla Unicode.
    /// - Parameter engWord: The raw phonetic input (e.g. "ami")
    /// - Returns: Bangla Unicode string (e.g. "আমি")
    static func parse(_ engWord: String) -> String {
        guard !engWord.isEmpty else { return "" }

        var st: [String] = []
        var carry = "", secondCarry = "", thirdCarry = ""
        var jukta = false, prevJukta = false

        let chars = Array(engWord)
        var i = 0
        while i < chars.count {
            let nowChar = chars[i]
            var now = String(nowChar)

            // Non-alpha passthrough
            if !now.first!.isLetter && !now.first!.isNumber {
                st.append(now)
                carry = ""; secondCarry = ""; thirdCarry = ""
                jukta = false; prevJukta = false
                i += 1
                continue
            }

            // Normalize capitals that map directly
            if "ABCEFPXKLMVYWQ".contains(now) { now = now.lowercased() }
            if now == "H" && carry != "T" { now = "h" }
            if (carry.isEmpty || isVowelStr(carry)) && now == "w" { now = "O" }

            // --- Vowel handling ---
            if let c = now.first, isVowel(c) {
                // rri special case
                if carry == "r" && secondCarry == "r" && now == "i" {
                    if thirdCarry.isEmpty {
                        let removeCount = min(2, st.count)
                        st.removeLast(removeCount)
                        st.append("\u{098B}")
                    } else {
                        let removeCount = min(3, st.count)
                        st.removeLast(removeCount)
                        st.append("\u{09C3}")
                    }
                    carry = "i"
                    i += 1
                    continue
                }

                let dualKey = carry + now
                if !secondCarry.isEmpty {
                    if let dual = karsMap[dualKey] {
                        if carry != "o" && !st.isEmpty { st.removeLast(1) }
                        if isVowelStr(secondCarry) {
                            st.append(unicodeMap[carry] ?? "")
                            st.append(unicodeMap[now] ?? "")
                        } else {
                            st.append(dual)
                        }
                    } else if now == "o" && !carry.isEmpty {
                        if isVowelStr(carry) {
                            st.append(unicodeMap["O"] ?? "")
                        } else {
                            thirdCarry = secondCarry
                            secondCarry = carry
                            carry = now
                            i += 1
                            continue
                        }
                    } else if isVowelStr(carry) || carry.isEmpty {
                        if now == "a" && !carry.isEmpty {
                            st.append(unicodeMap["y"] ?? "")
                            st.append(karsMap["a"] ?? "")
                        } else {
                            st.append(unicodeMap[now] ?? "")
                        }
                    } else {
                        st.append(karsMap[now] ?? "")
                    }
                } else if let dual = unicodeMap[dualKey] {
                    if carry != "o" && !st.isEmpty { st.removeLast(1) }
                    if isVowelStr(secondCarry) {
                        st.append(unicodeMap[carry] ?? "")
                        st.append(unicodeMap[now] ?? "")
                    } else {
                        st.append(dual)
                    }
                } else if now == "o" && !carry.isEmpty {
                    if isVowelStr(carry) {
                        st.append(unicodeMap["O"] ?? "")
                    } else {
                        thirdCarry = secondCarry
                        secondCarry = carry
                        carry = now
                        i += 1
                        continue
                    }
                } else if isVowelStr(carry) || carry.isEmpty {
                    if now == "a" && !carry.isEmpty {
                        st.append(unicodeMap["y"] ?? "")
                        st.append(karsMap["a"] ?? "")
                    } else {
                        st.append(unicodeMap[now] ?? "")
                    }
                } else {
                    st.append(karsMap[now] ?? "")
                }
            }

            if now == "y" || now == "Z" || now == "r" { jukta = false }
            let tempNoCarry = jukta && (unicodeMap[carry + now] == nil)

            // --- Consonant + Consonant (juktoborno) ---
            if let c = now.first, isConsonant(c),
               let cc = carry.first, isConsonant(cc), !tempNoCarry {

                if now == "y" || now == "Z" {
                    if !(now == "y" && carry == "q" && secondCarry == "q") { now = "z" }
                }

                // gg → জ্ঞ
                if carry == "g" && now == "g" && secondCarry != "N" && secondCarry != "n" {
                    if !st.isEmpty { st.removeLast(1) }
                    st.append("\u{099C}\u{09CD}\u{099E}")
                    prevJukta = jukta; jukta = true
                    secondCarry = "g"
                    i += 1
                    continue
                }

                // kkh → ক্ষ
                if secondCarry == "k" && carry == "k" && now == "h" { carry = "S" }

                let dualKey = carry + now
                if let dual = unicodeMap[dualKey] {
                    if thirdCarry == "g" && secondCarry == "k" && carry == "S" && now == "h" {
                        jukta = false; prevJukta = false
                    }
                    let firstOrAfter = isVowelStr(secondCarry) || secondCarry.isEmpty || prevJukta
                    let djkt = djktMap[dualKey]
                    let djktt = djkttMap[dualKey]
                    var sitsUnder = false

                    if secondCarry == "r" && thirdCarry == "r" {
                        sitsUnder = true
                    } else if secondCarry != "r" {
                        if let dj = djkt, !secondCarry.isEmpty, dj.contains(secondCarry) {
                            sitsUnder = true
                        } else if let djtt = djktt, !thirdCarry.isEmpty, !secondCarry.isEmpty,
                                  djtt.contains(thirdCarry + secondCarry) {
                            sitsUnder = true
                        }
                    }

                    if sitsUnder && !firstOrAfter {
                        if !st.isEmpty { st.removeLast(1) }
                        if secondCarry == "r" && thirdCarry == "r" && !st.isEmpty { st.removeLast(1) }
                        if !jukta && !secondCarry.isEmpty && !isVowelStr(secondCarry) {
                            st.append("\u{09CD}")
                        }
                        st.append(dual)
                        prevJukta = jukta; jukta = true
                    } else {
                        if jukta {
                            let removeCount = min(2, st.count)
                            st.removeLast(removeCount)
                        } else if !st.isEmpty {
                            st.removeLast(1)
                        }
                        if carry == "g" && secondCarry == "g" && now == "h" {
                            if !st.isEmpty { st.removeLast(1) }
                            st.append(unicodeMap["g"] ?? "")
                        }
                        st.append(dual)
                        prevJukta = jukta; jukta = false
                    }
                } else {
                    prevJukta = jukta; jukta = false

                    if secondCarry != "r" && carry == "r" && now == "z" {
                        st.append("\u{200D}\u{09CD}")
                    } else if carry == "r" && secondCarry != "r" {
                        // ref above — no additional push
                    } else if carry == "r" && secondCarry == "r" && isConsonantStr(thirdCarry) {
                        // no ref
                    } else if carry == "r" && secondCarry == "r" && (isVowelStr(thirdCarry) || thirdCarry.isEmpty) {
                        if !st.isEmpty { st.removeLast(1) }
                        st.append("\u{09CD}")
                    } else {
                        var notJuk = false
                        if now != "r" && now != "z" && now != "w" {
                            let dualJktKey = secondCarry + carry
                            if let dj = jktMap[dualJktKey] {
                                if !dj.contains(now) { notJuk = true }
                            } else if let jkt = jktMap[carry] {
                                if !jkt.contains(now) { notJuk = true }
                            }
                        }
                        if !notJuk {
                            st.append("\u{09CD}")
                            jukta = true
                        }
                    }
                    st.append(unicodeMap[now] ?? "")
                }

            } else if let c = now.first, isConsonant(c) {
                // Consonant after vowel or start
                if isVowelStr(carry) && now == "Z" { st.append("\u{09CD}") }
                if carry.isEmpty && now == "x" { st.append(unicodeMap["e"] ?? "") }
                prevJukta = jukta; jukta = false
                if now == "w" && isConsonantStr(carry) && isConsonantStr(secondCarry) {
                    st.append("\u{09CD}")
                    prevJukta = jukta; jukta = true
                }
                if thirdCarry == "k" && secondCarry == "S" && carry == "h" && (now == "N" || now == "m") {
                    st.append("\u{09CD}")
                    prevJukta = false; jukta = true
                }
                st.append(unicodeMap[now] ?? "")
            }

            thirdCarry = secondCarry
            secondCarry = carry
            carry = now
            i += 1
        }

        return st.joined()
    }

    // MARK: - Candidate Generation
    /// Generate up to `maxCount` word candidates for the given composing buffer.
    /// The first candidate is always the direct Avro parse.
    /// Additional candidates come from common suffix variations.
    static func candidates(for buffer: String, maxCount: Int = 9) -> [String] {
        guard !buffer.isEmpty else { return [] }

        let primary = parse(buffer)
        var results: [String] = [primary]

        // Common suffix alternatives that produce valid Bangla words
        let suffixAlternates: [(suffix: String, replacement: String)] = [
            ("a", "aa"), ("i", "ee"), ("u", "oo"),
            ("o", "ou"), ("e", "oi"), ("n", "ng"),
            ("k", "kh"), ("g", "gh"), ("t", "th"),
            ("d", "dh"), ("p", "ph"), ("b", "bh"),
            ("s", "sh"), ("S", "Sh")
        ]

        for alt in suffixAlternates {
            if buffer.hasSuffix(alt.suffix) && buffer.count > alt.suffix.count {
                let altBuffer = String(buffer.dropLast(alt.suffix.count)) + alt.replacement
                let altParsed = parse(altBuffer)
                if altParsed != primary && !results.contains(altParsed) {
                    results.append(altParsed)
                }
            }
            if results.count >= maxCount { break }
        }

        // Also try capital first letter variants
        if let first = buffer.first, first.isLowercase {
            let capBuffer = first.uppercased() + buffer.dropFirst()
            let capParsed = parse(capBuffer)
            if capParsed != primary && !results.contains(capParsed) {
                results.append(capParsed)
            }
        }

        return Array(results.prefix(maxCount))
    }
}
