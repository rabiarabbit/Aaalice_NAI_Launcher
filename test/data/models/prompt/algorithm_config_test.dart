import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/prompt/algorithm_config.dart';

void main() {
  test('effectiveCharacterCountConfig uses explicit characterCountConfig', () {
    final explicit = AlgorithmConfig.naiDefault.effectiveCharacterCountConfig;
    final config = AlgorithmConfig(characterCountConfig: explicit);

    expect(config.effectiveCharacterCountConfig, same(explicit));
  });

  test('effectiveCharacterCountConfig maps legacy count and gender weights',
      () {
    const config = AlgorithmConfig(
      characterCountWeights: [
        [0, 25],
        [1, 75],
      ],
      genderWeights: {
        'female': 80,
        'male': 20,
        'other': 1,
      },
    );

    final effective = config.effectiveCharacterCountConfig;
    final noHumans = effective.findCategoryById('no_humans');
    final solo = effective.findCategoryById('solo');
    final girl =
        solo!.tagOptions.firstWhere((option) => option.id == 'solo_girl');
    final boy = solo.tagOptions.firstWhere((option) => option.id == 'solo_boy');

    expect(noHumans!.weight, 25);
    expect(solo.weight, 75);
    expect(girl.weight, 80);
    expect(boy.weight, 20);
  });
}
