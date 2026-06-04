import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/prompt/random_prompt_result.dart';
import 'package:nai_launcher/presentation/providers/random_mode_provider.dart';

void main() {
  group('RandomGenerationMode storage serialization', () {
    test('serializes every implemented mode', () {
      expect(
        RandomGenerationMode.naiOfficial.toStorageValue(),
        'nai_official',
      );
      expect(RandomGenerationMode.custom.toStorageValue(), 'custom');
      expect(RandomGenerationMode.hybrid.toStorageValue(), 'hybrid');
    });

    test('deserializes known values and falls back for unknown values', () {
      expect(
        randomGenerationModeFromStorage('nai_official'),
        RandomGenerationMode.naiOfficial,
      );
      expect(
        randomGenerationModeFromStorage('custom'),
        RandomGenerationMode.custom,
      );
      expect(
        randomGenerationModeFromStorage('hybrid'),
        RandomGenerationMode.hybrid,
      );
      expect(
        randomGenerationModeFromStorage('future_mode'),
        RandomGenerationMode.naiOfficial,
      );
      expect(
        randomGenerationModeFromStorage(''),
        RandomGenerationMode.naiOfficial,
      );
    });
  });

  group('RandomModeNotifier persistence', () {
    test('build reads the persisted generation mode', () {
      final storage = _FakeRandomModeStorage(initialMode: 'hybrid');
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWith((ref) => storage),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(randomModeNotifierProvider),
        RandomGenerationMode.hybrid,
      );
      expect(container.read(isNaiOfficialModeProvider), isFalse);
      expect(container.read(isCustomModeProvider), isFalse);
    });

    test('build falls back to official mode for unknown stored values', () {
      final storage = _FakeRandomModeStorage(initialMode: 'unknown');
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWith((ref) => storage),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(randomModeNotifierProvider),
        RandomGenerationMode.naiOfficial,
      );
      expect(container.read(isNaiOfficialModeProvider), isTrue);
    });

    test('setMode persists the selected mode', () async {
      final storage = _FakeRandomModeStorage();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWith((ref) => storage),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(randomModeNotifierProvider.notifier)
          .setMode(RandomGenerationMode.hybrid);

      expect(
        container.read(randomModeNotifierProvider),
        RandomGenerationMode.hybrid,
      );
      expect(storage.mode, 'hybrid');
      expect(storage.writeLog, ['hybrid']);
    });

    test('setMode rolls back state when persistence fails', () async {
      final storage = _FakeRandomModeStorage(
        initialMode: 'custom',
        failWrites: true,
      );
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWith((ref) => storage),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(randomModeNotifierProvider.notifier)
          .setMode(RandomGenerationMode.hybrid);

      expect(
        container.read(randomModeNotifierProvider),
        RandomGenerationMode.custom,
      );
      expect(storage.writeLog, isEmpty);
    });

    test('named setters persist official, custom, and hybrid modes', () async {
      final storage = _FakeRandomModeStorage(initialMode: 'custom');
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWith((ref) => storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(randomModeNotifierProvider.notifier);
      await notifier.useNaiOfficial();
      await notifier.useCustom();
      await notifier.useHybrid();

      expect(
        container.read(randomModeNotifierProvider),
        RandomGenerationMode.hybrid,
      );
      expect(storage.writeLog, ['nai_official', 'custom', 'hybrid']);
    });

    test('toggle cycles official to custom to hybrid to official', () async {
      final storage = _FakeRandomModeStorage();
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWith((ref) => storage),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(randomModeNotifierProvider.notifier);

      expect(
        container.read(randomModeNotifierProvider),
        RandomGenerationMode.naiOfficial,
      );

      await notifier.toggle();
      expect(
        container.read(randomModeNotifierProvider),
        RandomGenerationMode.custom,
      );

      await notifier.toggle();
      expect(
        container.read(randomModeNotifierProvider),
        RandomGenerationMode.hybrid,
      );

      await notifier.toggle();
      expect(
        container.read(randomModeNotifierProvider),
        RandomGenerationMode.naiOfficial,
      );

      expect(storage.writeLog, ['custom', 'hybrid', 'nai_official']);
    });
  });
}

class _FakeRandomModeStorage extends LocalStorageService {
  _FakeRandomModeStorage({
    String initialMode = 'nai_official',
    this.failWrites = false,
  }) : mode = initialMode;

  String mode;
  final bool failWrites;
  final List<String> writeLog = [];

  @override
  String getRandomGenerationMode() => mode;

  @override
  Future<void> setRandomGenerationMode(String value) async {
    if (failWrites) {
      throw StateError('write failed');
    }
    mode = value;
    writeLog.add(value);
  }
}
