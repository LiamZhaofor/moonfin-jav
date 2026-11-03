import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'jav_player_tools.dart';
import 'jav_settings.dart';

const _ballSize = 52.0;
const _gap = 8.0;
const _panelWidth = 300.0;
const _blue = [Color(0xFF4A90E2), Color(0xFF357ABD)];
const _swatches = ['#ffffff', '#ffeb3b', '#00e5ff', '#76ff03', '#ff80ab', '#ffa726'];

/// The draggable "字幕" ball over the video and the panel it opens: hotkeys,
/// subtitle look and timing, local / online subtitles. Sits in the player's
/// overlay stack; empty areas let pointer events through to the player.
class JavSubtitleBall extends StatefulWidget {
  const JavSubtitleBall({
    super.key,
    required this.tools,
    required this.showBall,
    this.onPanelClosed,
  });

  final JavPlayerTools tools;

  /// The ball follows the player controls; an open panel stays put.
  final bool showBall;

  /// Lets the player take keyboard focus back after the panel's text fields.
  final VoidCallback? onPanelClosed;

  @override
  State<JavSubtitleBall> createState() => _JavSubtitleBallState();
}

class _JavSubtitleBallState extends State<JavSubtitleBall> {
  bool _open = false;
  bool _searching = false;
  List<OnlineSubtitle>? _results;
  Offset? _dragPos;

  JavPlayerTools get _tools => widget.tools;
  JavPlayerSettings get _s => _tools.settings;

  void _toggle() => _open ? _close() : setState(() => _open = true);

  void _close() {
    setState(() {
      _open = false;
      _results = null;
    });
    // A focused field is torn down without a focus-change callback.
    _tools.panelFocused = false;
    widget.onPanelClosed?.call();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _results = null;
    });
    final found = await _tools.searchOnline();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = found;
    });
  }

  Offset _ballOffset(Size area) {
    final maxX = (area.width - _ballSize - 12).clamp(12.0, double.infinity);
    final maxY = (area.height - _ballSize - 12).clamp(12.0, double.infinity);
    if (_dragPos != null) {
      return Offset(_dragPos!.dx.clamp(12.0, maxX), _dragPos!.dy.clamp(12.0, maxY));
    }
    final x = _s.ballX == null ? 14.0 : _s.ballX! * area.width;
    final y = _s.ballY == null ? area.height - _ballSize - 110 : _s.ballY! * area.height;
    return Offset(x.clamp(12.0, maxX), y.clamp(12.0, maxY));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tools,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          final ball = _ballOffset(area);
          final rightHalf = ball.dx + _ballSize / 2 > area.width / 2;
          final lowerHalf = ball.dy + _ballSize / 2 > area.height / 2;
          final panelMaxHeight = math.max(
            160.0,
            lowerHalf ? ball.dy - _gap - 12 : area.height - ball.dy - _ballSize - _gap - 12,
          );
          return Stack(
            children: [
              if (_tools.accelerating)
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: Center(child: _pill('▶▶ ${_fmt(_s.accelerationRate)}x 加速中')),
                ),
              if (widget.showBall || _open)
                Positioned(
                  left: ball.dx,
                  top: ball.dy,
                  child: GestureDetector(
                    onTap: _toggle,
                    onPanUpdate: (d) => setState(() => _dragPos = (_dragPos ?? ball) + d.delta),
                    onPanEnd: (_) {
                      final p = _ballOffset(area);
                      _s.ballX = (p.dx / area.width).clamp(0.0, 1.0);
                      _s.ballY = (p.dy / area.height).clamp(0.0, 1.0);
                      setState(() => _dragPos = null);
                      unawaited(_s.save().catchError((_) {}));
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Container(
                        width: _ballSize,
                        height: _ballSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(colors: _blue),
                          boxShadow: [BoxShadow(color: _blue.first.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 4))],
                        ),
                        child: Text(_open ? '收起' : '字幕', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
              if (_open)
                Positioned(
                  left: rightHalf ? null : ball.dx.clamp(12.0, (area.width - _panelWidth - 12).clamp(12.0, double.infinity)),
                  right: rightHalf ? (area.width - ball.dx - _ballSize).clamp(12.0, double.infinity) : null,
                  top: lowerHalf ? null : ball.dy + _ballSize + _gap,
                  bottom: lowerHalf ? area.height - ball.dy + _gap : null,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (area.width - 24).clamp(220.0, _panelWidth),
                      maxHeight: panelMaxHeight,
                    ),
                    // While a field in the panel has focus the player's hotkeys
                    // stand aside, or typing "z" would speed the video up.
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      onFocusChange: (focused) => _tools.panelFocused = focused,
                      child: _panel(),
                    ),
                  ),
                ),
              Positioned(
                right: 20,
                bottom: 20,
                child: ValueListenableBuilder<String?>(
                  valueListenable: _tools.message,
                  builder: (context, text, _) => AnimatedOpacity(
                    opacity: text == null ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: text == null ? const SizedBox.shrink() : _pill(text),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pill(String text) => Container(
    constraints: const BoxConstraints(maxWidth: 320),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(6)),
    child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 13)),
  );

  Widget _panel() {
    final code = _tools.code;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF21E1E28), Color(0xF228283A)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 32, offset: Offset(0, 8))],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Theme(
            data: ThemeData.dark(useMaterial3: true),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('字幕助手', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        code.isEmpty ? '未识别番号' : code,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: code.isEmpty ? Colors.orangeAccent : Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _grid([
                  _KeyField(label: '加速键', value: _s.accelerateKey, onChanged: (v) => _tools.updateSettings((s) => s.accelerateKey = v)),
                  _KeyField(label: '快进键', value: _s.forwardKey, onChanged: (v) => _tools.updateSettings((s) => s.forwardKey = v)),
                  _KeyField(label: '倒退键', value: _s.backwardKey, onChanged: (v) => _tools.updateSettings((s) => s.backwardKey = v)),
                  _NumField(label: '加速倍率', value: _s.accelerationRate, step: 0.5, min: 0.25, max: 16,
                      onChanged: (v) => _tools.updateSettings((s) => s.accelerationRate = v)),
                  _NumField(label: '步进秒数', value: _s.skipSeconds, step: 1, min: 0.5, max: 600,
                      onChanged: (v) => _tools.updateSettings((s) => s.skipSeconds = v)),
                  _NumField(label: '字幕偏移(秒)', value: _s.subtitleOffset, step: 0.1, min: -600, max: 600,
                      onChanged: (v) => _tools.updateSettings((s) => s.subtitleOffset = v)),
                  _NumField(label: '字幕位置(%)', value: _s.subtitlePosition, step: 1, min: 0, max: 90,
                      onChanged: (v) => _tools.updateSettings((s) => s.subtitlePosition = v)),
                  _NumField(label: '字幕大小', value: _s.subtitleSize, step: 2, min: 10, max: 150,
                      onChanged: (v) => _tools.updateSettings((s) => s.subtitleSize = v)),
                ]),
                const SizedBox(height: 10),
                const Text('字幕颜色', style: TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in _swatches)
                      InkWell(
                        onTap: () => _tools.updateSettings((s) => s.subtitleColor = c),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: _color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _s.subtitleColor == c ? _blue.first : Colors.white24,
                              width: _s.subtitleColor == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 92,
                      height: 28,
                      child: _HexField(
                        value: _s.subtitleColor,
                        onChanged: (v) => _tools.updateSettings((s) => s.subtitleColor = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                const SizedBox(height: 8),
                _grid([
                  _button('本地字幕', () => unawaited(_tools.loadLocalSubtitle())),
                  _button('站点搜索', () => unawaited(_tools.openSubtitlecat())),
                  _button(_searching ? '搜索中…' : '在线搜索', _searching ? null : () => unawaited(_search())),
                  _button('清空字幕', () => unawaited(_tools.clearSubtitles())),
                  _button('保存设置', () => unawaited(_tools.saveSettings())),
                  _button('收起面板', _close),
                ], columns: 3),
                if (_results != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _results!.isEmpty ? '没有找到在线字幕' : '选择在线字幕（${_results!.length}）',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _results = null),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 16, color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results!.length,
                      itemBuilder: (context, i) {
                        final sub = _results![i];
                        return InkWell(
                          onTap: () => _tools.loadOnlineSubtitle(sub),
                          borderRadius: BorderRadius.circular(6),
                          hoverColor: _blue.first.withValues(alpha: 0.25),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                                  child: Text(sub.ext.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(sub.label, maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Widget> children, {int columns = 2}) => LayoutBuilder(
    builder: (context, c) {
      const spacing = 8.0;
      final w = (c.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: 8,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    },
  );

  Widget _button(String text, VoidCallback? onTap) => Opacity(
    opacity: onTap == null ? 0.6 : 1,
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: const LinearGradient(colors: _blue), borderRadius: BorderRadius.circular(6)),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Center(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    ),
  );
}

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(v * 10 == (v * 10).roundToDouble() ? 1 : 2);

Color _color(String hex) => Color(int.parse('ff${hex.substring(1)}', radix: 16));

InputDecoration _decoration() => InputDecoration(
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
  filled: true,
  fillColor: Colors.white.withValues(alpha: 0.12),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: const Color(0xFF6496FF).withValues(alpha: 0.3)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: const Color(0xFF6496FF).withValues(alpha: 0.7)),
  ),
  counterText: '',
);

const _fieldText = TextStyle(color: Colors.white, fontSize: 12);
const _labelText = TextStyle(color: Colors.white70, fontSize: 11);

class _KeyField extends StatefulWidget {
  const _KeyField({required this.label, required this.value, required this.onChanged});

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<_KeyField> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(widget.label, style: _labelText)),
      SizedBox(
        width: 44,
        child: TextField(
          controller: _c,
          maxLength: 1,
          textAlign: TextAlign.center,
          style: _fieldText,
          decoration: _decoration(),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))],
          onChanged: (v) {
            if (v.length == 1) widget.onChanged(v.toLowerCase());
          },
        ),
      ),
    ],
  );
}

class _NumField extends StatefulWidget {
  const _NumField({
    required this.label,
    required this.value,
    required this.step,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double step;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final _c = TextEditingController(text: _fmt(widget.value));
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _NumField old) {
    super.didUpdateWidget(old);
    // Rewrite the text only for a change that did not come from typing (the
    // +/- buttons), so a half-typed "-" or "1." is left alone.
    final typed = double.tryParse(_c.text);
    final differs = typed != null && (typed - widget.value).abs() > 1e-9;
    if (!_focus.hasFocus || differs) _c.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _bump(double delta) {
    final v = ((widget.value + delta) * 100).round() / 100;
    widget.onChanged(v.clamp(widget.min, widget.max).toDouble());
  }

  Widget _stepper(IconData icon, double delta) => InkWell(
    onTap: () => _bump(delta),
    borderRadius: BorderRadius.circular(4),
    child: Padding(padding: const EdgeInsets.all(3), child: Icon(icon, size: 14, color: Colors.white70)),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.label, style: _labelText),
      const SizedBox(height: 3),
      Row(
        children: [
          _stepper(Icons.remove, -widget.step),
          Expanded(
            child: TextField(
              controller: _c,
              focusNode: _focus,
              textAlign: TextAlign.center,
              style: _fieldText,
              decoration: _decoration(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
              onChanged: (t) {
                final v = double.tryParse(t);
                if (v != null && v >= widget.min && v <= widget.max) widget.onChanged(v);
              },
            ),
          ),
          _stepper(Icons.add, widget.step),
        ],
      ),
    ],
  );
}

class _HexField extends StatefulWidget {
  const _HexField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final _c = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _HexField old) {
    super.didUpdateWidget(old);
    final typed = normalizeHexColor(_c.text);
    if (!_focus.hasFocus || (typed != null && typed != widget.value)) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    focusNode: _focus,
    maxLength: 7,
    style: _fieldText,
    decoration: _decoration(),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]'))],
    onChanged: (t) {
      final hex = normalizeHexColor(t);
      if (hex != null) widget.onChanged(hex);
    },
  );
}
