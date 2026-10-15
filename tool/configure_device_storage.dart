import 'dart:io';

/// Run after flutter create when generating native platform projects.
void main() {
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  if (project.existsSync()) {
    File('ios/Runner/Runner.entitlements').writeAsStringSync(
      '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>keychain-access-groups</key><array/></dict></plist>
''',
    );
    var text = project.readAsStringSync();
    if (!text.contains(
      'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
    )) {
      text = text.replaceAll(
        'INFOPLIST_FILE = Runner/Info.plist;',
        'INFOPLIST_FILE = Runner/Info.plist;\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;',
      );
      project.writeAsStringSync(text);
    }
  }
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    var text = manifest.readAsStringSync();
    // Platform backups must not copy device-bound encrypted credentials.
    text = text.replaceAll(RegExp(r'\sandroid:allowBackup="[^"]*"'), '');
    text = text.replaceFirst(
      '<application',
      '<application android:allowBackup="false"',
    );
    manifest.writeAsStringSync(text);
  }
}
