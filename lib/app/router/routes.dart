/// Route names and path builders. Keep every path in one place.
abstract final class Routes {
  static const splash = '/splash';
  static const home = '/home';
  static const settings = '/settings';

  static const camera = '/camera';
  static const adjust = '/adjust';
  static const enhance = '/enhance';
  static const signature = '/signature';
  static const photoCrop = '/photo';

  static String viewer(String docId) => '/doc/$docId';
  static String text(String docId) => '/doc/$docId/text';
  static String print(String docId) => '/doc/$docId/print';
  static String photoSheet(String docId) => '/doc/$docId/photos';
  static String sign(String docId, {String? pageId}) => '/doc/$docId/sign${pageId == null ? '' : '?page=$pageId'}';

  static const viewerPattern = '/doc/:docId';
  static const textPattern = '/doc/:docId/text';
  static const printPattern = '/doc/:docId/print';
}
