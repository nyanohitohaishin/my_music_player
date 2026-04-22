// ============================================================
// widgets/lyric_view.dart
// Spotify スタイル歌詞表示（左揃え・大文字・ゆったり行間）
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════

// ─── フォントサイズ ──────────────────────────────────────────
// テキストのレイアウト計算は常にこのサイズで行う（リフロー防止）。
// 非ハイライト行は Canvas transform で縮小するのみ。
const double _kBaseFontSize = 32.0;

// ─── スケール比 ──────────────────────────────────────────────
// Spotify 準拠: ハイライト行は大きく、それ以外は少し小さく。
const double _kScaleHighlighted = 1.000;                    // 32sp 相当
const double _kScaleNear        = 28.0 / _kBaseFontSize;   // ≈ 0.875（直前後）
const double _kScaleNormal      = 24.0 / _kBaseFontSize;   // ≈ 0.750（通常）

// ─── 不透明度 ────────────────────────────────────────────────
const double _kOpacityHighlighted = 1.00;
const double _kOpacityNear        = 0.55;
const double _kOpacityNormal      = 0.38;

// ─── 縦パディング ────────────────────────────────────────────
const double _kVertPadHighlighted = 16.0;
const double _kVertPadOther       =  8.0;

// ─── 左右余白 ────────────────────────────────────────────────
// Spotify は左右に余白を設けて左揃えで表示する。
const double _kHorizontalPadding = 24.0;

const Duration _kAnimDuration = Duration(milliseconds: 400);
const Curve    _kAnimCurve    = Curves.easeInOutCubic;

// ═══════════════════════════════════════════════════════════════
// LYRIC LINE STATE
// ═══════════════════════════════════════════════════════════════

enum _LyricLineState { highlighted, near, normal }

// ═══════════════════════════════════════════════════════════════
// SANITIZER
// ═══════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════

class LyricView extends ConsumerStatefulWidget {
  const LyricView({super.key});

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ItemPositionsListener _positionsListener = ItemPositionsListener.create();

  int     _lastHighlightedIndex = -1;
  String? _lastSongId;
  bool    _isInitialScroll      = true;

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
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToIndex(currentIdx));
    }

    if (lyrics.isEmpty) return const _EmptyLyricView();

    return ScrollablePositionedList.builder(
      itemCount: lyrics.length,
      itemScrollController: _scrollController,
      itemPositionsListener: _positionsListener,
      // ── Spotify の余白設計 ──────────────────────────────────
      // 上下: 画面の 35% ぶんの余白でハイライト行が中央付近に来る
      // 左右: 24px の余白で左揃えテキストに余裕を持たせる
      padding: EdgeInsets.only(
        top:    MediaQuery.of(context).size.height * 0.35,
        bottom: MediaQuery.of(context).size.height * 0.35,
        left:   _kHorizontalPadding,
        right:  _kHorizontalPadding,
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
      duration: _isInitialScroll
          ? Duration.zero
          : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
    _isInitialScroll = false;
  }

  _LyricLineState _resolveState(int index, int current) {
    if (current < 0)                   return _LyricLineState.normal;
    if (index == current)              return _LyricLineState.highlighted;
    if ((index - current).abs() == 1)  return _LyricLineState.near;
    return _LyricLineState.normal;
  }
}

// ═══════════════════════════════════════════════════════════════
// LYRIC LINE ITEM
// ═══════════════════════════════════════════════════════════════

class _LyricLineItem extends StatelessWidget {
  const _LyricLineItem({
    required this.lyricLine,
    required this.state,
    required this.onTap,
  });

  final LyricLine lyricLine;
  final _LyricLineState state;
  final VoidCallback onTap;

  double get _targetScale   => switch (state) {
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
    final text = lyricLine.text.isEmpty ? '♪' : _LyricSanitizer.clean(lyricLine.text);

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

// ═══════════════════════════════════════════════════════════════
// ANIMATED LYRIC BOX  (ImplicitlyAnimatedWidget)
// ═══════════════════════════════════════════════════════════════

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
      _scaleTween, widget.scale,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;

    _opacityTween = visitor(
      _opacityTween, widget.opacity,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;

    _vertPadTween = visitor(
      _vertPadTween, widget.verticalPadding,
      (v) => Tween<double>(begin: v as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final scale   = _scaleTween?.evaluate(animation)   ?? widget.scale;
    final opacity = _opacityTween?.evaluate(animation) ?? widget.opacity;
    final vertPad = _vertPadTween?.evaluate(animation) ?? widget.verticalPadding;

    // ハイライト行に近づくほど白いグロー影を強くする
    final glowT = ((scale - _kScaleNormal) /
        (_kScaleHighlighted - _kScaleNormal)).clamp(0.0, 1.0);

    return _LyricScaleBox(
      text: widget.text,
      scale: scale,
      color: Colors.white.withValues(alpha: opacity),
      shadows: glowT > 0.05
          ? [Shadow(
              color: Colors.white.withValues(alpha: glowT * 0.30),
              blurRadius: 16,
            )]
          : const [],
      verticalPadding: vertPad,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// _LyricScaleBox  (LeafRenderObjectWidget)
// ═══════════════════════════════════════════════════════════════

class _LyricScaleBox extends LeafRenderObjectWidget {
  const _LyricScaleBox({
    required this.text,
    required this.scale,
    required this.color,
    required this.shadows,
    required this.verticalPadding,
  });

  final String       text;
  final double       scale;
  final Color        color;
  final List<Shadow> shadows;
  final double       verticalPadding;

  @override
  _RenderLyricScaleBox createRenderObject(BuildContext context) =>
      _RenderLyricScaleBox(
        text: text, scale: scale, color: color,
        shadows: shadows, verticalPadding: verticalPadding,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderLyricScaleBox r) {
    r..text            = text
     ..scale           = scale
     ..color           = color
     ..shadows         = shadows
     ..verticalPadding = verticalPadding;
  }
}

// ═══════════════════════════════════════════════════════════════
// _RenderLyricScaleBox  (カスタム RenderBox)
//
// 【レイアウト】
//   performLayout: 常に _kBaseFontSize(32sp) でテキストを測定。
//   報告する高さ = (textH + vertPad*2) * scale
//   → scale が小さくなると Layout 上の高さも縮む（ゴーストスペース消滅）
//   → fontSizeは一切変わらないのでリフロー完全消滅
//
// 【描画】
//   paint: Canvas を scale 変換してから描画
//   → 視覚的にフォントが縮むが、折り返し判定は変わらない
//
// 【揃え: LEFT（Spotify スタイル）】
//   TextAlign.left + textWidthBasis: TextWidthBasis.parent
// ═══════════════════════════════════════════════════════════════

class _RenderLyricScaleBox extends RenderBox {
  _RenderLyricScaleBox({
    required String text,
    required double scale,
    required Color color,
    required List<Shadow> shadows,
    required double verticalPadding,
  })  : _text            = text,
        _scale           = scale,
        _color           = color,
        _shadows         = List.from(shadows),
        _verticalPadding = verticalPadding {
    _rebuildPainter();
  }

  String       _text;
  double       _scale;
  Color        _color;
  List<Shadow> _shadows;
  double       _verticalPadding;
  late TextPainter _painter;

  // ── Setters ─────────────────────────────────────

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
    _updatePainterSpan();
    // ★ バグ修正: markNeedsPaint() → markNeedsLayout()
    //
    // _rebuildPainter() / _updatePainterSpan() は TextPainter の text を更新する。
    // TextPainter.text の更新はレイアウトを無効にするため、
    // 必ず performLayout() → _painter.layout() を経由してから
    // paint() が呼ばれなければならない。
    //
    // 従来の markNeedsPaint() だとレイアウトをスキップするため、
    // paint() 内で _painter.height が 0 を返し（未レイアウト状態）、
    // rawH = 0 + padding しか確保されず全テキストが潰れてクリップされていた。
    markNeedsLayout();
  }

  set shadows(List<Shadow> v) {
    if (_listEquals(_shadows, v)) return;
    _shadows = List.from(v);
    _updatePainterSpan();
    markNeedsLayout(); // ★ 同上: markNeedsPaint() → markNeedsLayout()
  }

  set verticalPadding(double v) {
    if (_verticalPadding == v) return;
    _verticalPadding = v;
    markNeedsLayout();
  }

  // ── TextPainter 管理 ────────────────────────────
  //
  // TextPainter オブジェクト自体は一度だけ生成し（コンストラクタで）、
  // text プロパティのみを更新する。
  // これにより textAlign / textDirection / strutStyle 等の
  // イミュータブル設定が保持される。
  //
  void _rebuildPainter() {
    // 初回生成のみ呼ぶ（コンストラクタから呼ばれる）
    _painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,             // Spotify スタイル: 左揃え
      textWidthBasis: TextWidthBasis.parent, // 親幅基準で折り返す
      strutStyle: const StrutStyle(
        forceStrutHeight: true,
        leading: 0.2,
      ),
    );
    _updatePainterSpan();
  }

  void _updatePainterSpan() {
    // text プロパティの更新は内部でレイアウトを無効化する
    _painter.text = TextSpan(
      text: _text,
      style: TextStyle(
        color: _color,
        fontSize: _kBaseFontSize, // ← 絶対に変えない（リフロー防止の根拠）
        fontWeight: FontWeight.w700,
        height: 1.45,
        letterSpacing: -0.3,
        shadows: _shadows,
      ),
    );
  }

  static bool _listEquals(List<Shadow> a, List<Shadow> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ── Layout ───────────────────────────────────────

  @override
  void performLayout() {
    final maxW = constraints.maxWidth;
    // ここで必ず layout() を呼ぶことで、直前の _updatePainterSpan() による
    // 無効化が解消され、以降 _painter.height が正しい値を返す。
    _painter.layout(maxWidth: maxW);
    final rawH = _painter.height + _verticalPadding * 2;
    // Layout 高さを scale で縮める → ゴーストスペース消滅
    size = Size(maxW, rawH * _scale);
  }

  // ── Paint ────────────────────────────────────────

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_scale <= 0.0) return;

    // 安全網: 万一レイアウト未実行のまま paint が呼ばれても正しく描画する。
    // （通常は performLayout → paint の順で呼ばれるため不要だが念のため）
    if (!_painter.debugDisposed) {
      try {
        _painter.layout(maxWidth: size.width);
      } catch (_) {
        // すでにレイアウト済みの場合は何もしない
      }
    }

    final canvas  = context.canvas;
    final rawH    = _painter.height + _verticalPadding * 2;

    canvas.save();

    // スケールの起点を「左上」に固定する。
    //   X = offset.dx（左端ピン留め: 横ブレ完全防止）
    //   Y = offset.dy（上端ピン留め: シンプルで正確）
    // scale 後にテキストを _verticalPadding 分だけ下へずらして描画する。
    // rawH * _scale = size.height となるため、テキストは必ず bounds 内に収まる。
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(_scale);
    _painter.paint(canvas, Offset(0.0, _verticalPadding));

    canvas.restore();
  }

  // ── Intrinsic sizes ──────────────────────────────

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

// ═══════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════

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
            style: TextStyle(color: AppColors.textDisabled, fontSize: 16, height: 1.6),
          ),
          SizedBox(height: 8),
          Text(
            'LRCファイルを追加して歌詞を表示しましょう',
            style: TextStyle(color: AppColors.textDisabled, fontSize: 13, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}