/// Route names and path builders. Keep every path in one place.
abstract final class Routes {
  static const splash = '/splash';
  static const home = '/home';
  static const settings = '/settings';

  static const camera = '/camera';
  static const adjust = '/adjust';
  static const enhance = '/enhance';

  static String viewer(String docId) => '/doc/$docId';
  static String text(String docId) => '/doc/$docId/text';
  static String print(String docId) => '/doc/$docId/print';

  static const viewerPattern = '/doc/:docId';
  static const textPattern = '/doc/:docId/text';
  static const printPattern = '/doc/:docId/print';
}
