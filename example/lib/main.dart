import 'package:flutter/material.dart';
import 'package:smart_capture_kit/smart_capture_kit.dart';

void main() => runApp(const SmartCaptureDemoApp());

class SmartCaptureDemoApp extends StatelessWidget {
  const SmartCaptureDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'smart_capture_kit demo',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D5AFE),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SmartCaptureLabels _labels = SmartCaptureLabels.english();

  bool get _isArabic =>
      _labels.textDirection == SmartCaptureTextDirection.rtl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('smart_capture_kit'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _labels = _isArabic
                  ? SmartCaptureLabels.english()
                  : SmartCaptureLabels.arabic();
            }),
            child: Text(_isArabic ? 'EN' : 'ع'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _PhaseBanner(),
          const SizedBox(height: 16),
          _Section(
            title: 'Capture flows',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _capturePortrait,
                  icon: const Icon(Icons.person_outline),
                  label: Text(_labels.portraitTitle),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _captureDocument,
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(_labels.documentFrontTitle),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _GuidanceLabelsSection(),
          const SizedBox(height: 16),
          const _ProfilesSection(),
          const SizedBox(height: 16),
          const _NormalizationSection(),
        ],
      ),
    );
  }

  Future<void> _capturePortrait() async {
    try {
      final result = await SmartCapture.capturePortrait(
        context,
        options: PortraitCaptureOptions(labels: _labels),
      );
      if (result == null || !mounted) return; // user cancelled

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Portrait captured'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.file(
                  (result.croppedImage ?? result.originalImage).file,
                  height: 160,
                ),
                const SizedBox(height: 12),
                Text('faces detected: ${result.faceCount}'),
                Text(
                  'continued despite failures: '
                  '${result.userContinuedDespiteFailures}',
                ),
                const Divider(),
                for (final check in result.qualityReport.checks)
                  Text('${check.id.name}: ${check.outcome.name}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

      // The host owns these files the moment the result is returned; the
      // example doesn't keep them, so it disposes them right after showing
      // this summary.
      await result.dispose();
    } on SmartCaptureException catch (e) {
      if (!mounted) return;
      await _showError(e);
    }
  }

  Future<void> _captureDocument() async {
    try {
      final result = await SmartCapture.captureDocument(
        context,
        options: DocumentCaptureOptions(
          documentProfile: 'jo_national_id',
          sides: DocumentSides.frontAndBack,
          labels: _labels,
        ),
      );
      if (result == null || !mounted) return; // user cancelled

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Document captured'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final side in [result.front, result.back])
                  if (side != null) ...[
                    Text(
                      side.side.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Image.file(
                      (side.rectifiedImage ?? side.originalImage).file,
                      height: 120,
                    ),
                    Text('rectified: ${side.rectifiedImage != null}'),
                    Text(
                      'continued despite failures: '
                      '${side.userContinuedDespiteFailures}',
                    ),
                    for (final check in side.qualityReport.checks)
                      Text('${check.id.name}: ${check.outcome.name}'),
                    if (side.ocr != null)
                      Text(
                        'OCR (${side.ocr!.engine.displayName}): '
                        '${side.ocr!.lines.length} lines, scripts '
                        '${side.ocr!.requestedScripts.map((s) => s.name).join('+')}',
                      ),
                    const Divider(),
                  ],
                if (result.ocrError != null)
                  Text('OCR error: ${result.ocrError!.code.name} — '
                      '${result.ocrError!.message}'),
                // Field values can be personal data: shown on screen here
                // for the demo, never logged.
                for (final field in result.fields?.fields ?? const <ExtractedField>[])
                  Text('${field.id.name}: ${field.status.name}'
                      '${field.value == null ? '' : ' — ${field.value}'}'),
                if (result.fields != null && result.fields!.fields.isEmpty)
                  Text('Profile "${result.profileId}" maps no fields yet '
                      '(raw text only).'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

      // As with the portrait result: the example keeps nothing, so it
      // deletes every document image as soon as the summary closes.
      await result.dispose();
    } on SmartCaptureException catch (e) {
      if (!mounted) return;
      await _showError(e);
    }
  }

  Future<void> _showError(SmartCaptureException e) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(e.code.name),
          content: Text('${e.message}\n\nretryable: ${e.isRetryable}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phase 7 — capture and on-device OCR are live',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Portrait capture runs camera + on-device face detection. '
              'Document capture detects the card boundary live, '
              'perspective-corrects each side, runs quality checks, then '
              'reads the text on-device (Apple Vision on iOS; ML Kit, Latin '
              'only, on Android). The Jordan profile maps no fields yet.',
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceLabelsSection extends StatelessWidget {
  const _GuidanceLabelsSection();

  @override
  Widget build(BuildContext context) {
    final english = SmartCaptureLabels.english();
    final arabic = SmartCaptureLabels.arabic();
    const shown = [
      CaptureGuidance.noFaceDetected,
      CaptureGuidance.moveCloser,
      CaptureGuidance.lookStraightAhead,
      CaptureGuidance.fitAllCornersInFrame,
      CaptureGuidance.avoidGlare,
    ];
    return _Section(
      title: 'Guidance is emitted as enums, not strings',
      child: Column(
        children: [
          for (final g in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      g.name,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(flex: 3, child: Text(english.guidanceText(g))),
                  Expanded(
                    flex: 3,
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(arabic.guidanceText(g)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfilesSection extends StatelessWidget {
  const _ProfilesSection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Registered document profiles',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in DocumentProfileRegistry.all) ...[
            Text(
              '${p.displayName}  (${p.id})',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              'aspect ${p.aspectRatio.toStringAsFixed(3)} · '
              'scripts ${p.expectedScripts.map((s) => s.name).join(", ")} · '
              '${p.extractionSupport.name}',
              style: const TextStyle(fontSize: 12),
            ),
            if (p.notes != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Text(
                  p.notes!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _NormalizationSection extends StatefulWidget {
  const _NormalizationSection();

  @override
  State<_NormalizationSection> createState() => _NormalizationSectionState();
}

class _NormalizationSectionState extends State<_NormalizationSection> {
  final _controller = TextEditingController(text: 'رقم ١٢٣٤٥٦٧٨٩ إبراهيم');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = _controller.text;
    return _Section(
      title: 'Normalization is derivation only',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Simulated raw OCR text',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _kv('raw (preserved)', raw),
          _kv('western digits', toWesternDigits(raw)),
          _kv('comparison key', normalizeForComparison(raw)),
          _kv('digit runs', extractDigitRuns(raw).join(', ')),
          _kv('contains Arabic', '${containsArabic(raw)}'),
          _kv('contains Latin', '${containsLatin(raw)}'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                k,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}
