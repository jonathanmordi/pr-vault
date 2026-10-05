// Unit tests for pure app logic.
//
// The heavy screens (leaderboard, profiles, maxes) are wired directly to
// Supabase, so widget-level tests would need a live/mocked backend. The pure,
// backend-free logic worth locking down lives in helpers like formatName,
// which turns TFRRS "Last, First" strings into display names shown all over
// the UI.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/design_system.dart';

void main() {
  group('formatName', () {
    test('flips "Last, First" into "First Last"', () {
      expect(formatName('Smith, John'), 'John Smith');
    });

    test('trims whitespace around the comma', () {
      expect(formatName('Smith ,  John'), 'John Smith');
    });

    test('leaves an already-formatted name untouched', () {
      expect(formatName('John Smith'), 'John Smith');
    });

    test('handles a single name with no comma', () {
      expect(formatName('Cher'), 'Cher');
    });

    test('handles hyphenated and multi-part last names', () {
      expect(formatName('Smith-Jones, Mary Ann'), 'Mary Ann Smith-Jones');
    });
  });

  group('initialsFor', () {
    test('uses first and last initials of the display name', () {
      expect(initialsFor('Smith, John'), 'JS');
    });

    test('ignores stray spaces instead of crashing', () {
      expect(initialsFor('John  Smith'), 'JS');
    });

    test('handles single and empty names', () {
      expect(initialsFor('cher'), 'C');
      expect(initialsFor(''), '?');
    });
  });
}
