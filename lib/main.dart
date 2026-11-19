import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RitmoApp());
}

/// Paleta: papel azulado, tinta oscura y un marcador amarillo como acento único.
class Palette {
  static const paper = Color(0xFFF2F4F8);
  static const ink = Color(0xFF172033);
  static const marker = Color(0xFFFFC933);
  static const teal = Color(0xFF1F6F78);
  static const nightBg = Color(0xFF111620);
  static const nightInk = Color(0xFFE6EAF2);
}

class RitmoApp extends StatelessWidget {
  const RitmoApp({super.key});

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: Palette.teal, brightness: b)
        .copyWith(
      primary: dark ? Palette.marker : Palette.teal,
      surface: dark ? Palette.nightBg : Palette.paper,
      onSurface: dark ? Palette.nightInk : Palette.ink,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ritmo',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const InputScreen(),
    );
  }
}

/// Ajustes y texto guardados en el dispositivo.
class Prefs {
  String text = '';
  int wpm = 250;
  int group = 1;
  double fontSize = 22;
  bool punctPause = true;

  static Future<Prefs> load() async {
    final sp = await SharedPreferences.getInstance();
    final p = Prefs();
    p.text = sp.getString('text') ?? '';
    p.wpm = sp.getInt('wpm') ?? 250;
    p.group = sp.getInt('group') ?? 1;
    p.fontSize = sp.getDouble('fontSize') ?? 22;
    p.punctPause = sp.getBool('punctPause') ?? true;
    return p;
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('text', text);
    await sp.setInt('wpm', wpm);
    await sp.setInt('group', group);
    await sp.setDouble('fontSize', fontSize);
    await sp.setBool('punctPause', punctPause);
  }
}

/// Texto dividido en palabras, recordando dónde empieza cada párrafo.
class Doc {
  final List<String> words;
  final Set<int> paraStarts;
  Doc(this.words, this.paraStarts);

  factory Doc.parse(String text) {
    final words = <String>[];
    final starts = <int>{};
    for (final para in text.trim().split(RegExp(r'\n\s*\n'))) {
      final ws = para.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (ws.isEmpty) continue;
      starts.add(words.length);
      words.addAll(ws);
    }
    return Doc(words, starts);
  }
}

String formatMinutes(double minutes) =>
    minutes < 1 ? 'menos de 1 min' : '${minutes.round()} min';

/// Control de velocidad en palabras por minuto (ppm).
class SpeedControl extends StatelessWidget {
  final int wpm;
  final ValueChanged<int> onChanged;
  const SpeedControl({super.key, required this.wpm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Velocidad',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$wpm ppm',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'Más lento',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => onChanged(math.max(60, wpm - 25)),
            ),
            Expanded(
              child: Slider(
                min: 60,
                max: 1000,
                divisions: 94,
                value: wpm.toDouble().clamp(60, 1000),
                onChanged: (v) => onChanged((v / 10).round() * 10),
              ),
            ),
            IconButton(
              tooltip: 'Más rápido',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onChanged(math.min(1000, wpm + 25)),
            ),
          ],
        ),
        Text(
          'Lectura normal: 200 a 250 ppm',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pantalla 1: pegar el texto
// ---------------------------------------------------------------------------

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final _ctrl = TextEditingController();
  Prefs? _prefs;
  int _words = 0;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onPause: _persist);
    Prefs.load().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _ctrl.text = p.text;
        _words = _count(p.text);
      });
    });
  }

  @override
  void dispose() {
    _life.dispose();
    _persist();
    _ctrl.dispose();
    super.dispose();
  }

  int _count(String t) => RegExp(r'\S+').allMatches(t).length;

  void _persist() {
    final p = _prefs;
    if (p == null) return;
    p.text = _ctrl.text;
    p.save();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final t = data?.text ?? '';
    if (t.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El portapapeles no tiene texto.')),
      );
      return;
    }
    setState(() {
      _ctrl.text = t;
      _words = _count(t);
    });
  }

  void _clear() {
    setState(() {
      _ctrl.clear();
      _words = 0;
    });
  }

  void _start() {
    _persist();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ReaderScreen(prefs: _prefs!)))
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ritmo')),
      body: SafeArea(
        child: p == null
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pega un texto largo y sigue el resaltador palabra por palabra.',
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        onChanged: (t) => setState(() => _words = _count(t)),
                        style: const TextStyle(
                            fontFamily: 'serif', fontSize: 17, height: 1.4),
                        decoration: InputDecoration(
                          hintText: 'Pega o escribe aquí tu texto…',
                          filled: true,
                          fillColor: cs.onSurface.withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.all(18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _paste,
                          icon: const Icon(Icons.content_paste_rounded),
                          label: const Text('Pegar'),
                        ),
                        if (_words > 0)
                          TextButton.icon(
                            onPressed: _clear,
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Borrar'),
                          ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('$_words palabras',
                                style: text.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            if (_words > 0)
                              Text(
                                'Unos ${formatMinutes(_words / p.wpm)} a ${p.wpm} ppm',
                                style: text.bodySmall?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.6)),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SpeedControl(
                      wpm: p.wpm,
                      onChanged: (v) {
                        setState(() => p.wpm = v);
                        p.save();
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: _words == 0 ? null : _start,
                        style: FilledButton.styleFrom(
                          backgroundColor: Palette.marker,
                          foregroundColor: Palette.ink,
                          disabledBackgroundColor:
                              cs.onSurface.withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          textStyle: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Empezar a leer'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pantalla 2: lectura con resaltador
// ---------------------------------------------------------------------------

class ReaderScreen extends StatefulWidget {
  final Prefs prefs;
  const ReaderScreen({super.key, required this.prefs});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final Doc doc = Doc.parse(widget.prefs.text);
  Prefs get p => widget.prefs;

  final GlobalKey _activeKey = GlobalKey();
  Timer? _timer;
  int index = 0;
  bool playing = false;
  bool finished = false;

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    p.save();
    super.dispose();
  }

  Duration _delay() {
    final n = doc.words.length;
    var ms = 60000 / p.wpm * p.group;
    if (p.punctPause) {
      final last = doc.words[math.min(index + p.group, n) - 1];
      if (RegExp(r'[.!?…]["”’)»]*$').hasMatch(last)) {
        ms *= 1.8;
      } else if (RegExp(r'[,;:]["”’)»]*$').hasMatch(last)) {
        ms *= 1.35;
      }
    }
    return Duration(milliseconds: ms.round());
  }

  void _schedule() {
    _timer?.cancel();
    if (!playing) return;
    _timer = Timer(_delay(), () {
      if (!mounted) return;
      final next = index + p.group;
      if (next >= doc.words.length) {
        setState(() {
          playing = false;
          finished = true;
        });
        WakelockPlus.disable();
        return;
      }
      setState(() => index = next);
      _schedule();
    });
  }

  void _toggle() {
    if (doc.words.isEmpty) return;
    setState(() {
      if (finished) {
        index = 0;
        finished = false;
      }
      playing = !playing;
    });
    if (playing) {
      WakelockPlus.enable();
      _schedule();
    } else {
      _timer?.cancel();
      WakelockPlus.disable();
    }
  }

  void _jumpTo(int i) {
    setState(() {
      index = i.clamp(0, doc.words.length - 1);
      finished = false;
    });
    if (playing) _schedule();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void update(VoidCallback change) {
            setState(change);
            setSheet(() {});
            p.save();
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Palabras por resalte',
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: [1, 2, 3]
                      .map((n) => ButtonSegment(value: n, label: Text('$n')))
                      .toList(),
                  selected: {p.group},
                  onSelectionChanged: (s) => update(() => p.group = s.first),
                ),
                const SizedBox(height: 20),
                Text('Tamaño de letra: ${p.fontSize.round()}',
                    style: Theme.of(ctx).textTheme.titleSmall),
                Slider(
                  min: 16,
                  max: 34,
                  divisions: 18,
                  value: p.fontSize,
                  onChanged: (v) => update(() => p.fontSize = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pausa breve en puntuación'),
                  subtitle: const Text('Más tiempo tras puntos y comas.'),
                  value: p.punctPause,
                  onChanged: (v) => update(() => p.punctPause = v),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pageText(ColorScheme cs, int start, int end) {
    final children = <Widget>[];
    for (var i = start; i < end; i++) {
      if (i != start && doc.paraStarts.contains(i)) {
        children.add(const SizedBox(width: double.infinity, height: 14));
      }
      final active = i >= index && i < index + p.group;
      final read = i < index;
      children.add(
        GestureDetector(
          key: i == index ? _activeKey : null,
          onTap: () => _jumpTo(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: active ? Palette.marker : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              doc.words[i],
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: p.fontSize,
                height: 1.25,
                color: active
                    ? Palette.ink
                    : cs.onSurface.withValues(alpha: read ? 0.38 : 0.92),
              ),
            ),
          ),
        ),
      );
    }
    return Wrap(runSpacing: 6, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final n = doc.words.length;
    final pageSize = math.max(30, (1100 / p.fontSize).round());
    final page = n == 0 ? 0 : index ~/ pageSize;
    final start = page * pageSize;
    final end = math.min(start + pageSize, n);
    final remaining = math.max(0, n - index) / p.wpm;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _activeKey.currentContext;
      if (c != null && c.mounted) {
        Scrollable.ensureVisible(c,
            alignment: 0.4, duration: const Duration(milliseconds: 150));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(finished ? 'Lectura completa' : 'Palabra ${index + 1} de $n'),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: SingleChildScrollView(
                key: ValueKey(page),
                padding: const EdgeInsets.only(top: 12, bottom: 24),
                child: _pageText(cs, start, end),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                  cs.onSurface.withValues(alpha: 0.06), cs.surface),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    min: 0,
                    max: math.max(1, n - 1).toDouble(),
                    value: index.clamp(0, math.max(1, n - 1)).toDouble(),
                    onChanged: (v) => _jumpTo(v.round()),
                  ),
                  Row(
                    children: [
                      Text('${n == 0 ? 0 : (index / n * 100).round()} %',
                          style: text.bodySmall),
                      const Spacer(),
                      Text('Quedan ${formatMinutes(remaining)}',
                          style: text.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 32,
                        tooltip: 'Retroceder 10 palabras',
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () => _jumpTo(index - 10),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: FilledButton(
                          onPressed: _toggle,
                          style: FilledButton.styleFrom(
                            backgroundColor: Palette.marker,
                            foregroundColor: Palette.ink,
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                          ),
                          child: Icon(
                            finished
                                ? Icons.replay_rounded
                                : playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                            size: 40,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        iconSize: 32,
                        tooltip: 'Avanzar 10 palabras',
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () => _jumpTo(index + 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SpeedControl(
                    wpm: p.wpm,
                    onChanged: (v) {
                      setState(() => p.wpm = v);
                      p.save();
                    },
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
