// Copyright (c) Techuboard Authors.
// Apache License 2.0 / MIT.
// TechuAvro Phonetic Parsing Engine (English -> Bengali Phonetic Transliteration)

class TechuAvroUnicode {
  final Map<String, String> map = {};
  final Map<String, String> kars = {};
  final Map<String, String> jkt = {};
  final Map<String, String> djkt = {};
  final Map<String, String> djktt = {};

  TechuAvroUnicode() {
    map['o'] = '\u0985'; // অ (shore o)
    map['O'] = '\u0993'; // ও (rossho o)
    map['a'] = '\u0986'; // আ (aa)
    map['A'] = '\u0986'; // আ (aa)
    map['S'] = '\u09B6'; // শ (talobbo sho)
    map['sh'] = '\u09B6'; // শ (talobbo sho)
    map['s'] = '\u09B8'; // স (donto sho)
    map['Sh'] = '\u09B7'; // ষ (murdonno sho)
    map['h'] = '\u09B9'; // হ (ho)
    map['H'] = '\u09B9'; // হ (ho)
    map['r'] = '\u09B0'; // র (ro)
    map['R'] = '\u09DC'; // ড় (dhoye shunne ro)
    map['Rh'] = '\u09DD'; // ঢ় (dhoye shunne ro)
    map['k'] = '\u0995'; // ক (ko)
    map['K'] = '\u0995'; // ক (ko)
    map['q'] = '\u0995'; // ক
    map['qq'] = '\u0981'; // ঁ (chondro bindu)
    map['kh'] = '\u0996'; // খ (kho)
    map['g'] = '\u0997'; // গ (go)
    map['G'] = '\u0997'; // গ (go)
    map['gh'] = '\u0998'; // ঘ (gho)
    map['Ng'] = '\u0999'; // ঙ (unga)
    map['c'] = '\u099A'; // চ (cho)
    map['C'] = '\u099A'; // চ (cho)
    map['ch'] = '\u099B'; // ছ (ccho)
    map['j'] = '\u099C'; // জ (jo)
    map['jh'] = '\u099D'; // ঝ (jho)
    map['J'] = '\u099C'; // জ
    map['NG'] = '\u099E'; // ঞ (niyo)
    map['T'] = '\u099F'; // ট (To)
    map['Th'] = '\u09A0'; // ঠ (Tho)
    map['TH'] = '\u09CE'; // ৎ (khondiyo to)
    map['f'] = '\u09AB'; // ফ (fo)
    map['F'] = '\u09AB'; // ফ (fo)
    map['ph'] = '\u09AB'; // ফ (fo)
    map['i'] = '\u0987'; // ই (rossho i)
    map['I'] = '\u0988'; // ঈ (dhirgo i)
    map['e'] = '\u098F'; // এ (e)
    map['E'] = '\u098F'; // এ (e)
    map['u'] = '\u0989'; // উ (rossho u)
    map['U'] = '\u098A'; // ঊ (dhirgo u)
    map['b'] = '\u09AC'; // ব (bo)
    map['B'] = '\u09AC'; // ব (bo)
    map['w'] = '\u09AC'; // ব (bo)
    map['bh'] = '\u09AD'; // ভ (bho)
    map['V'] = '\u09AD'; // ভ (bho)
    map['v'] = '\u09AD'; // ভ (bho)
    map['t'] = '\u09A4'; // ত (to)
    map['th'] = '\u09A5'; // থ (tho)
    map['d'] = '\u09A6'; // দ (do)
    map['dh'] = '\u09A7'; // ধ (dho)
    map['D'] = '\u09A1'; // ড (do)
    map['Dh'] = '\u09A2'; // ঢ (dho)
    map['n'] = '\u09A8'; // ন (donto no)
    map['N'] = '\u09A3'; // ণ (murdo no)
    map['z'] = '\u09AF'; // য (zho)
    map['Z'] = '\u09AF'; // য (zho fola)
    map['y'] = '\u09DF'; // য় (ontosto yo)
    map['l'] = '\u09B2'; // ল (lo)
    map['L'] = '\u09B2'; // ল (lo)
    map['m'] = '\u09AE'; // ম (mo)
    map['M'] = '\u09AE'; // ম (mo)
    map['P'] = '\u09AA'; // প (po)
    map['p'] = '\u09AA'; // প (po)
    map['ng'] = '\u0982'; // ং (onushar)
    map['cb'] = '\u0981'; // ঁ (chondro point)
    map['x'] = '\u0995\u09CD\u09B8'; // ক্স
    map['OU'] = '\u0994'; // ঔ
    map['OI'] = '\u0990'; // ঐ
    map['hs'] = '\u09CD'; // ্
    map['nj'] = '\u099E\u09CD\u099C'; // ঞ্জ
    map['nc'] = '\u099E\u09CD\u099A'; // ঞ্চ

    kars['o'] = ''; // o kar (implicit)
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

    // each of 2nd sits under 1st
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

    // first sits under each of 2nd
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

    // first sits under 2nd(dual)
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
  String? getDualJkt(String secondCarry, String carry) => jkt['$secondCarry$carry'];
  String? getDjkt(String carry, String now) => djkt['$carry$now'];
  String? getDjktt(String carry, String now) => djktt['$carry$now'];
}

/// TechuAvro Phonetic transliteration engine.
class TechuAvroParser {
  final TechuAvroUnicode unicode = TechuAvroUnicode();

  /// Common phonetic word dictionary overrides for instant natural typing
  static const Map<String, String> _dictionary = {
    'ami': 'আমি',
    'amar': 'আমার',
    'amra': 'আমরা',
    'amader': 'আমাদের',
    'apni': 'আপনি',
    'apnar': 'আপনার',
    'apnara': 'আপনারা',
    'tumi': 'তুমি',
    'tomar': 'তোমার',
    'tomra': 'তোমরা',
    'kemon': 'কেমন',
    'acho': 'আছো',
    'achen': 'আছেন',
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
  };

  /// Transliterate a single word or full sentence.
  String parse(String input) {
    if (input.isEmpty) return '';
    final words = input.split(' ');
    final parsed = words.map((w) => toBangla(w));
    return parsed.join(' ');
  }

  /// Converts an English phonetic word (e.g. "bangla", "uddhot")
  /// into Bengali Unicode text following Avro phonetic layout rules.
  String toBangla(String engWord) {
    if (engWord.isEmpty) return '';

    final lower = engWord.toLowerCase();
    if (_dictionary.containsKey(lower)) {
      return _dictionary[lower]!;
    }

    final StringBuffer st = StringBuffer();
    String carry = '';
    String secondCarry = '';
    String thirdCarry = '';
    bool jukta = false;
    bool prevJukta = false;

    for (int i = 0; i < engWord.length; i++) {
      String now = engWord[i];

      final code = now.codeUnitAt(0);
      final isLetter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
      final isDigit = (code >= 48 && code <= 57);

      if (!isLetter && !isDigit) {
        st.write(now);
        carry = '';
        secondCarry = '';
        thirdCarry = '';
        jukta = false;
        prevJukta = false;
        continue;
      }

      if ('ABCEFPXK LMVYWQ'.contains(now)) {
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

        String? dual;
        if (secondCarry.isNotEmpty) {
          dual = unicode.getDualKar(now, carry);
        } else {
          dual = unicode.getDual(now, carry);
        }

        if (dual != null) {
          if (carry != 'o') {
            _deleteTail(st, 1);
          }
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

      final bool tempNoCarry = jukta && (unicode.getDual(now, carry) == null);

      if (_isConsonant(now) && _isConsonant(carry) && !tempNoCarry) {
        if (now == 'y' || now == 'Z') {
          if (now == 'y' && carry == 'q' && secondCarry == 'q') {
            // keep
          } else {
            now = 'z';
          }
        }

        if (carry == 'g' && now == 'g' && secondCarry != 'N' && secondCarry != 'n') {
          _deleteTail(st, 1);
          st.write('\u099C\u09CD\u099E'); // জ্ঞ
          prevJukta = jukta;
          jukta = true;
          secondCarry = 'g';
          continue;
        }

        if (secondCarry == 'k' && carry == 'k' && now == 'h') {
          carry = 'S';
        }

        final String? dual = unicode.getDual(now, carry);
        if (dual != null) {
          if (thirdCarry == 'g' && secondCarry == 'k' && carry == 'S' && now == 'h') {
            jukta = false;
            prevJukta = false;
          }

          final bool firstOrAfter = _isVowel(secondCarry) || secondCarry.isEmpty || prevJukta;

          if (_dualSitsUnder(thirdCarry, secondCarry, carry, now) && !firstOrAfter) {
            _deleteTail(st, 1);
            if (secondCarry == 'r' && thirdCarry == 'r') {
              _deleteTail(st, 1);
            }
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
            st.write('\u200D\u09CD'); // rya
          } else if (carry == 'r' && secondCarry != 'r') {
            // no ref
          } else if (carry == 'r' && secondCarry == 'r' && _isConsonant(thirdCarry)) {
            // no ref
          } else if (carry == 'r' && secondCarry == 'r' && (_isVowel(thirdCarry) || thirdCarry.isEmpty)) {
            _deleteTail(st, 1);
            st.write('\u09CD'); // ref
          } else if (_notJukta(thirdCarry, secondCarry, carry, now)) {
            // not a conjunct
          } else {
            st.write('\u09CD');
            jukta = true;
          }

          st.write(unicode.get(now) ?? '');
        }
      } else if (_isConsonant(now)) {
        if (_isVowel(carry) && now == 'Z') {
          st.write('\u09CD');
        }
        if (carry.isEmpty && now == 'x') {
          st.write(unicode.get('e') ?? '');
        }

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

    return st.toString();
  }

  bool _isVowel(String ch) {
    if (ch.isEmpty) return false;
    return 'AEIOUaeiou'.contains(ch);
  }

  bool _isConsonant(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    final isLetter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    return isLetter && !_isVowel(ch);
  }

  bool _dualSitsUnder(String thirdCarry, String secondCarry, String carry, String now) {
    if (secondCarry == 'r' && thirdCarry == 'r') return true;
    if (secondCarry == 'r') return false;

    final djkt = unicode.getDjkt(carry, now);
    if (djkt != null && secondCarry.isNotEmpty && djkt.contains(secondCarry)) {
      return true;
    }

    final djktt = unicode.getDjktt(carry, now);
    if (djktt != null && djktt.contains('$thirdCarry$secondCarry')) {
      return true;
    }

    return false;
  }

  bool _notJukta(String thirdCarry, String secondCarry, String carry, String now) {
    if (now == 'r' || now == 'z' || now == 'w') return false;

    final dualJkt = unicode.getDualJkt(secondCarry, carry);
    if (dualJkt != null) {
      return !dualJkt.contains(now);
    }

    final jkt = unicode.getJkt(carry);
    if (jkt != null) {
      return !jkt.contains(now);
    }

    return true;
  }

  void _deleteTail(StringBuffer sb, int count) {
    final str = sb.toString();
    if (str.length <= count) {
      sb.clear();
    } else {
      final sub = str.substring(0, str.length - count);
      sb.clear();
      sb.write(sub);
    }
  }
}
