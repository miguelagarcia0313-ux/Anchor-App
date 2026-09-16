import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anchor_app/shell/module_preferences.dart';

void main() {
  test('stores module selections separately for each user', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = ModulePreferences();
    const allModules = {'finance', 'health', 'tasks'};

    await preferences.save(
      userId: 'user-a',
      enabledModuleIds: {'finance', 'tasks'},
    );
    await preferences.save(userId: 'user-b', enabledModuleIds: {'health'});

    expect(
      await preferences.load(userId: 'user-a', defaultModuleIds: allModules),
      {'finance', 'tasks'},
    );
    expect(
      await preferences.load(userId: 'user-b', defaultModuleIds: allModules),
      {'health'},
    );
  });
}
