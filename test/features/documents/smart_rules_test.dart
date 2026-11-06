import 'dart:io';

import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/smart_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rules = SmartRules.fromJson(File('assets/smart_rules.json').readAsStringSync());
  final scanned = DateTime(2026, 11, 5);

  NameSuggestion? doc(String text) => rules.match(text, ScanMode.document, scanned);

  test('LESCO bill: Bills, month and year from the bill month', () {
    final s = doc('''
LAHORE ELECTRIC SUPPLY COMPANY (LESCO)
CONSUMER ID 0412345  REFERENCE NO 12 11223 1234567
BILL MONTH  OCT 26   READING DATE 18-OCT-26   ISSUE DATE 20-OCT-26
DUE DATE 03-NOV-26
UNITS CONSUMED 312   METER NO 4412
PAYABLE WITHIN DUE DATE 8,450
''')!;
    expect(s.folder, DocFolder.bills);
    expect(s.title, 'Electricity bill – Oct 2026');
    expect(s.kind, 'an electricity bill');
  });

  test('CNIC number on a document scan: IDs', () {
    final s = doc('Name: Ali Khan\nIdentity Number 35202-1234567-1\nDate of Birth 01.02.1990')!;
    expect(s.folder, DocFolder.ids);
    expect(s.title, 'CNIC');
  });

  test('card modes are IDs whatever the text says', () {
    expect(rules.match('', ScanMode.idCard, scanned, pages: 2)!.title, 'ID card – front & back');
    expect(rules.match('35202-1234567-1', ScanMode.idCard, scanned, pages: 2)!.title, 'CNIC – front & back');
    final p = rules.match('PASSPORT  P<PAK', ScanMode.passport, scanned)!;
    expect(p.title, 'Passport – data page');
    expect(p.folder, DocFolder.ids);
  });

  test('result card: Education, year from the text', () {
    final s = doc('''
BOARD OF INTERMEDIATE AND SECONDARY EDUCATION, LAHORE
RESULT CARD  Annual Examination 2025
Roll No 412233   Marks Obtained 912 / 1100   Grade A+
''')!;
    expect(s.folder, DocFolder.education);
    expect(s.title, 'Result card – 2025');
  });

  test('notes: chapter number when there is one', () {
    expect(doc('Chapter 4 — Photosynthesis\nDefinition: the process by which…')!.title, 'Notes – Chapter 4');
    expect(doc('Assignment 2\nQuestion 1: explain the lecture topic')!.title, 'Notes – 05 Nov 2026');
  });

  test('receipt: Receipts, date from the text', () {
    final s = doc('''
AL-FATAH STORE  Cash Memo / Receipt
Date: 02/11/2026   Time 18:42
Milk 1L      x2    560
Bread        x1    180
Subtotal          740   GST 0
TOTAL             740   CASH 1000   CHANGE 260
''')!;
    expect(s.folder, DocFolder.receipts);
    expect(s.title, 'Receipt – 02 Nov 2026');
  });

  test('no match keeps the default name', () {
    expect(doc('Dear Sara, thank you for the lovely dinner last week. See you soon!'), isNull);
    expect(doc(''), isNull);
  });

  test('weak words alone do not match; whole words only', () {
    expect(doc('The total was totally fine, paid in cash.'), isNotNull, reason: 'two receipt hints still add up to 2');
    expect(doc('We totally agree.'), isNull, reason: '"total" must not match inside "totally"');
    expect(doc('As a result we left early.'), isNull, reason: 'one hint is not enough');
  });

  test('a bill with no readable date falls back to the scan date', () {
    expect(doc('SNGPL gas bill  consumer no 123')!.title, 'Gas bill – Nov 2026');
  });
}
