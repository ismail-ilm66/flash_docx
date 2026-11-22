import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/save_service.dart';
import 'package:flash_dox/core/services/share_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
import 'package:flash_dox/features/editor/data/services/clean_base_service.dart';
import 'package:flash_dox/features/editor/data/services/page_render_service.dart';
import 'package:flash_dox/features/editor/domain/entities/render_size.dart';
import 'package:flash_dox/features/editor/domain/services/image_processor.dart';
import 'package:flash_dox/features/export/domain/entities/export_options.dart';
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart';
import 'package:flash_dox/features/export/domain/shrink_to_fit.dart';
import 'package:flash_dox/features/export/domain/usecases/export_document.dart';
import 'package:flash_dox/features/print_layout/data/sheet_image_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Render extends Mock implements PageRenderService {}

class _Pdf extends Mock implements PdfBuilder {}

class _Share extends Mock implements ShareService {}

class _Save extends Mock implements SaveService {}

class _Repo extends Mock implements DocumentRepository {}

class _Sheet extends Mock implements SheetImageRenderer {}

class _Proc extends Mock implements ImageProcessor {}

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);
  final Directory root;
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(root.path, 'docs');
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
}

void main() {
  late Directory tmp;
  late FileStore files;
  late _Render render;
  late _Pdf pdf;
  late _Share share;
  late ExportDocument export;
  late ScanDocument doc;
  late _Proc proc;
  var pdfBytes = <int>[9];

  setUpAll(() {
    registerFallbackValue(const PdfOptions());
    registerFallbackValue(RenderSize.standard);
    registerFallbackValue(
      const ScanPage(
        id: '',
        documentId: '',
        originalPath: '',
        edits: PageEdits(),
        order: 0,
      ),
    );
    registerFallbackValue(ActivityType.sharedPdf);
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('export_doc');
    PathProviderPlatform.instance = _Paths(tmp);
    files = FileStore();
    await files.init();
    render = _Render();
    pdf = _Pdf();
    share = _Share();
    final repo = _Repo();
    export = ExportDocument(
      render,
      pdf,
      files,
      share,
      _Save(),
      repo,
      _Sheet(),
      proc = _Proc(),
    );
    pdfBytes = [9];
    when(() => render.joinWarm(any())).thenAnswer((_) async => false);
    when(
      () => render.renderExportPage(
        any(),
        size: any(named: 'size'),
        outputPath: any(named: 'outputPath'),
        jpegQuality: any(named: 'jpegQuality'),
        card: any(named: 'card'),
      ),
    ).thenAnswer((inv) async {
      final out = inv.namedArguments[#outputPath] as String;
      File(out)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      return out;
    });
    when(
      () => pdf.fromPages(any(), any(), outputPath: any(named: 'outputPath')),
    ).thenAnswer((inv) async {
      final out = File(inv.namedArguments[#outputPath] as String)
        ..parent.createSync(recursive: true);
      return out..writeAsBytesSync(pdfBytes);
    });
    when(
      () => share.shareFiles(any(), subject: any(named: 'subject')),
    ).thenAnswer((_) async => const Right(unit));
    when(
      () => repo.logActivity(any(), any()),
    ).thenAnswer((_) async => const Right(unit));

    final pages = [
      for (var i = 0; i < 3; i++)
        ScanPage(
          id: 'p$i',
          documentId: 'd',
          originalPath: files.newCapturePath('o$i'),
          edits: const PageEdits(),
          order: i,
        ),
    ];
    for (final pg in pages) {
      File(pg.originalPath).writeAsBytesSync([1]);
    }
    doc = ScanDocument(
      id: 'd',
      title: 'Lease',
      mode: ScanMode.document,
      pages: pages,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  });

  tearDown(() => tmp.delete(recursive: true));

  int renders() => verify(
    () => render.renderExportPage(
      any(),
      size: any(named: 'size'),
      outputPath: any(named: 'outputPath'),
      jpegQuality: any(named: 'jpegQuality'),
      card: any(named: 'card'),
    ),
  ).callCount;

  test(
    'P0-4: page JPEGs are rendered once and reused for a new page size or JPG',
    () async {
      final steps = <String>[];
      final a4 = await export.prepare(
        doc,
        const ExportOptions(),
        onStep: (d, t) => steps.add('$d/$t'),
      );
      expect(a4.isRight(), isTrue);
      expect(steps, ['0/3', '1/3', '2/3', '3/3']);
      expect(renders(), 3);

      final letter = await export.prepare(
        doc,
        const ExportOptions(pageSize: PdfPageSize.letter),
      );
      expect(letter.isRight(), isTrue);
      verifyNever(
        () => render.renderExportPage(
          any(),
          size: any(named: 'size'),
          outputPath: any(named: 'outputPath'),
          jpegQuality: any(named: 'jpegQuality'),
          card: any(named: 'card'),
        ),
      );

      final jpg = (await export.prepare(
        doc,
        const ExportOptions(format: ExportFormat.jpg),
      )).getOrElse((_) => const PreparedExport([])).files;
      expect(jpg, hasLength(3));
      verifyNever(
        () => render.renderExportPage(
          any(),
          size: any(named: 'size'),
          outputPath: any(named: 'outputPath'),
          jpegQuality: any(named: 'jpegQuality'),
          card: any(named: 'card'),
        ),
      );

      // High quality is a different render.
      await export.prepare(
        doc,
        const ExportOptions(quality: ExportQuality.high),
      );
      expect(renders(), 3);
    },
  );

  test('round 10, P1-1: Standard and High really differ (2000 px q80 vs 3000 px q92)', () async {
    for (final q in ExportQuality.values) {
      await export.prepare(doc, ExportOptions(quality: q, format: ExportFormat.jpg));
    }
    final calls = verify(
      () => render.renderExportPage(
        any(),
        size: captureAny(named: 'size'),
        outputPath: any(named: 'outputPath'),
        jpegQuality: captureAny(named: 'jpegQuality'),
        card: any(named: 'card'),
      ),
    ).captured;
    final pairs = {for (var i = 0; i < calls.length; i += 2) (calls[i] as RenderSize, calls[i + 1] as int)};
    expect(pairs, {(RenderSize.standard, 80), (RenderSize.full, 92)});
    expect(RenderSize.standard.longEdge, 2000);
    expect(CleanBaseService.highLongEdge, 3000, reason: 'High renders the 3000 px base');
    expect(
      ExportDocument.estimatePageBytes(const ExportOptions(quality: ExportQuality.high)),
      greaterThan(2 * ExportDocument.estimatePageBytes(const ExportOptions())),
    );
  });

  test('a cancelled job stops before the next page', () async {
    final token = CancelToken();
    final r = await export.prepare(
      doc,
      const ExportOptions(),
      cancel: token,
      onStep: (d, _) {
        if (d == 1) token.cancel();
      },
    );
    expect(r.getLeft().toNullable(), isA<CancelledFailure>());
    expect(renders(), 1);
    verifyNever(
      () => pdf.fromPages(any(), any(), outputPath: any(named: 'outputPath')),
    );
  });

  test('deliver names the files after the chosen file name', () async {
    final jpg = (await export.prepare(
      doc,
      const ExportOptions(format: ExportFormat.jpg),
    )).getOrElse((_) => const PreparedExport([])).files;
    var existedWhileSharing = false;
    when(
      () => share.shareFiles(any(), subject: any(named: 'subject')),
    ).thenAnswer((inv) async {
      final files = inv.positionalArguments.first as List<File>;
      existedWhileSharing = files.every((f) => f.existsSync());
      return const Right(unit);
    });
    final r = await export.deliver(
      doc,
      jpg,
      const ExportOptions(format: ExportFormat.jpg, fileName: 'My lease'),
      ExportTarget.share,
    );
    expect(r.isRight(), isTrue);
    final shared =
        verify(
              () => share.shareFiles(
                captureAny(),
                subject: any(named: 'subject'),
              ),
            ).captured.single
            as List<File>;
    expect(shared.map((f) => p.basename(f.path)), [
      'My lease_1.jpg',
      'My lease_2.jpg',
      'My lease_3.jpg',
    ]);
    expect(existedWhileSharing, isTrue);
    // Round 6, P0-3: the copies are deleted once the sheet closes; the
    // cached page renders they were made from stay.
    expect(shared.any((f) => f.existsSync()), isFalse);
    expect(jpg.every((f) => f.existsSync()), isTrue);
  });

  group('Max file size (feature 2)', () {
    void stubShrink(List<ShrinkOutcome> outcomes) {
      var call = 0;
      when(
        () => proc.shrinkPages(
          any(),
          targetBytes: any(named: 'targetBytes'),
          overheadBytes: any(named: 'overheadBytes'),
          grayscale: any(named: 'grayscale'),
          outputs: any(named: 'outputs'),
          minEdge: any(named: 'minEdge'),
        ),
      ).thenAnswer((inv) async {
        for (final out in inv.namedArguments[#outputs] as List<String>) {
          File(out)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync([1]);
        }
        return outcomes[call++];
      });
    }

    List<Object?> shrinkCall(String name) => verify(
          () => proc.shrinkPages(
            any(),
            targetBytes: any(named: 'targetBytes'),
            overheadBytes: name == 'overheadBytes' ? captureAny(named: 'overheadBytes') : any(named: 'overheadBytes'),
            grayscale: name == 'grayscale' ? captureAny(named: 'grayscale') : any(named: 'grayscale'),
            outputs: any(named: 'outputs'),
            minEdge: name == 'minEdge' ? captureAny(named: 'minEdge') : any(named: 'minEdge'),
          ),
        ).captured;

    test('renders 2000 px bases once, then builds the PDF at the chosen settings', () async {
      stubShrink([const ShrinkFits(ShrinkStep(1700, 70), 400000)]);
      final steps = <String>[];
      final r = await export.prepare(doc, const ExportOptions(maxBytes: 500000), onStep: (d, t) => steps.add('$d/$t'));
      final prepared = r.getOrElse((f) => throw StateError('$f'));
      expect(prepared.shrunk, const ShrinkStep(1700, 70));
      expect(steps.last, '4/4', reason: '3 pages + the search');
      verify(
        () => render.renderExportPage(any(), size: RenderSize.standard, outputPath: any(named: 'outputPath'), jpegQuality: 95, card: any(named: 'card')),
      ).called(3);

      // A second export with another limit reuses the bases.
      stubShrink([const ShrinkFits(ShrinkStep(1228, 60), 190000)]);
      final small = (await export.prepare(doc, const ExportOptions(maxBytes: 200000))).getOrElse((f) => throw StateError('$f'));
      expect(small.shrunk!.hardToRead, isTrue);
      verifyNever(
        () => render.renderExportPage(any(), size: any(named: 'size'), outputPath: any(named: 'outputPath'), jpegQuality: any(named: 'jpegQuality'), card: any(named: 'card')),
      );
    });

    test('colour that cannot fit offers black and white; grayscale that cannot fit gives up', () async {
      stubShrink([const ShrinkNeedsGrayscale(260000)]);
      final colour = await export.prepare(doc, const ExportOptions(maxBytes: 200000));
      expect(
        colour.getLeft().toNullable(),
        const ShrinkFailure(targetBytes: 200000, smallestBytes: 260000, canTryGrayscale: true),
      );

      stubShrink([const ShrinkCantFit(230000)]);
      final gray = await export.prepare(doc, const ExportOptions(maxBytes: 200000, grayscaleToFit: true));
      expect((gray.getLeft().toNullable()! as ShrinkFailure).canTryGrayscale, isFalse);
      expect(shrinkCall('grayscale'), [false, true], reason: 'colour first, then black and white');
    });

    test('a PDF bigger than estimated searches again with the real overhead', () async {
      pdfBytes = List.filled(1200, 0);
      stubShrink([const ShrinkFits(ShrinkStep(2000, 80), 900), const ShrinkFits(ShrinkStep(2000, 75), 700)]);
      pdfBytes = List.filled(1200, 0);
      var builds = 0;
      when(() => pdf.fromPages(any(), any(), outputPath: any(named: 'outputPath'))).thenAnswer((inv) async {
        final out = File(inv.namedArguments[#outputPath] as String)..parent.createSync(recursive: true);
        // First build overshoots the 1000-byte limit, the second fits.
        return out..writeAsBytesSync(List.filled(builds++ == 0 ? 1200 : 950, 0));
      });
      final r = await export.prepare(doc, const ExportOptions(maxBytes: 1000));
      expect(r.getOrElse((f) => throw StateError('$f')).shrunk, const ShrinkStep(2000, 75));
      final overheads = shrinkCall('overheadBytes').cast<int>();
      expect(overheads, hasLength(2));
      expect(overheads[1] - overheads[0], 1200 - 900);
    });

    test('page images and the one-picture card layout ignore the limit', () {
      expect(ExportDocument.shrinks(doc, const ExportOptions(maxBytes: 1, format: ExportFormat.jpg)), isFalse);
      expect(ExportDocument.shrinks(doc, const ExportOptions(maxBytes: 1)), isTrue);
      expect(ExportDocument.shrinks(doc, const ExportOptions()), isFalse);
    });

    test('a passport photo at an exact pixel size (JPG, PNG, and with a size limit)', () async {
      final photo = doc.copyWith(mode: ScanMode.photo, pages: [doc.sortedPages.first]);
      when(
        () => proc.resizeExact(any(), any(), any(), outputPath: any(named: 'outputPath'), jpegQuality: any(named: 'jpegQuality')),
      ).thenAnswer((inv) async {
        final out = inv.namedArguments[#outputPath] as String;
        File(out)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync([7]);
        return out;
      });
      for (final format in [ExportFormat.jpg, ExportFormat.png]) {
        final r = await export.prepare(photo, ExportOptions(format: format, pixelWidth: 600, pixelHeight: 771));
        final file = r.getOrElse((f) => throw StateError('$f')).files.single;
        expect(file.path, endsWith('600x771.${format.name}'));
      }
      verify(
        () => proc.resizeExact(any(), 600, 771, outputPath: any(named: 'outputPath'), jpegQuality: any(named: 'jpegQuality')),
      ).called(2);

      stubShrink([const ShrinkFits(ShrinkStep(771, 60), 90000)]);
      await export.prepare(photo, const ExportOptions(format: ExportFormat.jpg, pixelWidth: 600, pixelHeight: 771, maxBytes: 100000));
      final minEdge = verify(
        () => proc.shrinkPages(
          any(),
          targetBytes: any(named: 'targetBytes'),
          overheadBytes: any(named: 'overheadBytes'),
          grayscale: any(named: 'grayscale'),
          outputs: any(named: 'outputs'),
          minEdge: captureAny(named: 'minEdge'),
        ),
      ).captured;
      expect(minEdge, [771], reason: 'the size is kept; only the quality drops');
    });

    test('a passport photo shrinks as a JPG: no PDF, small sizes allowed, never black and white', () async {
      final photo = doc.copyWith(mode: ScanMode.photo, pages: [doc.sortedPages.first]);
      expect(ExportDocument.canShrink(photo, const ExportOptions(format: ExportFormat.jpg)), isTrue);
      expect(ExportDocument.canShrink(photo, const ExportOptions(format: ExportFormat.png)), isFalse, reason: 'PNG is lossless');
      stubShrink([const ShrinkFits(ShrinkStep(642, 70), 48000)]);
      final r = await export.prepare(photo, const ExportOptions(format: ExportFormat.jpg, maxBytes: 50000));
      final prepared = r.getOrElse((f) => throw StateError('$f'));
      expect(prepared.files.single.path, endsWith('.jpg'));
      expect(prepared.shrunk, const ShrinkStep(642, 70));
      verifyNever(() => pdf.fromPages(any(), any(), outputPath: any(named: 'outputPath')));
      final call = verify(
        () => proc.shrinkPages(
          any(),
          targetBytes: any(named: 'targetBytes'),
          overheadBytes: captureAny(named: 'overheadBytes'),
          grayscale: any(named: 'grayscale'),
          outputs: any(named: 'outputs'),
          minEdge: captureAny(named: 'minEdge'),
        ),
      ).captured;
      expect(call, [0, ShrinkToFit.photoMinEdge], reason: 'no PDF overhead; photos may go small');

      stubShrink([const ShrinkNeedsGrayscale(70000)]);
      final tooSmall = await export.prepare(photo, const ExportOptions(format: ExportFormat.jpg, maxBytes: 20000, grayscaleToFit: true));
      expect((tooSmall.getLeft().toNullable()! as ShrinkFailure).canTryGrayscale, isFalse);
      expect(shrinkCall('grayscale'), [false]);
    });
  });
}
