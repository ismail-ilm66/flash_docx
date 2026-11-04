// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:connectivity_plus/connectivity_plus.dart' as _i895;
import 'package:flash_dox/app/di/register_module.dart' as _i254;
import 'package:flash_dox/core/services/connectivity_service.dart' as _i427;
import 'package:flash_dox/core/services/file_store.dart' as _i626;
import 'package:flash_dox/core/services/isolate_runner.dart' as _i448;
import 'package:flash_dox/core/services/prefs_service.dart' as _i567;
import 'package:flash_dox/core/services/save_service.dart' as _i792;
import 'package:flash_dox/core/services/share_in_service.dart' as _i742;
import 'package:flash_dox/core/services/share_service.dart' as _i856;
import 'package:flash_dox/features/documents/data/db/app_database.dart'
    as _i554;
import 'package:flash_dox/features/documents/data/repositories/document_repository_impl.dart'
    as _i257;
import 'package:flash_dox/features/documents/domain/entities/entities.dart'
    as _i355;
import 'package:flash_dox/features/documents/domain/repositories/document_repository.dart'
    as _i132;
import 'package:flash_dox/features/documents/domain/usecases/document_usecases.dart'
    as _i310;
import 'package:flash_dox/features/documents/domain/usecases/watch_documents.dart'
    as _i948;
import 'package:flash_dox/features/documents/presentation/cubit/home_cubit.dart'
    as _i713;
import 'package:flash_dox/features/documents/presentation/cubit/viewer_cubit.dart'
    as _i411;
import 'package:flash_dox/features/editor/data/services/opencv_image_processor.dart'
    as _i421;
import 'package:flash_dox/features/editor/data/services/page_render_service.dart'
    as _i120;
import 'package:flash_dox/features/editor/domain/services/image_processor.dart'
    as _i618;
import 'package:flash_dox/features/editor/presentation/bloc/page_editor_bloc.dart'
    as _i935;
import 'package:flash_dox/features/editor/presentation/editor_args.dart'
    as _i546;
import 'package:flash_dox/features/export/data/pdf_builder_impl.dart' as _i337;
import 'package:flash_dox/features/export/domain/services/pdf_builder.dart'
    as _i435;
import 'package:flash_dox/features/export/domain/usecases/export_document.dart'
    as _i402;
import 'package:flash_dox/features/export/presentation/bloc/export_bloc.dart'
    as _i314;
import 'package:flash_dox/features/ocr/data/mlkit_text_recognizer.dart'
    as _i346;
import 'package:flash_dox/features/ocr/domain/recognize_page_text.dart'
    as _i813;
import 'package:flash_dox/features/ocr/domain/text_recognizer.dart' as _i917;
import 'package:flash_dox/features/ocr/presentation/cubit/ocr_cubit.dart'
    as _i323;
import 'package:flash_dox/features/print_layout/data/sheet_image_renderer.dart'
    as _i84;
import 'package:flash_dox/features/print_layout/domain/usecases/build_print_layout.dart'
    as _i60;
import 'package:flash_dox/features/print_layout/presentation/cubit/print_layout_cubit.dart'
    as _i603;
import 'package:flash_dox/features/rewards/data/admob_reward_gate.dart' as _i32;
import 'package:flash_dox/features/rewards/domain/reward_gate.dart' as _i607;
import 'package:flash_dox/features/rewards/presentation/reward_cubit.dart'
    as _i904;
import 'package:flash_dox/features/scanner/data/import_service.dart' as _i959;
import 'package:flash_dox/features/scanner/domain/usecases/prepare_pages.dart'
    as _i922;
import 'package:flash_dox/features/scanner/presentation/bloc/scan_session_bloc.dart'
    as _i382;
import 'package:flash_dox/features/settings/presentation/cubit/settings_cubit.dart'
    as _i493;
import 'package:flash_dox/features/settings/presentation/cubit/theme_cubit.dart'
    as _i242;
import 'package:get_it/get_it.dart' as _i174;
import 'package:image_picker/image_picker.dart' as _i183;
import 'package:injectable/injectable.dart' as _i526;
import 'package:share_plus/share_plus.dart' as _i998;
import 'package:shared_preferences/shared_preferences.dart' as _i460;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final registerModule = _$RegisterModule();
    await gh.lazySingletonAsync<_i460.SharedPreferences>(
      () => registerModule.prefs,
      preResolve: true,
    );
    gh.lazySingleton<_i895.Connectivity>(() => registerModule.connectivity);
    gh.lazySingleton<_i998.SharePlus>(() => registerModule.sharePlus);
    gh.lazySingleton<_i183.ImagePicker>(() => registerModule.imagePicker);
    await gh.lazySingletonAsync<_i626.FileStore>(() {
      final i = _i626.FileStore();
      return i.init().then((_) => i);
    }, preResolve: true);
    gh.lazySingleton<_i448.IsolateRunner>(() => _i448.IsolateRunner());
    gh.lazySingleton<_i792.SaveService>(() => _i792.SaveService());
    gh.lazySingleton<_i742.ShareInService>(() => _i742.ShareInService());
    gh.lazySingleton<_i554.AppDatabase>(
      () => _i554.AppDatabase(),
      dispose: (i) => i.dispose(),
    );
    gh.lazySingleton<_i132.DocumentRepository>(
      () => _i257.DocumentRepositoryImpl(
        gh<_i554.AppDatabase>(),
        gh<_i626.FileStore>(),
      ),
    );
    gh.lazySingleton<_i917.TextRecognizer>(
      () => _i346.MlKitTextRecognizer(),
      dispose: (i) => i.dispose(),
    );
    gh.lazySingleton<_i856.ShareService>(
      () => _i856.ShareService(gh<_i998.SharePlus>()),
    );
    gh.lazySingleton<_i427.ConnectivityService>(
      () => _i427.ConnectivityService(gh<_i895.Connectivity>()),
    );
    gh.lazySingleton<_i567.PrefsService>(
      () => _i567.PrefsService(gh<_i460.SharedPreferences>()),
    );
    gh.lazySingleton<_i435.PdfBuilder>(
      () => _i337.PdfBuilderImpl(gh<_i448.IsolateRunner>()),
    );
    gh.lazySingleton<_i84.SheetImageRenderer>(
      () => _i84.SheetImageRenderer(gh<_i448.IsolateRunner>()),
    );
    gh.lazySingleton<_i618.ImageProcessor>(
      () => _i421.OpenCvImageProcessor(gh<_i448.IsolateRunner>()),
    );
    gh.lazySingleton<_i959.ImportService>(
      () => _i959.ImportService(gh<_i183.ImagePicker>()),
    );
    gh.factory<_i310.WatchDocument>(
      () => _i310.WatchDocument(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.GetDocument>(
      () => _i310.GetDocument(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.CreateDocument>(
      () => _i310.CreateDocument(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.RenameDocument>(
      () => _i310.RenameDocument(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.DeleteDocument>(
      () => _i310.DeleteDocument(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.AddPages>(
      () => _i310.AddPages(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.ReorderPages>(
      () => _i310.ReorderPages(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.DeletePage>(
      () => _i310.DeletePage(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.UpdatePages>(
      () => _i310.UpdatePages(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.LogActivity>(
      () => _i310.LogActivity(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i310.GetStorageUsed>(
      () => _i310.GetStorageUsed(gh<_i132.DocumentRepository>()),
    );
    gh.factory<_i948.WatchDocuments>(
      () => _i948.WatchDocuments(gh<_i132.DocumentRepository>()),
    );
    gh.lazySingleton<_i607.RewardGate>(
      () => _i32.AdMobRewardGate(
        gh<_i427.ConnectivityService>(),
        gh<_i567.PrefsService>(),
      ),
    );
    gh.lazySingleton<_i242.ThemeCubit>(
      () => _i242.ThemeCubit(gh<_i567.PrefsService>()),
    );
    gh.factory<_i493.SettingsCubit>(
      () => _i493.SettingsCubit(
        gh<_i567.PrefsService>(),
        gh<_i626.FileStore>(),
        gh<_i310.GetStorageUsed>(),
      ),
    );
    gh.factory<_i922.PreparePages>(
      () => _i922.PreparePages(
        gh<_i618.ImageProcessor>(),
        gh<_i626.FileStore>(),
        gh<_i567.PrefsService>(),
      ),
    );
    gh.factory<_i713.HomeCubit>(
      () => _i713.HomeCubit(
        gh<_i948.WatchDocuments>(),
        gh<_i310.DeleteDocument>(),
        gh<_i310.RenameDocument>(),
      ),
    );
    gh.lazySingleton<_i120.PageRenderService>(
      () => _i120.PageRenderService(
        gh<_i618.ImageProcessor>(),
        gh<_i626.FileStore>(),
        gh<_i132.DocumentRepository>(),
      ),
    );
    gh.factoryParam<_i935.PageEditorBloc, _i546.EditorArgs, dynamic>(
      (args, _) => _i935.PageEditorBloc(
        gh<_i618.ImageProcessor>(),
        gh<_i626.FileStore>(),
        gh<_i310.CreateDocument>(),
        gh<_i310.AddPages>(),
        gh<_i310.UpdatePages>(),
        gh<_i310.LogActivity>(),
        gh<_i120.PageRenderService>(),
        args,
      ),
    );
    gh.factory<_i402.ExportDocument>(
      () => _i402.ExportDocument(
        gh<_i120.PageRenderService>(),
        gh<_i435.PdfBuilder>(),
        gh<_i626.FileStore>(),
        gh<_i856.ShareService>(),
        gh<_i792.SaveService>(),
        gh<_i132.DocumentRepository>(),
      ),
    );
    gh.factory<_i813.RecognizePageText>(
      () => _i813.RecognizePageText(
        gh<_i917.TextRecognizer>(),
        gh<_i120.PageRenderService>(),
        gh<_i132.DocumentRepository>(),
      ),
    );
    gh.factory<_i904.RewardCubit>(
      () => _i904.RewardCubit(gh<_i607.RewardGate>()),
    );
    gh.factoryParam<_i411.ViewerCubit, String, dynamic>(
      (documentId, _) => _i411.ViewerCubit(
        gh<_i310.WatchDocument>(),
        gh<_i310.RenameDocument>(),
        gh<_i310.DeleteDocument>(),
        gh<_i310.DeletePage>(),
        gh<_i310.ReorderPages>(),
        gh<_i120.PageRenderService>(),
        documentId,
      ),
    );
    gh.factoryParam<_i323.OcrCubit, String, String?>(
      (documentId, pageId) => _i323.OcrCubit(
        gh<_i310.GetDocument>(),
        gh<_i813.RecognizePageText>(),
        gh<_i310.LogActivity>(),
        documentId,
        pageId,
      ),
    );
    gh.factoryParam<_i382.ScanSessionBloc, _i355.ScanMode?, dynamic>(
      (initialMode, _) => _i382.ScanSessionBloc(
        gh<_i922.PreparePages>(),
        gh<_i567.PrefsService>(),
        initialMode,
      ),
    );
    gh.factory<_i60.BuildPrintLayout>(
      () => _i60.BuildPrintLayout(
        gh<_i120.PageRenderService>(),
        gh<_i435.PdfBuilder>(),
        gh<_i84.SheetImageRenderer>(),
        gh<_i626.FileStore>(),
        gh<_i856.ShareService>(),
        gh<_i792.SaveService>(),
        gh<_i132.DocumentRepository>(),
      ),
    );
    gh.factoryParam<_i314.ExportBloc, _i355.ScanDocument, dynamic>(
      (document, _) => _i314.ExportBloc(
        gh<_i402.ExportDocument>(),
        gh<_i567.PrefsService>(),
        document,
      ),
    );
    gh.factoryParam<_i603.PrintLayoutCubit, String, dynamic>(
      (documentId, _) => _i603.PrintLayoutCubit(
        gh<_i310.GetDocument>(),
        gh<_i60.BuildPrintLayout>(),
        documentId,
      ),
    );
    return this;
  }
}

class _$RegisterModule extends _i254.RegisterModule {}
