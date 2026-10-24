import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Kich hoat phat nen: khoa man hinh van phat, hien dieu khien tren
  // man hinh khoa / Control Center / Dynamic Island (iOS) va
  // thong bao media (Android). PHAI goi truoc runApp.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.vominhnguyen.ipodclassic.channel.audio',
    androidNotificationChannelName: 'iPod Classic Playback',
    androidNotificationOngoing: true,
    androidShowNotificationBadge: true,
    androidStopForegroundOnPause: true,
  );
  runApp(const IPodApp());
}

class IPodApp extends StatelessWidget {
  const IPodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iPod Classic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Helvetica', useMaterial3: true),
      home: const IPodHomePage(),
    );
  }
}

enum MediaKind { audio, video, photo }

class MediaFile {
  final String name;
  final String path;
  final MediaKind kind;
  const MediaFile({required this.name, required this.path, required this.kind});
}

MediaKind? kindFromPath(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.mp3') || p.endsWith('.m4a') || p.endsWith('.aac') ||
      p.endsWith('.wav') || p.endsWith('.flac') || p.endsWith('.ogg')) {
    return MediaKind.audio;
  }
  if (p.endsWith('.mp4') || p.endsWith('.mov') || p.endsWith('.m4v') ||
      p.endsWith('.mkv') || p.endsWith('.webm')) {
    return MediaKind.video;
  }
  if (p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png') ||
      p.endsWith('.gif') || p.endsWith('.webp') || p.endsWith('.heic')) {
    return MediaKind.photo;
  }
  return null;
}

enum AppScreen { menu, music, videos, photos, nowPlaying, videoPlayer, photoViewer }

class IPodHomePage extends StatefulWidget {
  const IPodHomePage({super.key});

  @override
  State<IPodHomePage> createState() => _IPodHomePageState();
}

class _IPodHomePageState extends State<IPodHomePage> {
  final AudioPlayer _player = AudioPlayer();
  VideoPlayerController? _video;

  final List<MediaFile> _all = [];
  AppScreen _screen = AppScreen.menu;
  int _selected = 0; // dong dang duoc chon trong menu / danh sach
  int _currentAudio = -1;
  int _currentPhoto = 0;
  bool _videoReady = false;

  static const List<String> _menuItems = [
    'Music',
    'Videos',
    'Photos',
    'Now Playing',
    'Import Media...',
  ];

  List<MediaFile> get _audios =>
      _all.where((e) => e.kind == MediaKind.audio).toList();
  List<MediaFile> get _videos =>
      _all.where((e) => e.kind == MediaKind.video).toList();
  List<MediaFile> get _photos =>
      _all.where((e) => e.kind == MediaKind.photo).toList();

  @override
  void initState() {
    super.initState();
    _player.currentIndexStream.listen((i) {
      if (i != null && mounted) setState(() => _currentAudio = i);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _video?.dispose();
    super.dispose();
  }

  // ---------------- Chon file ----------------
  Future<void> _importMedia() async {
    // file_picker v13: pickFiles la ham static, tra ve List<PlatformFile>;
    // nguoi dung huy chon -> danh sach rong (khong con tra null nhu v8).
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg',
        'mp4', 'mov', 'm4v', 'webm',
        'jpg', 'jpeg', 'png', 'gif', 'webp',
      ],
    );
    if (files.isEmpty) return;
    int added = 0;
    for (final f in files) {
      final path = f.path;
      if (path == null) continue;
      final kind = kindFromPath(path);
      if (kind == null) continue;
      if (_all.any((e) => e.path == path)) continue;
      _all.add(MediaFile(name: f.name, path: path, kind: kind));
      added++;
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Da them $added file. Tong: ${_all.length} file.')),
    );
  }

  // ---------------- Phat nhac ----------------
  Future<void> _playAudioAt(int index) async {
    if (_audios.isEmpty) return;
    await _video?.pause();
    final sources = _audios
        .map((e) => AudioSource.file(
              e.path,
              tag: MediaItem(
                id: e.path,
                title: e.name,
                album: 'iPod Classic',
                artist: 'My Library',
              ),
            ))
        .toList();
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: index,
      initialPosition: Duration.zero,
    );
    setState(() {
      _currentAudio = index;
      _screen = AppScreen.nowPlaying;
      _selected = 0;
    });
    await _player.play();
  }

  // ---------------- Phat video ----------------
  Future<void> _playVideoAt(int index) async {
    if (_videos.isEmpty) return;
    await _player.pause();
    await _video?.dispose();
    setState(() => _videoReady = false);
    final controller = VideoPlayerController.file(File(_videos[index].path));
    _video = controller;
    await controller.initialize();
    await controller.play();
    if (!mounted) return;
    setState(() {
      _videoReady = true;
      _screen = AppScreen.videoPlayer;
      _selected = 0;
    });
  }

  // ---------------- Dieu huong bang num xoay ----------------
  int get _itemCount {
    switch (_screen) {
      case AppScreen.menu:
        return _menuItems.length;
      case AppScreen.music:
        return _audios.length;
      case AppScreen.videos:
        return _videos.length;
      case AppScreen.photos:
        return _photos.length;
      case AppScreen.photoViewer:
        return _photos.length;
      default:
        return 0;
    }
  }

  void _onRotate(int direction) {
    if (_screen == AppScreen.photoViewer) {
      if (_photos.isEmpty) return;
      setState(() {
        _currentPhoto =
            (_currentPhoto + direction) % _photos.length;
        if (_currentPhoto < 0) _currentPhoto += _photos.length;
      });
      return;
    }
    final count = _itemCount;
    if (count == 0) return;
    setState(() {
      _selected = (_selected + direction) % count;
      if (_selected < 0) _selected += count;
    });
  }

  void _goTo(AppScreen s) => setState(() {
        _screen = s;
        _selected = 0;
      });

  Future<void> _onCenter() async {
    switch (_screen) {
      case AppScreen.menu:
        switch (_selected) {
          case 0:
            _goTo(AppScreen.music);
            break;
          case 1:
            _goTo(AppScreen.videos);
            break;
          case 2:
            _goTo(AppScreen.photos);
            break;
          case 3:
            _goTo(AppScreen.nowPlaying);
            break;
          case 4:
            await _importMedia();
            break;
        }
        break;
      case AppScreen.music:
        if (_audios.isNotEmpty) await _playAudioAt(_selected);
        break;
      case AppScreen.videos:
        if (_videos.isNotEmpty) await _playVideoAt(_selected);
        break;
      case AppScreen.photos:
        if (_photos.isNotEmpty) {
          setState(() {
            _currentPhoto = _selected;
            _screen = AppScreen.photoViewer;
          });
        }
        break;
      case AppScreen.nowPlaying:
        await _toggleAudio();
        break;
      case AppScreen.videoPlayer:
        await _toggleVideo();
        break;
      case AppScreen.photoViewer:
        _goTo(AppScreen.photos);
        break;
    }
  }

  void _onMenuButton() {
    if (_screen == AppScreen.videoPlayer) _video?.pause();
    _goTo(AppScreen.menu);
  }

  Future<void> _toggleAudio() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_currentAudio < 0 && _audios.isNotEmpty) {
        await _playAudioAt(0);
        return;
      }
      await _player.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleVideo() async {
    final v = _video;
    if (v == null) return;
    if (v.value.isPlaying) {
      await v.pause();
    } else {
      await v.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _onPlayPause() async {
    if (_screen == AppScreen.videoPlayer) {
      await _toggleVideo();
    } else {
      await _toggleAudio();
    }
  }

  Future<void> _onNext() async {
    if (_screen == AppScreen.nowPlaying || _screen == AppScreen.menu) {
      if (_player.hasNext) await _player.seekToNext();
    } else if (_screen == AppScreen.photoViewer) {
      _onRotate(1);
    } else {
      _onRotate(1);
    }
  }

  Future<void> _onPrevious() async {
    if (_screen == AppScreen.nowPlaying || _screen == AppScreen.menu) {
      if (_player.hasPrevious) await _player.seekToPrevious();
    } else if (_screen == AppScreen.photoViewer) {
      _onRotate(-1);
    } else {
      _onRotate(-1);
    }
  }

  // ---------------- Giao dien ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2B2B2E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 350,
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF7F7F7), Color(0xFFD9D9DE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(38),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 14)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildScreen(),
                  const SizedBox(height: 26),
                  ClickWheel(
                    isPlaying: _screen == AppScreen.videoPlayer
                        ? (_video?.value.isPlaying ?? false)
                        : _player.playing,
                    onRotate: _onRotate,
                    onCenter: () => _onCenter(),
                    onMenu: _onMenuButton,
                    onNext: () => _onNext(),
                    onPrevious: () => _onPrevious(),
                    onPlayPause: () => _onPlayPause(),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Xoay vong tron de chon - cham giua de OK - MENU de quay lai',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScreen() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(7),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(color: const Color(0xFFF4F4EE), child: _screenContent()),
      ),
    );
  }

  Widget _screenContent() {
    switch (_screen) {
      case AppScreen.menu:
        return _listView(
          title: 'iPod',
          items: _menuItems,
          counts: [
            '${_audios.length}',
            '${_videos.length}',
            '${_photos.length}',
            _currentAudio >= 0 && _audios.isNotEmpty
                ? _audios[_currentAudio].name
                : '-',
            '${_all.length} files',
          ],
        );
      case AppScreen.music:
        return _listView(
          title: 'Music',
          items: _audios.map((e) => e.name).toList(),
          emptyText: 'Chua co nhac.\nVao MENU > Import Media... de them.',
        );
      case AppScreen.videos:
        return _listView(
          title: 'Videos',
          items: _videos.map((e) => e.name).toList(),
          emptyText: 'Chua co video.\nVao MENU > Import Media... de them.',
        );
      case AppScreen.photos:
        return _listView(
          title: 'Photos',
          items: _photos.map((e) => e.name).toList(),
          emptyText: 'Chua co anh.\nVao MENU > Import Media... de them.',
        );
      case AppScreen.nowPlaying:
        return _nowPlayingView();
      case AppScreen.videoPlayer:
        return _videoView();
      case AppScreen.photoViewer:
        return _photoView();
    }
  }

  Widget _listView({
    required String title,
    required List<String> items,
    List<String>? counts,
    String emptyText = '',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7FB2D9), Color(0xFF3E7CB1)],
            ),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
        if (items.isEmpty)
          Expanded(
            child: Center(
              child: Text(emptyText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final selected = i == _selected;
                return Container(
                  color: selected ? const Color(0xFF2E7CD6) : Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          items[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      if (counts != null && i < counts.length)
                        Text(
                          counts[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: selected ? Colors.white70 : Colors.black45,
                          ),
                        ),
                      Icon(Icons.chevron_right,
                          size: 16,
                          color: selected ? Colors.white : Colors.black38),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _nowPlayingView() {
    if (_currentAudio < 0 || _audios.isEmpty) {
      return const Center(
        child: Text('Chua phat bai nao.\nVao Music, chon mot bai hat.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black54)),
      );
    }
    final track = _audios[_currentAudio];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Now Playing',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Text(track.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Text('My Library - iPod Classic',
              style: TextStyle(fontSize: 13, color: Colors.black54)),
          const Spacer(),
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              final dur = _player.duration ?? Duration.zero;
              final maxMs = dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds;
              return Column(
                children: [
                  Slider(
                    value: pos.inMilliseconds.clamp(0, maxMs).toDouble(),
                    max: maxMs.toDouble(),
                    onChanged: (v) =>
                        _player.seek(Duration(milliseconds: v.toInt())),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(pos), style: const TextStyle(fontSize: 12)),
                      Text(_fmt(dur), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            _player.playing ? 'Dang phat - tam dung bang nut duoi cua num xoay' : 'Da tam dung',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _videoView() {
    final v = _video;
    if (v == null || !_videoReady) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: v.value.aspectRatio == 0 ? 16 / 9 : v.value.aspectRatio,
          child: VideoPlayer(v),
        ),
      ),
    );
  }

  Widget _photoView() {
    if (_photos.isEmpty) {
      return const Center(child: Text('Chua co anh'));
    }
    final photo = _photos[_currentPhoto];
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          Expanded(child: Image.file(File(photo.path), fit: BoxFit.contain)),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              '${_currentPhoto + 1}/${_photos.length} - ${photo.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ---------------- Click Wheel (num xoay iPod Classic) ----------------
class ClickWheel extends StatefulWidget {
  final bool isPlaying;
  final void Function(int direction) onRotate;
  final VoidCallback onCenter;
  final VoidCallback onMenu;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;

  const ClickWheel({
    super.key,
    required this.isPlaying,
    required this.onRotate,
    required this.onCenter,
    required this.onMenu,
    required this.onNext,
    required this.onPrevious,
    required this.onPlayPause,
  });

  @override
  State<ClickWheel> createState() => _ClickWheelState();
}

class _ClickWheelState extends State<ClickWheel> {
  double? _lastAngle;
  double _accumulated = 0;

  double _angleOf(Offset p, Size s) =>
      math.atan2(p.dy - s.height / 2, p.dx - s.width / 2);

  void _handlePan(DragUpdateDetails d, Size s) {
    final a = _angleOf(d.localPosition, s);
    if (_lastAngle != null) {
      var delta = a - _lastAngle!;
      while (delta > math.pi) {
        delta -= 2 * math.pi;
      }
      while (delta < -math.pi) {
        delta += 2 * math.pi;
      }
      _accumulated += delta;
      const threshold = 0.35; // ~20 do thi nhay 1 muc
      if (_accumulated.abs() >= threshold) {
        widget.onRotate(_accumulated > 0 ? 1 : -1);
        _accumulated = 0;
      }
    }
    _lastAngle = a;
  }

  void _handleTap(TapUpDetails d, Size s) {
    final dx = d.localPosition.dx - s.width / 2;
    final dy = d.localPosition.dy - s.height / 2;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 52) {
      widget.onCenter();
      return;
    }
    final deg = math.atan2(dy, dx) * 180 / math.pi; // -180..180, 0 = phai
    if (deg >= -135 && deg < -45) {
      widget.onMenu(); // tren
    } else if (deg >= -45 && deg < 45) {
      widget.onNext(); // phai
    } else if (deg >= 45 && deg < 135) {
      widget.onPlayPause(); // duoi
    } else {
      widget.onPrevious(); // trai
    }
  }

  @override
  Widget build(BuildContext context) {
    const size = 272.0;
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          _lastAngle = _angleOf(d.localPosition, const Size(size, size));
          _accumulated = 0;
        },
        onPanUpdate: (d) => _handlePan(d, const Size(size, size)),
        onPanEnd: (_) => _lastAngle = null,
        onTapUp: (d) => _handleTap(d, const Size(size, size)),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.white, Color(0xFFE3E3E8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned(
                top: 16,
                child: Text('MENU',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF55555A),
                        fontSize: 15)),
              ),
              const Positioned(
                left: 14,
                child: Icon(Icons.skip_previous, color: Color(0xFF55555A)),
              ),
              const Positioned(
                right: 14,
                child: Icon(Icons.skip_next, color: Color(0xFF55555A)),
              ),
              Positioned(
                bottom: 14,
                child: Icon(
                  widget.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: const Color(0xFF55555A),
                ),
              ),
              Container(
                width: 104,
                height: 104,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFF2F2F4), Color(0xFFD6D6DB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
