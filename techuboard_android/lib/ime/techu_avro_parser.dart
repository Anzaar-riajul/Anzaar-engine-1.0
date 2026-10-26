/// TechuAvro Phonetic transliteration engine for Flutter.
/// Converts Romanized phonetic Bengali (Avro keyboard layout) into Bengali Unicode.
class TechuAvroUnicode {
  final Map<String, String> map = {};
  final Map<String, String> kars = {};
  final Map<String, String> jkt = {};
  final Map<String, String> djkt = {};
  final Map<String, String> djktt = {};

  TechuAvroUnicode() {
    map['o'] = '\u0985'; // অ
    map['O'] = '\u0993'; // ও
    map['a'] = '\u0986'; // আ
    map['A'] = '\u0986'; // আ
    map['S'] = '\u09B6'; // শ
    map['sh'] = '\u09B6'; // শ
    map['s'] = '\u09B8'; // স
    map['Sh'] = '\u09B7'; // ষ
    map['h'] = '\u09B9'; // হ
    map['H'] = '\u09B9'; // হ
    map['r'] = '\u09B0'; // র
    map['R'] = '\u09DC'; // ড়
    map['Rh'] = '\u09DD'; // ঢ়
    map['k'] = '\u0995'; // ক
    map['K'] = '\u0995'; // ক
    map['q'] = '\u0995';
    map['qq'] = '\u0981'; // ঁ
    map['kh'] = '\u0996'; // খ
    map['g'] = '\u0997'; // গ
    map['G'] = '\u0997'; // গ
    map['gh'] = '\u0998'; // ঘ
    map['Ng'] = '\u0999'; // ঙ
    map['c'] = '\u099A'; // চ
    map['C'] = '\u099A'; // চ
    map['ch'] = '\u099B'; // ছ
    map['j'] = '\u099C'; // জ
    map['jh'] = '\u099D'; // ঝ
    map['J'] = '\u099C';
    map['NG'] = '\u099E'; // ঞ
    map['T'] = '\u099F'; // ট
    map['Th'] = '\u09A0'; // ঠ
    map['TH'] = '\u09CE'; // ৎ
    map['f'] = '\u09AB'; // ফ
    map['F'] = '\u09AB'; // ফ
    map['ph'] = '\u09AB'; // ফ
    map['i'] = '\u0987'; // ই
    map['I'] = '\u0988'; // ঈ
    map['e'] = '\u098F'; // এ
    map['E'] = '\u098F'; // এ
    map['u'] = '\u0989'; // উ
    map['U'] = '\u098A'; // ঊ
    map['b'] = '\u09AC'; // ব
    map['B'] = '\u09AC'; // ব
    map['w'] = '\u09AC'; // ব
    map['bh'] = '\u09AD'; // ভ
    map['V'] = '\u09AD'; // ভ
    map['v'] = '\u09AD'; // ভ
    map['t'] = '\u09A4'; // ত
    map['th'] = '\u09A5'; // থ
    map['d'] = '\u09A6'; // দ
    map['dh'] = '\u09A7'; // ধ
    map['D'] = '\u09A1'; // ড
    map['Dh'] = '\u09A2'; // ঢ
    map['n'] = '\u09A8'; // ন
    map['N'] = '\u09A3'; // ণ
    map['z'] = '\u09AF'; // য
    map['Z'] = '\u09AF'; // য
    map['y'] = '\u09DF'; // য়
    map['l'] = '\u09B2'; // ল
    map['L'] = '\u09B2'; // ল
    map['m'] = '\u09AE'; // ম
    map['M'] = '\u09AE'; // ম
    map['P'] = '\u09AA'; // প
    map['p'] = '\u09AA'; // প
    map['ng'] = '\u0982'; // ং
    map['cb'] = '\u0981'; // ঁ
    map['x'] = '\u0995\u09CD\u09B8'; // ক্স
    map['OU'] = '\u0994'; // ঔ
    map['OI'] = '\u0990'; // ঐ
    map['hs'] = '\u09CD'; // ্
    map['nj'] = '\u099E\u09CD\u099C'; // ঞ্জ
    map['nc'] = '\u099E\u09CD\u099A'; // ঞ্চ

    kars['o'] = '';
    kars['a'] = '\u09BE'; // া
    kars['A'] = '\u09BE'; // া
    kars['e'] = '\u09C7'; // ে
    kars['E'] = '\u09C7'; // ে
    kars['O'] = '\u09CB'; // ো
    kars['OI'] = '\u09C8'; // ৈ
    kars['OU'] = '\u09CC'; // ৌ
    kars['i'] = '\u09BF'; // ি
    kars['I'] = '\u09C0'; // ী
    kars['u'] = '\u09C1'; // ু
    kars['U'] = '\u09C2'; // ূ
    kars['oo'] = '\u09C1'; // ু

    jkt['k'] = 'kTtnNslw';
    jkt['g'] = 'gnNmlw';
    jkt['ch'] = 'w';
    jkt['Ng'] = 'gkm';
    jkt['NG'] = 'cj';
    jkt['G'] = 'gnNmlw';
    jkt['th'] = 'w';
    jkt['gh'] = 'Nn';
    jkt['c'] = 'c';
    jkt['j'] = 'jw';
    jkt['T'] = 'T';
    jkt['D'] = 'D';
    jkt['R'] = 'g';
    jkt['N'] = 'DNmw';
    jkt['t'] = 'tnmwN';
    jkt['d'] = 'wdm';
    jkt['dh'] = 'wn';
    jkt['n'] = 'ndwmtsDT';
    jkt['p'] = 'plTtns';
    jkt['f'] = 'l';
    jkt['ph'] = 'l';
    jkt['b'] = 'jdbwl';
    jkt['v'] = 'l';
    jkt['bh'] = 'l';
    jkt['m'] = 'npfwvmlb';
    jkt['l'] = 'lwmpkgTDf';
    jkt['Sh'] = 'kTNpmf';
    jkt['S'] = 'clwnm';
    jkt['sh'] = 'clwnm';
    jkt['s'] = 'kTtnpfmlw';
    jkt['h'] = 'Nnmlw';
    jkt['cb'] = '';
    jkt['jh'] = '';
    jkt['TH'] = '';
    jkt['qq'] = '';
    jkt['ng'] = '';
    jkt['kh'] = '';
    jkt['gg'] = '';
    jkt['dh'] = '';
    jkt['Th'] = '';

    djkt['kh'] = 'Ngs';
    djkt['ch'] = 'c';
    djkt['Dh'] = 'N';
    djkt['ph'] = 'mls';
    djkt['dh'] = 'gdnbl';
    djkt['bh'] = 'dm';
    djkt['Sh'] = 'k';
    djkt['th'] = 'tns';
    djkt['Th'] = 'Nn';
    djkt['jh'] = 'j';
    djkt['NG'] = 'cj';

    djktt['ch'] = 'NG';
    djktt['gh'] = 'Ng';
    djktt['Th'] = 'Sh';
    djktt['jh'] = 'NG';
    djktt['sh'] = 'ch';
  }

  String? getDual(String x, String carry) => map['$carry$x'];
  String? get(String x) => map[x];
  String? getKar(String x) => kars[x];
  String? getDualKar(String x, String carry) => kars['$carry$x'];
  String? getJkt(String carry) => jkt[carry];
  String? getDualJkt(String sc, String carry) => jkt['$sc$carry'];
  String? getDjkt(String carry, String now) => djkt['$carry$now'];
  String? getDjktt(String carry, String now) => djktt['$carry$now'];
}

/// Phonetic Avro parser implementation
class TechuAvroParser {
  final TechuAvroUnicode unicode = TechuAvroUnicode();

  final Map<String, String> dictionary = const {
    'ami': 'আমি',
    'amar': 'আমার',
    'amra': 'আমরা',
    'amader': 'আমাদের',
    'apni': 'আপনি',
    'apnar': 'আপনার',
    'apnara': 'আপনারা',
    'apnader': 'আপনাদের',
    'tumi': 'তুমি',
    'tomar': 'তোমার',
    'tomra': 'তোমরা',
    'tomader': 'তোমাদের',
    'kemon': 'কেমন',
    'acho': 'আছো',
    'achen': 'আছেন',
    'achi': 'আছি',
    'achhi': 'আছি',
    'bangla': 'বাংলা',
    'bangladesh': 'বাংলাদেশ',
    'dhonnobad': 'ধন্যবাদ',
    'shonar': 'সোনার',
    'sonar': 'সোনার',
    'bhalobashi': 'ভালোবাসি',
    'valobashi': 'ভালোবাসি',
    'khub': 'খুব',
    'bhalo': 'ভালো',
    'valo': 'ভালো',
    'shob': 'সব',
    'sob': 'সব',
    'kichu': 'কিছু',
    'thik': 'ঠিক',
    'ache': 'আছে',
    'techuboard': 'টেকুবোর্ড',
    'techu': 'টেকু',
    'avro': 'অভ্র',
    'ki': 'কী',
    'keno': 'কেন',
    'kore': 'করে',
    'koro': 'করো',
    'korbo': 'করব',
    'korche': 'করছে',
    'bolte': 'বলতে',
    'bolo': 'বলো',
    'bolun': 'বলুন',
    'somoy': 'সময়',
    'din': 'দিন',
    'ajke': 'আজকে',
    'aaj': 'আজ',
    'kaal': 'কাল',
    'kal': 'কাল',
    'bondhu': 'বন্ধু',
    'bhai': 'ভাই',
    'vai': 'ভাই',
    'ekhon': 'এখন',
    'ar': 'আর',
    'aar': 'আর',
    'shathe': 'সাথে',
    'sathe': 'সাথে',
    'gan': 'গান',
    'gai': 'গাই',
    'hobe': 'হবে',
    'hoyeche': 'হয়েছে',
    'hoise': 'হইছে',
    'onek': 'অনেক',
    'sundor': 'সুন্দর',
    'shundor': 'সুন্দর',
    'dorkar': 'দরকার',
  };

  String toBangla(String engWord) {
    if (engWord.isEmpty) return '';

    final lower = engWord.toLowerCase();
    if (dictionary.containsKey(lower)) {
      return dictionary[lower]!;
    }

    final StringBuffer st = StringBuffer();
    String carry = '';
    String secondCarry = '';
    String thirdCarry = '';
    bool jukta = false;
    bool prevJukta = false;

    for (int i = 0; i < engWord.length; i++) {
      String now = engWord[i];

      final codeUnit = now.codeUnitAt(0);
      final isAlphaNum = (codeUnit >= 65 && codeUnit <= 90) ||
          (codeUnit >= 97 && codeUnit <= 122) ||
          (codeUnit >= 48 && codeUnit <= 57);

      if (!isAlphaNum) {
        st.write(now);
        carry = '';
        secondCarry = '';
        thirdCarry = '';
        jukta = false;
        prevJukta = false;
        continue;
      }

      if ('ABCEFPXKLMVYWQ'.contains(now)) {
        now = now.toLowerCase();
      }

      if (now == 'H' && carry != 'T') {
        now = 'h';
      }

      if ((carry.isEmpty || _isVowel(carry)) && now == 'w') {
        now = 'O';
      }

      if (_isVowel(now)) {
        if (carry == 'r' && secondCarry == 'r' && now == 'i') {
          if (thirdCarry.isEmpty) {
            _deleteTail(st, 2);
            st.write('\u098B'); // ঋ
          } else {
            _deleteTail(st, 3);
            st.write('\u09C3'); // ৃ
          }
          carry = 'i';
          continue;
        }

        final dual = secondCarry.isNotEmpty
            ? unicode.getDualKar(now, carry)
            : unicode.getDual(now, carry);

        if (dual != null) {
          if (carry != 'o') _deleteTail(st, 1);
          if (_isVowel(secondCarry)) {
            st.write(unicode.get(carry) ?? '');
            st.write(unicode.get(now) ?? '');
          } else {
            st.write(dual);
          }
        } else if (now == 'o' && carry.isNotEmpty) {
          if (_isVowel(carry)) {
            st.write(unicode.get('O') ?? '');
          } else {
            thirdCarry = secondCarry;
            secondCarry = carry;
            carry = now;
            continue;
          }
        } else if (_isVowel(carry) || carry.isEmpty) {
          if (now == 'a' && carry.isNotEmpty) {
            st.write(unicode.get('y') ?? '');
            st.write(unicode.getKar('a') ?? '');
          } else {
            st.write(unicode.get(now) ?? '');
          }
        } else {
          st.write(unicode.getKar(now) ?? '');
        }
      }

      if (now == 'y' || now == 'Z' || now == 'r') {
        jukta = false;
      }

      final tempNoCarry = jukta && (unicode.getDual(now, carry) == null);

      if (_isConsonant(now) && _isConsonant(carry) && !tempNoCarry) {
        if (now == 'y' || now == 'Z') {
          if (!(now == 'y' && carry == 'q' && secondCarry == 'q')) now = 'z';
        }

        if (carry == 'g' && now == 'g' && secondCarry != 'N' && secondCarry != 'n') {
          _deleteTail(st, 1);
          st.write('\u099C\u09CD\u099E'); // জ্ঞ
          prevJukta = jukta;
          jukta = true;
          secondCarry = 'g';
          continue;
        }

        if (secondCarry == 'k' && carry == 'k' && now == 'h') carry = 'S';

        final dual = unicode.getDual(now, carry);
        if (dual != null) {
          if (thirdCarry == 'g' && secondCarry == 'k' && carry == 'S' && now == 'h') {
            jukta = false;
            prevJukta = false;
          }

          final firstOrAfter = _isVowel(secondCarry) || secondCarry.isEmpty || prevJukta;

          if (_dualSitsUnder(thirdCarry, secondCarry, carry, now) && !firstOrAfter) {
            _deleteTail(st, 1);
            if (secondCarry == 'r' && thirdCarry == 'r') _deleteTail(st, 1);
            if (!jukta && secondCarry.isNotEmpty && !_isVowel(secondCarry)) {
              st.write('\u09CD');
            }
            st.write(dual);
            prevJukta = jukta;
            jukta = true;
          } else {
            if (jukta) {
              _deleteTail(st, 2);
            } else {
              _deleteTail(st, 1);
            }

            if (secondCarry == 'g' && carry == 'g' && now == 'h') {
              _deleteTail(st, 1);
              st.write(unicode.get('g') ?? '');
            }

            st.write(dual);
            prevJukta = jukta;
            jukta = false;
          }
        } else {
          prevJukta = jukta;
          jukta = false;

          if (secondCarry != 'r' && carry == 'r' && now == 'z') {
            st.write('\u200D\u09CD');
          } else if (carry == 'r' && secondCarry != 'r') {
            // no ref
          } else if (carry == 'r' && secondCarry == 'r' && _isConsonant(thirdCarry)) {
            // no ref
          } else if (carry == 'r' && secondCarry == 'r' && (_isVowel(thirdCarry) || thirdCarry.isEmpty)) {
            _deleteTail(st, 1);
            st.write('\u09CD');
          } else if (_notJukta(thirdCarry, secondCarry, carry, now)) {
            // no conjunct
          } else {
            st.write('\u09CD');
            jukta = true;
          }

          st.write(unicode.get(now) ?? '');
        }
      } else if (_isConsonant(now)) {
        if (_isVowel(carry) && now == 'Z') st.write('\u09CD');
        if (carry.isEmpty && now == 'x') st.write(unicode.get('e') ?? '');

        prevJukta = jukta;
        jukta = false;

        if (now == 'w' && _isConsonant(carry) && _isConsonant(secondCarry)) {
          st.write('\u09CD');
          prevJukta = jukta;
          jukta = true;
        }

        if (thirdCarry == 'k' && secondCarry == 'S' && carry == 'h' && (now == 'N' || now == 'm')) {
          st.write('\u09CD');
          prevJukta = false;
          jukta = true;
        }

        st.write(unicode.get(now) ?? '');
      }

      thirdCarry = secondCarry;
      secondCarry = carry;
      carry = now;
    }

    return sanitizeBangla(st.toString());
  }

  String sanitizeBangla(String input) {
    String s = input;
    // 1. Never allow hasanta after anusvara (ং), chandrabindu (ঁ), visarga (ঃ), khanda-ta (ৎ)
    s = s.replaceAll('\u0982\u09CD', '\u0982'); // ং্ -> ং
    s = s.replaceAll('\u0981\u09CD', '\u0981'); // ঁ্ -> ঁ
    s = s.replaceAll('\u0983\u09CD', '\u0983'); // ঃ্ -> ঃ
    s = s.replaceAll('\u09CE\u09CD', '\u09CE'); // ৎ্ -> ৎ

    // 2. Double hasanta cleanup
    s = s.replaceAll(RegExp(r'\u09CD+'), '\u09CD');

    // 3. Remove hasanta or ZWNJ before vowel signs (kars) so vowels never break
    s = s.replaceAll(RegExp(r'[\u09CD\u200C]+([\u09BE-\u09CC\u09D7])'), r'$1');

    // 4. Common specific ligature fixes
    s = s.replaceAll('বাং্লা', 'বাংলা');
    s = s.replaceAll('বাং्लादेश', 'বাংলাদেশ');

    return s;
  }

  bool _isVowel(String c) {
    if (c.isEmpty) return false;
    return 'AEIOUaeiou'.contains(c);
  }

  bool _isConsonant(String c) {
    if (c.isEmpty) return false;
    final code = c.codeUnitAt(0);
    final isLetter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    return isLetter && !_isVowel(c);
  }

  bool _dualSitsUnder(String thirdCarry, String secondCarry, String carry, String now) {
    if (secondCarry == 'r' && thirdCarry == 'r') return true;
    if (secondCarry == 'r') return false;

    final djkt = unicode.getDjkt(carry, now);
    if (djkt != null && secondCarry.isNotEmpty && djkt.contains(secondCarry)) return true;

    final djktt = unicode.getDjktt(carry, now);
    if (djktt != null && djktt.contains('$thirdCarry$secondCarry')) return true;

    return false;
  }

  bool _notJukta(String thirdCarry, String secondCarry, String carry, String now) {
    if (now == 'r' || now == 'z' || now == 'w') return false;

    final dualJkt = unicode.getDualJkt(secondCarry, carry);
    if (dualJkt != null) return !dualJkt.contains(now);

    final jkt = unicode.getJkt(carry);
    if (jkt != null) return !jkt.contains(now);

    return true;
  }

  void _deleteTail(StringBuffer sb, int count) {
    final str = sb.toString();
    if (str.length <= count) {
      sb.clear();
    } else {
      sb.clear();
      sb.write(str.substring(0, str.length - count));
    }
  }
}
