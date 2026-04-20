// ============================================================
// widgets/lyric_view.dart
// ============================================================
//
//   - scrollable_positioned_list: ^0.3.8
//
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

// 
// CONSTANTS
// 

/// 26sp
const double _kBaseFontSize = 26.0;

const double _kScaleHighlighted = 1.000;
const double _kScaleNear        = 19.0 / _kBaseFontSize; 
const double _kScaleNormal      = 17.0 / _kBaseFontSize; 

const double _kOpacityHighlighted = 1.00;
const double _kOpacityNear        = 0.60;
const double _kOpacityNormal      = 0.28;

const double _kVertPadHighlighted = 14.0;
const double _kVertPadOther       =  7.0;

const double _kHorizontalPadding  = 32.0;
const Duration _kAnimDuration     = Duration(milliseconds: 380);
const Curve _kAnimCurve           = Curves.easeInOutCubic;

// 
// LYRIC LINE STATE
// 

enum _LyricLineState { highlighted, near, normal }

// 
// SANITIZER
// 

abstract final class _LyricSanitizer {
  static String clean(String raw) => raw
      .replaceAll('\r\n', ' ')
      .replaceAll('\r', '')       
      .replaceAll('\n', ' ')
      .replaceAll('\u200B', '')   
      .replaceAll('\u200C', '')   
      .replaceAll('\u200D', '')   
      .replaceAll('\uFEFF', '')   
      .replaceAll('\u00A0', ' ')  
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

// 
// MAIN WIDGET
// 

class LyricView extends ConsumerStatefulWidget {
  const LyricView({super.key});

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();

  int _lastHighlightedIndex = -1;
  String? _lastSongId;
  bool _isInitialScroll = true; 

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(audioPlayerProvider);
    final notifier    = ref.read(audioPlayerProvider.notifier);
    final lyrics      = playerState.currentSong?.lyrics ?? [];
    final currentIdx  = playerState.currentLyricIndex;
    final songId      = playerState.currentSong?.id;

    if (songId != _lastSongId) {
      _lastSongId           = songId;
      _lastHighlightedIndex = -1;
      _isInitialScroll      = true;
    }

    if (currentIdx != _lastHighlightedIndex &&
        currentIdx >= 0 &&
        currentIdx < lyrics.length) {
      _lastHighlightedIndex = currentIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToIndex(currentIdx);
      });
    }

    if (lyrics.isEmpty) return const _EmptyLyricView();

    return ScrollablePositionedList.builder(
      itemCount: lyrics.length,
      itemScrollController: _scrollController,
      itemPositionsListener: _positionsListener,
      padding: EdgeInsets.symmetric(
        vertical: MediaQuery.of(context).size.height * 0.40,
        horizontal: _kHorizontalPadding,
      ),
      itemBuilder: (context, index) {
        return _LyricLineItem(
          lyricLine: lyrics[index],
          state: _resolveState(index, currentIdx),
          onTap: () => notifier.seekTo(lyrics[index].position),
        );
      },
    );
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.isAttached) return;

    _scrollController.scrollTo(
      index: index,
      alignment: 0.5, 
      duration: _isInitialScroll ? Duration.zero : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
    _isInitialScroll = false;
  }

  _LyricLineState _resolveState(int index, int current) {
    if (current < 0) return _LyricLineState.normal;
    if (index == current) return _LyricLineState.highlighted;
    if ((index - current).abs() == 1) return _LyricLineState.near;
    return _LyricLineState.normal;
  }
}

// 
// LYRIC LINE ITEM
// 

class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
    required this.lyricLine,
    required this.state,
    required this.onTap,
  });

  final LyricLine lyricLine;
  final _LyricLineState state;
  final VoidCallback onTap;

  double get _targetScale => switch (state) {
    _LyricLineState.highlighted => _kScaleHighlighted,
    _LyricLineState.near        => _kScaleNear,
    _LyricLineState.normal      => _kScaleNormal,
  };

  double get _targetOpacity => switch (state) {
    _LyricLineState.highlighted => _kOpacityHighlighted,
    _LyricLineState.near        => _kOpacityNear,
    _LyricLineState.normal      => _kOpacityNormal,
  };

  double get _targetVertPad =>
      state == _LyricLineState.highlighted ? _kVertPadHighlighted : _kVertPadOther;

  @override
  Widget build(BuildContext context) {
    final text = lyricLine.text.isEmpty ? '・' : _LyricSanitizer.clean(lyricLine.text);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _AnimatedLyricBox(
        text: text,
        scale: _targetScale,
        opacity: _targetOpacity,
        verticalPadding: _targetVertPad,
        duration: _kAnimDuration,
        curve: _kAnimCurve,
      ),
    );
  }
}

// 
// ANIMATED LYRIC BOX  (ImplicitlyAnimatedWidget)
// 

class _AnimatedLyricBox extends ImplicitlyAnimatedWidget {
  const _AnimatedLyricBox({
    required this.text,
    required this.scale,
    required this.opacity,
    required this.verticalPadding,
    required super.duration,
    super.curve = Curves.linear,
  });

  final String text;
  final double scale;
  final double opacity;
  final double verticalPadding;

  @override
  ImplicitlyAnimatedWidgetState<_AnimatedLyricBox> createState() =>
      _AnimatedLyricBoxState();
}

class _AnimatedLyricBoxState
    extends AnimatedWidgetBaseState<_AnimatedLyricBox> {
  Tween<double>? _scaleTween;
  Tween<double>? _opacityTween;
  Tween<double>? _vertPadTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _scaleTween = visitor(
      _scaleTween,
      widget.scale,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;

    _opacityTween = visitor(
      _opacityTween,
      widget.opacity,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;

    _vertPadTween = visitor(
      _vertPadTween,
      widget.verticalPadding,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final scale   = _scaleTween?.evaluate(animation)   ?? widget.scale;
    final opacity = _opacityTween?.evaluate(animation) ?? widget.opacity;
    final vertPad = _vertPadTween?.evaluate(animation) ?? widget.verticalPadding;

    final glowT = ((scale - _kScaleNormal) / (_kScaleHighlighted - _kScaleNormal))
        .clamp(0.0, 1.0);
    final shadowAlpha = glowT * 0.38;

    return _LyricScaleBox(
      text: widget.text,
      scale: scale,
      color: Colors.white.withValues(alpha: opacity),
      shadows: shadowAlpha > 0.01
          ? [Shadow(color: Colors.white.withValues(alpha: shadowAlpha), blurRadius: 14)]
          : const [],
      verticalPadding: vertPad,
    );
  }
}

// 
// _LyricScaleBox  (LeafRenderObjectWidget)
// 

class _LyricScaleBox extends LeafRenderObjectWidget {
  const _LyricScaleBox({
    required this.text,
    required this.scale,
    required this.color,
    required this.shadows,
    required this.verticalPadding,
  });

  final String text;
  final double scale;
  final Color color;
  final List<Shadow> shadows;
  final double verticalPadding;

  @override
  _RenderLyricScaleBox createRenderObject(BuildContext context) {
    return _RenderLyricScaleBox(
      text: text,
      scale: scale,
      color: color,
      shadows: shadows,
      verticalPadding: verticalPadding,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, _RenderLyricScaleBox renderObject) {
    renderObject
      ..text           = text
      ..scale          = scale
      ..color          = color
      ..shadows        = shadows
      ..verticalPadding = verticalPadding;
  }
}

// 
// _RenderLyricScaleBox  (Custom RenderBox)
// 

class _RenderLyricScaleBox extends RenderBox {
  _RenderLyricScaleBox({
    required String text,
    required double scale,
    required Color color,
    required List<Shadow> shadows,
    required double verticalPadding,
  })  : _text           = text,
        _scale          = scale,
        _color          = color,
        _shadows        = List.from(shadows),
        _verticalPadding = verticalPadding {
    _rebuildPainter();
  }

  String          _text;
  double          _scale;
  Color           _color;
  List<Shadow>    _shadows;
  double          _verticalPadding;
  late TextPainter _painter;

  set text(String v) {
    if (_text == v) return;
    _text = v;
    _rebuildPainter();
    markNeedsLayout();
  }

  set scale(double v) {
    if (_scale == v) return;
    _scale = v;
    markNeedsLayout(); 
  }

  set color(Color v) {
    if (_color == v) return;
    _color = v;
    _rebuildPainter();
    markNeedsPaint(); 
  }

  set shadows(List<Shadow> v) {
    _shadows = List.from(v);
    _rebuildPainter();
    markNeedsPaint();
  }

  set verticalPadding(double v) {
    if (_verticalPadding == v) return;
    _verticalPadding = v;
    markNeedsLayout();
  }

  void _rebuildPainter() {
    _painter = TextPainter(
      text: TextSpan(
        text: _text,
        style: TextStyle(
          color: _color,
          fontSize: _kBaseFontSize, 
          fontWeight: FontWeight.w700,
          height: 1.55,
          letterSpacing: 0.15,
          shadows: _shadows,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textWidthBasis: TextWidthBasis.parent, 
      strutStyle: const StrutStyle(forceStrutHeight: true, leading: 0.3),
    );
  }

  @override
  void performLayout() {
    final maxW = constraints.maxWidth;
    _painter.layout(maxWidth: maxW);
    final rawH = _painter.height + _verticalPadding * 2;
    size = Size(maxW, rawH * _scale);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_scale <= 0.0) return;

    final canvas = context.canvas;
    final rawH   = _painter.height + _verticalPadding * 2;

    canvas.save();

    canvas.translate(
      offset.dx + size.width / 2,
      offset.dy + size.height / 2,
    );

    canvas.scale(_scale);

    canvas.translate(-size.width / 2, -rawH / 2);

    _painter.paint(canvas, Offset(0.0, _verticalPadding));

    canvas.restore();
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _painter.layout(maxWidth: width.isFinite ? width : 9999.0);
    return (_painter.height + _verticalPadding * 2) * _scale;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double computeMinIntrinsicWidth(double height) => 0.0;

  @override
  double computeMaxIntrinsicWidth(double height) => _kBaseFontSize * 20;

  @override
  bool hitTestSelf(Offset position) => true;
}

// 
// EMPTY STATE
// 

class _EmptyLyricView extends StatelessWidget {
  const _EmptyLyricView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lyrics_outlined, color: AppColors.textDisabled, size: 48),
          SizedBox(height: 16),
          Text(
            '歌詞がありません',
            style: TextStyle(
              color: AppColors.textDisabled,
              fontSize: 16,
              height: 1.6,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'LRCファイルを追加して歌詞を表示しましょう',
            style: TextStyle(
              color: AppColors.textDisabled,
              fontSize: 13,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
