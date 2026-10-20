import 'package:flutter_test/flutter_test.dart';
import 'package:techuboard_android/ime/techu_avro_parser.dart';

void main() {
  group('TechuAvroParser Tests', () {
    final parser = TechuAvroParser();

    test('Standard phonetic sentences', () {
      expect(parser.toBangla('ami'), 'আমি');
      expect(parser.toBangla('bangla'), 'বাংলা');
      expect(parser.toBangla('amar'), 'আমার');
      expect(parser.toBangla('sonar'), 'সোনার');
      expect(parser.toBangla('kemon'), 'কেমন');
      expect(parser.toBangla('acho'), 'আছো');
      expect(parser.toBangla('dhonnobad'), 'ধন্যবাদ');
      expect(parser.toBangla('techuboard'), 'টেকুবোর্ড');
    });

    test('ParserTest parity test cases', () {
      expect(parser.toBangla('uddhot'), 'উদ্ধত');
      expect(parser.toBangla('raShTro'), 'রাষ্ট্র');
      expect(parser.toBangla('bOIShNb'), 'বৈষ্ণব');
      expect(parser.toBangla('lokkhmI'), 'লক্ষ্মী');
      expect(parser.toBangla('bangla'), 'বাংলা');
      expect(parser.toBangla('vaNgaghor'), 'ভাঙাঘর');
      expect(parser.toBangla('korrtrrik'), 'কর্তৃক');
      expect(parser.toBangla('boNGcona'), 'বঞ্চনা');
      expect(parser.toBangla('jhoNGjha'), 'ঝঞ্ঝা');
      expect(parser.toBangla('udhbhranto'), 'উধভ্রান্ত');
      expect(parser.toBangla('oar'), 'অয়ার');
      expect(parser.toBangla('biggan'), 'বিজ্ঞান');
      expect(parser.toBangla('cihn'), 'চিহ্ন');
      expect(parser.toBangla(''), '');
    });
  });
}
