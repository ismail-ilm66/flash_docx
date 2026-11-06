import 'dart:io';

import 'package:flash_dox/core/error/failures.dart';
import 'package:flash_dox/core/services/file_store.dart';
import 'package:flash_dox/core/services/isolate_runner.dart';
import 'package:flash_dox/core/services/save_service.dart';
import 'package:flash_dox/core/services/share_service.dart';
import 'package:flash_dox/features/documents/domain/entities/entities.dart';
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart';
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
    when(
      () => render.renderForExport(
        any(),
        size: any(named: 'size'),
        outputPath: any(named: 'outputPath'),
        jpegQuality: any(named: 'jpegQuality'),
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
    () => render.renderForExport(
      any(),
      size: any(named: 'size'),
      outputPath: any(named: 'outputPath'),
      jpegQuality: any(named: 'jpegQuality'),
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
        () => render.renderForExport(
          any(),
          size: any(named: 'size'),
          outputPath: any(named: 'outputPath'),
          jpegQuality: any(named: 'jpegQuality'),
        ),
      );

      final jpg = (await export.prepare(
        doc,
        const ExportOptions(format: ExportFormat.jpg),
      )).getOrElse((_) => const PreparedExport([])).files;
      expect(jpg, hasLength(3));
      verifyNever(
        () => render.renderForExport(
          any(),
          size: any(named: 'size'),
          outputPath: any(named: 'outputPath'),
          jpegQuality: any(named: 'jpegQuality'),
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
    expect(shared.every((f) => f.existsSync()), isTrue);
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
        () => render.renderForExport(any(), size: RenderSize.standard, outputPath: any(named: 'outputPath'), jpegQuality: 95),
      ).called(3);

      // A second export with another limit reuses the bases.
      stubShrink([const ShrinkFits(ShrinkStep(1228, 60), 190000)]);
      final small = (await export.prepare(doc, const ExportOptions(maxBytes: 200000))).getOrElse((f) => throw StateError('$f'));
      expect(small.shrunk!.hardToRead, isTrue);
      verifyNever(
        () => render.renderForExport(any(), size: any(named: 'size'), outputPath: any(named: 'outputPath'), jpegQuality: any(named: 'jpegQuality')),
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

    test('images and the one-picture card layout ignore the limit', () {
      expect(ExportDocument.shrinks(doc, const ExportOptions(maxBytes: 1, format: ExportFormat.jpg)), isFalse);
      expect(ExportDocument.shrinks(doc, const ExportOptions(maxBytes: 1)), isTrue);
      expect(ExportDocument.shrinks(doc, const ExportOptions()), isFalse);
    });
  });
}
