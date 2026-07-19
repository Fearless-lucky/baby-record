import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/utils/date_utils.dart';

/// 全屏视频播放页。
class VideoPlayerPage extends StatefulWidget {
  final String filePath;
  final String? title;

  const VideoPlayerPage({super.key, required this.filePath, this.title});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _error = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.file(File(widget.filePath));
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _controller = c);
      await c.play();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = AppDateUtils.two(d.inMinutes.remainder(60));
    final s = AppDateUtils.two(d.inSeconds.remainder(60));
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _error
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: Colors.white54, size: 48),
                        SizedBox(height: 12),
                        Text('视频无法播放',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : c == null
                      ? const CircularProgressIndicator(color: Colors.white70)
                      : AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: VideoPlayer(c),
                        ),
            ),
            if (_showControls) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      if (widget.title != null)
                        Expanded(
                          child: Text(
                            widget.title!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (c != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                c.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                              onPressed: () {
                                setState(() {
                                  c.value.isPlaying ? c.pause() : c.play();
                                });
                              },
                            ),
                            ValueListenableBuilder(
                              valueListenable: c,
                              builder: (_, VideoPlayerValue v, __) => Text(
                                '${_fmt(v.position)} / ${_fmt(v.duration)}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: VideoProgressIndicator(
                                c,
                                allowScrubbing: true,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                colors: VideoProgressColors(
                                  playedColor: Colors.white,
                                  bufferedColor:
                                      Colors.white.withValues(alpha: 0.3),
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
