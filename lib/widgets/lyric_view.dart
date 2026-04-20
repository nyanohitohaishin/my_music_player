// ============================================================
// widgets/lyric_view.dart
// ============================================================
//
//   - scrollable_positioned_list: ^0.3.8
//
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/lyric_line.dart';
import '../providers/audio_player_provider.dart';
import '../theme/app_theme.dart';

// 
// CONSTANTS
// 

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

  @override
  Widget build(BuildContext context) {
    final text = lyricLine.text.isEmpty ? '・' : _LyricSanitizer.clean(lyricLine.text);

    final isHigh = state == _LyricLineState.highlighted;
    final isNear = state == _LyricLineState.near;

    // Spotifyのような文字サイズと不透明度の設定
    final fontSize = isHigh ? 28.0 : (isNear ? 20.0 : 18.0);
    final opacity  = isHigh ? 1.0  : (isNear ? 0.6  : 0.3);
    final vertPad  = isHigh ? 14.0 : 8.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedPadding(
        duration: _kAnimDuration,
        curve: _kAnimCurve,
        padding: EdgeInsets.symmetric(vertical: vertPad),
        child: AnimatedDefaultTextStyle(
          duration: _kAnimDuration,
          curve: _kAnimCurve,
          style: TextStyle(
            color: Colors.white.withValues(alpha: opacity),
            fontSize: fontSize,
            fontWeight: FontWeight.w800, // より力強い太字
            height: 1.4, // 行間
            letterSpacing: 0.5,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              text,
              textAlign: TextAlign.left, // 画像の通りの左揃え
              softWrap: true,
              overflow: TextOverflow.visible,
            ),
          ),
        ),
      ),
    );
  }
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
