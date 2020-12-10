#! /usr/bin/env dcli

import 'dart:async';
import 'dart:io';
import 'package:dcli/dcli.dart';
import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';

/// dcli script generated by:
/// dcli create show.dart
///
/// See
/// https://pub.dev/packages/dcli#-installing-tab-
///
/// For details on installing dcli.
///
Future<void> main(List<String> args) async {
  final parser = ArgParser();
  parser.addFlag(
    'verbose',
    abbr: 'v',
    negatable: false,
    help: 'Logs additional details to the cli',
  );

  parser.addFlag(
    'help',
    abbr: 'h',
    negatable: false,
    help: 'Shows the help message',
  );

  parser.addFlag(
    'show',
    abbr: 's',
    negatable: false,
    help: 'After generating the image file it will be displayed using firefox.',
  );

  parser.addFlag(
    'watch',
    abbr: 'w',
    negatable: false,
    help: 'Monitors the smcat files and regenerates the svg if they change.',
  );

  parser.addFlag(
    'install',
    abbr: 'i',
    negatable: false,
    help: 'Install the smcat dependencies',
  );

  final parsed = parser.parse(args);

  if (parsed.wasParsed('help')) {
    showUsage(parser);
  }

  if (parsed.wasParsed('verbose')) {
    Settings().setVerbose(enabled: true);
  }

  if (parsed.wasParsed('install')) {
    install();
    exit(0);
  }

  if (parsed.rest.isEmpty) {
    // ignore: avoid_print
    print(red('You must pass a to path the basename of the smcat file'));
    showUsage(parser);
  }

  await generateAll(parsed.rest,
      show: parsed.wasParsed('show'), watch: parsed.wasParsed('watch'));
}

Future<void> generateAll(List<String> rest, {bool show, bool watch}) async {
  final watchList = <String>[];

  for (var file in rest) {
    if (exists(file)) {
      watchList.add(file);
      generate(file, show: show);
    } else {
      /// if the passed file name had an extension
      /// then we do an exact match. So if we are
      /// here the file doesn't exist.
      if (extension(file).isNotEmpty) {
        printerr(red('File $file not found'));
        exit(1);
      }

      /// do a glob match as the filename didn't have an extension.
      var count = 0;
      final pattern = '$file.*.smcat';
      for (file in find(pattern, recursive: false).toList()) {
        generate(file, show: show);
        count++;
        watchList.add(file);
      }
      if (count == 0) {
        if (exists(file)) {
          generate(file, show: show);
          watchList.add(file);
        } else {
          printerr(orange(
              'No files found that match the pattern: ${truepath(pattern)}.'));
        }
      }
    }
  }
  if (watch && watchList.isNotEmpty) {
    await watchFiles(watchList);
  }
}

void install() {
  if (which('npm').notfound) {
    // ignore: avoid_print
    print(red('Please install npm and then try again'));
    exit(1);
  }
  'npm install --global state-machine-cat'.start(privileged: true);
}

final lock = Lock();

void generate(String path, {@required bool show}) {
  final outputFile = '${basenameWithoutExtension(path)}.svg';
  // ignore: avoid_print
  print('Generating: $outputFile ');

  /// 'smcat -T dot $path | dot -T svg > your-machine.svg'.run;
  final result = start('smcat $path',
      // ignore: avoid_print
      progress: Progress((stdout) => print(stdout), stderr: (stderr) {
        /// suppress the viz warning:
        /// https://github.com/sverweij/state-machine-cat/issues/127
        // ignore: avoid_print
        if (!stderr.contains('viz.js:33')) print(stderr);
      }),
      nothrow: true);

  if (result.exitCode == 0) {
    /// See if the filename contains a page no.
    var pageNo = extension(basenameWithoutExtension(path));
    if (pageNo.isNotEmpty) {
      pageNo = pageNo.substring(1);

      final page = int.tryParse(pageNo);
      if (page != null) {
        addPageNo(
            '${join(dirname(path), basenameWithoutExtension(path))}.svg', page);
      }
    }
    if (show) {
      'firefox $outputFile'
          .start(detached: true, workingDirectory: dirname(path));
    }
    // ignore: avoid_print
    print('Generation of $outputFile complete.');
  } else {
    // ignore: avoid_print
    print(red('Generation of $outputFile failed.'));
  }
}

/// Add a page no. at the top of the page.
/// We add the svg elements at the very end of the file.
void addPageNo(String svgPath, int page) {
  addInkscapeNamespace(svgPath);

  const xPos = 40;
  const yPos = 40;
  final svgPageNo = '''
    <text
     xml:space="preserve"
     style="font-style:normal;font-weight:normal;font-size:30px;line-height:1.25;font-family:sans-serif;fill:#000000;fill-opacity:1;stroke:none;stroke-width:0.75"
     x="$xPos"
     y="$yPos"
     id="text288"><tspan
       sodipodi:role="line"
       id="tspan286"
       x="$xPos"
       y="$yPos"
       style="font-size:12px;stroke-width:0.75">Page: $page</tspan></text>
</svg>
''';

  replace(svgPath, '</svg>', svgPageNo);
}

void addInkscapeNamespace(String svgPath) {
  const existing = 'xmlns="http://www.w3.org/2000/svg"';

  const replacement =
      'xmlns="http://www.w3.org/2000/svg" xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd" xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"';

  replace(svgPath, existing, replacement);
}

void showUsage(ArgParser parser) {
  // ignore: avoid_print
  print('Usage: ${Script.current.exeName} <base name of myfsm2>\n');
  // ignore: avoid_print
  print('Converts a set of smcat files into svg files.');
  // ignore: avoid_print
  print(
      'If your smcat file has multiple parts due to page breaks then each page will be processed.');
  // ignore: avoid_print
  print(parser.usage);
  exit(1);
}

var _controller = StreamController<FileSystemEvent>();

Future<void> watchFiles(List<String> files) async {
  StreamSubscription<FileSystemEvent> subscriber;
  subscriber = _controller.stream.listen((event) async {
    // serialise the events
    // otherwise we end up trying to move multiple files
    // at once and that doesn't work.
    subscriber.pause();
    onFileSystemEvent(event);
    subscriber.resume();
  });

  /// start a watch on every subdirectory of _projectRoot
  for (final file in files) {
    watchFile(file);
  }

  final forever = Completer<void>();

  forever.future.whenComplete(() => subscriber.cancel());

  // wait until someone does ctrl-c.
  await forever.future;
}

void watchFile(String file) {
  File(file)
      .watch(events: FileSystemEvent.all)
      .listen((event) => _controller.add(event));
}

void watchDirectory(String projectRoot) {
  // ignore: avoid_print
  print('watching $projectRoot');
  Directory(projectRoot)
      .watch(events: FileSystemEvent.all)
      .listen((event) => _controller.add(event));
}

void onFileSystemEvent(FileSystemEvent event) {
  if (event is FileSystemCreateEvent) {
    onCreateEvent(event);
  } else if (event is FileSystemModifyEvent) {
    onModifyEvent(event);
  } else if (event is FileSystemMoveEvent) {
    onMoveEvent(event);
  } else if (event is FileSystemDeleteEvent) {
    onDeleteEvent(event);
  }
}

/// when we see a mod we want to delay the generation as we often
/// see multiple modifications when a file is being updated.
var _toGenerate = <String>[];

void onModifyEvent(FileSystemModifyEvent event) {
  _toGenerate.add(event.path);

  Future.delayed(const Duration(microseconds: 1500), () => delayedGeneration());
}

void delayedGeneration() {
  lock.synchronized(() {
    for (final file in _toGenerate.toSet()) {
      generate(file, show: true);
    }
    _toGenerate.clear();
  });
}

void onCreateEvent(FileSystemCreateEvent event) {
  if (event.isDirectory) {
    Directory(event.path)
        .watch(events: FileSystemEvent.all)
        .listen((event) => _controller.add(event));
  } else {
    if (lastDeleted != null) {
      if (basename(event.path) == basename(lastDeleted)) {
        // ignore: avoid_print
        print(red('Move from: $lastDeleted to: ${event.path}'));
        generate(event.path, show: true);
        lastDeleted = null;
      }
    }
  }
}

String lastDeleted;

void onDeleteEvent(FileSystemDeleteEvent event) {
  // ignore: avoid_print
  print('Delete:  ${event.path}');
  if (!event.isDirectory) {
    lastDeleted = event.path;
  }
}

void onMoveEvent(FileSystemMoveEvent event) {
  // var actioned = false;

  // var from = event.path;
  // var to = event.destination;

  // if (event.isDirectory) {
  //   actioned = true;
  //   await MoveCommand().importMoveDirectory(from: libRelative(from), to: libRelative(to), alreadyMoved: true);
  // } else {
  //   if (extension(from) == '.dart') {
  //     /// we don't process the move if the 'to' isn't a dart file.
  //     /// e.g. ignore a target of <lib>.dart.bak
  //     if (isDirectory(to) || isFile(to) && extension(to) == '.dart') {
  //       actioned = true;
  //       await MoveCommand()
  //           .moveFile(from: libRelative(from), to: libRelative(to), fromDirectory: false, alreadyMoved: true);
  //     }
  //   }
  // }
  // if (actioned) {
  //   print('Move: directory: ${event.isDirectory} ${event.path} destination: ${event.destination}');
  // }
}
