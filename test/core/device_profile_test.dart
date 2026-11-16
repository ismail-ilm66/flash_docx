import 'package:flash_dox/core/services/device_profile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.swtnoa.flashdox/device');

  Future<DeviceProfile> load(Map<String, Object?>? reply) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => reply,
    );
    final d = DeviceProfile();
    await d.load();
    return d;
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('a 4 GB phone (3.6 GiB reported, Y9 Prime 2019) is not low-RAM', () async {
    final d = await load({'totalBytes': 3775716 * 1024, 'lowRam': false});
    expect(d.isLowRam, isFalse);
  });

  test('a 3 GB phone (~2.8 GiB reported) is low-RAM', () async {
    final d = await load({'totalBytes': 2900 * 1024 * 1024, 'lowRam': false});
    expect(d.isLowRam, isTrue);
  });

  test("Android's low-RAM flag wins", () async {
    final d = await load({'totalBytes': 6 * 1024 * 1024 * 1024, 'lowRam': true});
    expect(d.isLowRam, isTrue);
  });

  test('no answer from the platform: a normal phone', () async {
    expect((await load(null)).isLowRam, isFalse);
    expect(DeviceProfile().isLowRam, isFalse, reason: 'before load');
  });
}
