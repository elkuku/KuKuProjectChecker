import 'package:flutter_test/flutter_test.dart';
import 'package:kuku_project_checker/support/open_in.dart';

void main() {
  OpenInTarget target(String label) =>
      OpenInTarget.all.firstWhere((target) => target.label == label);

  test('looks in PATH and in the JetBrains Toolbox scripts folder', () {
    final path =
        OpenInTarget.searchPath({'PATH': '/usr/bin:/bin', 'HOME': '/home/me'});

    expect(path, [
      '/usr/bin',
      '/bin',
      '/home/me/.local/bin',
      '/home/me/.local/share/JetBrains/Toolbox/scripts',
    ]);
  });

  test('lists only the installed apps, with their executable', () {
    final installed = {
      '/usr/bin/xdg-open',
      '/usr/bin/konsole',
      '/home/me/.local/share/JetBrains/Toolbox/scripts/phpstorm',
    };

    final available = OpenInTarget.available(
      environment: {'PATH': '/usr/bin', 'HOME': '/home/me'},
      isExecutable: installed.contains,
    );

    expect([
      for (final (target, executable) in available)
        '${target.label}: $executable'
    ], [
      'File manager: /usr/bin/xdg-open',
      'Terminal: /usr/bin/konsole',
      'PhpStorm: /home/me/.local/share/JetBrains/Toolbox/scripts/phpstorm',
    ]);
  });

  test('takes the first terminal that is installed', () {
    final executable = target('Terminal').findExecutable(
      ['/usr/bin'],
      isExecutable: {'/usr/bin/gnome-terminal', '/usr/bin/kitty'}.contains,
    );

    expect(executable, '/usr/bin/gnome-terminal');
  });

  test('passes the folder the way each app expects it', () {
    expect(target('File manager').arguments('xdg-open', '/r'), ['/r']);
    expect(target('Terminal').arguments('konsole', '/r'), ['--workdir', '/r']);
    expect(target('Terminal').arguments('gnome-terminal', '/r'),
        ['--working-directory=/r']);
    expect(target('PhpStorm').arguments('phpstorm', '/r'), ['/r']);
    expect(target('gitk (history)').arguments('gitk', '/r'), ['--all']);
  });
}
