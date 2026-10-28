import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
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

// Mot album trong Cover Flow: gom cac bai cung ten album, lay anh
// cua bai dau tien co anh, bam giua se phat tu bai dau tien do.
class _Album {
  final String name;
  final String artist;
  final Uint8List? art;
  final int firstIndex;
  const _Album(
      {required this.name,
      required this.artist,
      this.art,
      required this.firstIndex});
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

enum AppScreen { menu, music, videos, photos, nowPlaying, videoPlayer, photoViewer, coverFlow }

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

  // ---------------- Anh bia nhung trong file nhac ----------------
  // Chi DOC anh co san trong file (ID3/APIC, iTunes covr, Vorbis
  // PICTURE...), KHONG sua file nhac, KHONG gan them anh cho file.
  // Anh doc duoc se cache trong RAM + ghi ra file tam rieng de lam
  // anh bia man hinh khoa/thong bao (qua MediaItem.artUri).
  // File khong co anh -> tra null, giao dien giu nguyen ban chu.
  final Map<String, Uint8List> _artBytesCache = {};
  final Map<String, Uri> _artUriCache = {};

  // Album / nghe si doc tu tag file nhac (cung luc doc anh bia).
  final Map<String, String> _albumCache = {};
  final Map<String, String> _artistCache = {};
  // Cover Flow: album dang chon + bo dieu khien luot ngang.
  int _coverIndex = 0;
  final PageController _coverController =
      PageController(viewportFraction: 0.55);

  Future<Uint8List?> _artworkBytesFor(String path) async {
    if (_artBytesCache.containsKey(path)) return _artBytesCache[path];
    try {
      final metadata = await MetadataRetriever.fromFile(File(path));
      final bytes = metadata.albumArt;
      if (bytes != null && bytes.isNotEmpty) {
        _artBytesCache[path] = bytes;
        return bytes;
      }
    } catch (_) {
      // File khong co anh / dinh dang khong doc duoc -> khong co anh bia.
    }
    return null;
  }

  // Doc tag album/nghe si/anh bia trong 1 lan doc file (cung goi
  // MetadataRetriever nhu khi doc anh bia). Chi DOC, khong sua file.
  // File khong co tag -> album/nghe si mac dinh 'Unknown ...'.
  Future<void> _readAudioTags(String path) async {
    if (_albumCache.containsKey(path)) return;
    try {
      final metadata = await MetadataRetriever.fromFile(File(path));
      final album = metadata.albumName?.trim();
      _albumCache[path] =
          (album == null || album.isEmpty) ? 'Unknown Album' : album;
      var artist = metadata.albumArtistName?.trim() ?? '';
      final artists = metadata.trackArtistNames;
      if (artist.isEmpty && artists != null && artists.isNotEmpty) {
        artist = artists.join(', ');
      }
      _artistCache[path] = artist.isEmpty ? 'Unknown Artist' : artist;
      final bytes = metadata.albumArt;
      if (bytes != null && bytes.isNotEmpty) _artBytesCache[path] = bytes;
    } catch (_) {
      _albumCache[path] = 'Unknown Album';
      _artistCache[path] = 'Unknown Artist';
    }
  }

  int _stableHash(String s) {
    var h = 5381;
    for (final c in s.codeUnits) {
      h = ((h << 5) + h + c) & 0x7fffffff;
    }
    return h;
  }

  Future<Uri?> _artUriFor(String path, Uint8List bytes) async {
    if (_artUriCache.containsKey(path)) return _artUriCache[path];
    try {
      // Doan dinh dang anh theo magic bytes de dat dung duoi file.
      var ext = 'jpg';
      if (bytes.length >= 4 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        ext = 'png';
      }
      final file = File(
          '${Directory.systemTemp.path}/ipod_art_${_stableHash(path)}.$ext');
      if (!await file.exists()) {
        await file.writeAsBytes(bytes, flush: true);
      }
      final uri = Uri.file(file.path);
      _artUriCache[path] = uri;
      return uri;
    } catch (_) {
      return null;
    }
  }

  static const List<String> _menuItems = [
    'Music',
    'Videos',
    'Photos',
    'Now Playing',
    'Import Media...',
    'Cover Flow',
  ];

  List<MediaFile> get _audios =>
      _all.where((e) => e.kind == MediaKind.audio).toList();
  List<MediaFile> get _videos =>
      _all.where((e) => e.kind == MediaKind.video).toList();
  List<MediaFile> get _photos =>
      _all.where((e) => e.kind == MediaKind.photo).toList();

  // Gom bai hat thanh album theo ten album trong tag. Bai nao
  // chua doc tag thi tam gom vao 'Unknown Album' (doc xong se tach
  // ra dung album khi vao lai Cover Flow).
  List<_Album> get _albums {
    final List<_Album> out = [];
    for (var i = 0; i < _audios.length; i++) {
      final track = _audios[i];
      final name = _albumCache[track.path] ?? 'Unknown Album';
      final idx = out.indexWhere((a) => a.name == name);
      if (idx >= 0) {
        final old = out[idx];
        if (old.art == null) {
          final art = _artBytesCache[track.path];
          if (art != null) {
            out[idx] = _Album(
                name: old.name,
                artist: old.artist,
                art: art,
                firstIndex: old.firstIndex);
          }
        }
      } else {
        out.add(_Album(
          name: name,
          artist: _artistCache[track.path] ?? 'Unknown Artist',
          art: _artBytesCache[track.path],
          firstIndex: i,
        ));
      }
    }
    return out;
  }

  int get _safeCoverIndex {
    final albums = _albums;
    if (albums.isEmpty) return 0;
    if (_coverIndex < 0) return 0;
    if (_coverIndex >= albums.length) return albums.length - 1;
    return _coverIndex;
  }

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
    _coverController.dispose();
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
    // Doc anh bia nhung san trong tung file truoc khi phat.
    // Bai nao co anh: anh hien ca tren man hinh Now Playing lan
    // tren man hinh khoa/thong bao (qua artUri, giong Spotify).
    // Bai khong co anh: man hinh khoa dung mac dinh he thong.
    // (Da bo cach ve anh not nhac bang dart:ui: doan code do loi
    // bien dich 3 lan lien tiep, khong dang giu lai khi can xong
    // trong ngay; o not nhac trong app thi van co.)
    // Doc lan dau hoi cham mot chut (doc header file), cac lan
    // sau lay tu cache nen khong doc lai.
    final Map<String, Uri?> artUris = {};
    for (final track in _audios) {
      // Doc ca tag album/nghe si lan anh bia (cung 1 lan doc file).
      await _readAudioTags(track.path);
      final bytes = _artBytesCache[track.path];
      artUris[track.path] =
          bytes == null ? null : await _artUriFor(track.path, bytes);
    }
    final sources = _audios
        .map((e) => AudioSource.file(
              e.path,
              tag: MediaItem(
                id: e.path,
                title: e.name,
                album: _albumCache[e.path] ?? 'iPod Classic',
                artist: _artistCache[e.path] ?? 'My Library',
                artUri: artUris[e.path],
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
    if (_screen == AppScreen.coverFlow) {
      final albums = _albums;
      if (albums.isEmpty) return;
      setState(() {
        _coverIndex = (_coverIndex + direction) % albums.length;
        if (_coverIndex < 0) _coverIndex += albums.length;
      });
      if (_coverController.hasClients) {
        _coverController.animateToPage(_coverIndex,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
      return;
    }
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
          case 5:
            // Doc tag truoc de Cover Flow gom dung album (lan dau
            // hoi cham mot chut vi doc header tung file).
            for (final track in _audios) {
              await _readAudioTags(track.path);
            }
            if (!mounted) return;
            _goTo(AppScreen.coverFlow);
            setState(() => _coverIndex = 0);
            if (_coverController.hasClients) {
              _coverController.jumpToPage(0);
            }
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
      case AppScreen.coverFlow:
        final albums = _albums;
        if (albums.isNotEmpty) {
          await _playAudioAt(albums[_safeCoverIndex].firstIndex);
        }
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

  // ---------------- Giao dien (full man hinh) ----------------
  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final wheelSize = screenW * 0.70;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(screenW * 0.06, 18, screenW * 0.06, 14),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF7F7F7), Color(0xFFD9D9DE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            children: [
              // Man hinh LCD ti le chuan iPod Classic 7: 320x240 = 4:3.
              // Tren dien thoai cao, phan than may con thua se om quanh
              // man hinh (man hinh nam giua vung Expanded).
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _buildScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              ClickWheel(
                size: wheelSize,
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
              const SizedBox(height: 12),
              const Text(
                'Xoay vong tron de chon - cham giua de OK - MENU de quay lai',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreen() {
    return Container(
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
            '${_audios.length} songs',
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
      case AppScreen.coverFlow:
        return _coverFlowView();
      case AppScreen.nowPlaying:
        return _nowPlayingView();
      case AppScreen.videoPlayer:
        return _videoView();
      case AppScreen.photoViewer:
        return _photoView();
    }
  }

  // ---------------- Cover Flow ----------------
  // Man hinh duyet album kieu iPod Classic: bia chay ngang dang 3D,
  // bia giua dung thang + to nhat, 2 bia ben nghieng di, duoi moi
  // bia co anh phan chieu mo dan. Xoay num hoac quet ngang de
  // luot album, bam giua de phat album dang chon tu bai dau tien.
  Widget _coverFlowView() {
    final albums = _albums;
    if (_audios.isEmpty) {
      return const Center(
        child: Text('Chua co nhac.\nVao MENU > Import Media... de them.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black54)),
      );
    }
    final current = albums[_safeCoverIndex];
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7FB2D9), Color(0xFF3E7CB1)],
            ),
          ),
          child: Row(
            children: [
              const Text('Cover Flow',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const Spacer(),
              Text('${albums.length} albums',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _coverController,
            itemCount: albums.length,
            onPageChanged: (i) => setState(() => _coverIndex = i),
            itemBuilder: (context, i) {
              return AnimatedBuilder(
                animation: _coverController,
                builder: (context, child) {
                  double delta;
                  if (_coverController.hasClients &&
                      _coverController.position.hasContentDimensions) {
                    delta =
                        i - (_coverController.page ?? _coverIndex.toDouble());
                  } else {
                    delta = (i - _coverIndex).toDouble();
                  }
                  final angle =
                      (-delta * 1.1).clamp(-1.1, 1.1).toDouble();
                  final scale =
                      (1.0 - (delta.abs() * 0.18).clamp(0.0, 0.35)).toDouble();
                  return Center(
                    child: Transform(
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0015)
                        ..rotateY(angle)
                        ..scale(scale),
                      alignment: Alignment.center,
                      child: child,
                    ),
                  );
                },
                child: _coverTile(albums[i]),
              );
            },
          ),
        ),
        Text(current.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold)),
        Text(current.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _coverTile(_Album album) {
    final art = album.art;
    final Widget cover = art != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(art,
                width: 100, height: 100, fit: BoxFit.cover),
          )
        : Container(
            // Album khong co anh: logo not nhac mac dinh thay cho
            // o xam ghi ten (ten album da hien duoi day bia roi).
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9DE),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.music_note,
                size: 52, color: Colors.black38),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        cover,
        const SizedBox(height: 2),
        // Phan chieu: cung anh lat nguoc, chi lay 30px sat bia,
        // phu gradient ve mau nen de mo dan xuong duoi.
        ClipRect(
          child: SizedBox(
            height: 30,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..scale(1.0, -1.0),
                    child: Opacity(opacity: 0.35, child: cover),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x80F4F4EE),
                        Color(0xFFF4F4EE),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _listView({
    required String title,
    required List<String> items,
    List<String>? counts,
    String emptyText = '',
  }) {
    // Danh sach cuon THEO dong dang chon: ListView.builder cu chi
    // doi mau dong duoc chon chu khong tu cuon, nen dong nam duoi
    // nep gap (vi du Cover Flow la dong thu 6 trong menu) se bi an
    // mat du highlight da chay xuong toi no. O day build het cac
    // dong 1 lan (danh sach ngan) roi dung ensureVisible de cuon
    // dong dang chon vao trong khung hinh sau moi frame.
    final rowKeys =
        List<GlobalKey>.generate(items.length, (_) => GlobalKey());
    if (items.isNotEmpty) {
      var selectedIdx = _selected;
      if (selectedIdx < 0) selectedIdx = 0;
      if (selectedIdx >= items.length) selectedIdx = items.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = rowKeys[selectedIdx].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    }
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
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Builder(
                      builder: (context) {
                        final selected = i == _selected;
                        return Container(
                          key: rowKeys[i],
                          color: selected
                              ? const Color(0xFF2E7CD6)
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
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
                                    color: selected
                                        ? Colors.white
                                        : Colors.black87,
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
                                    color: selected
                                        ? Colors.white70
                                        : Colors.black45,
                                  ),
                                ),
                              Icon(Icons.chevron_right,
                                  size: 16,
                                  color: selected
                                      ? Colors.white
                                      : Colors.black38),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
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
    // Anh bia chi hien khi file nhac co san anh nhung (da doc o
    // _playAudioAt); file khong co anh thi giu nguyen giao dien chu.
    final art = _artBytesCache[track.path];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Anh bia co dan theo chieu cao LCD: man hinh hep hoac
          // chu he thong to hon van vua, khong con loi RenderFlex
          // overflow nhu ban truoc (tran 9.8px o day man hinh).
          final artSize =
              (constraints.maxHeight - 140).clamp(56.0, 84.0).toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          const Text('Now Playing',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          if (art != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(art,
                      width: artSize, height: artSize, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const Text('My Library - iPod Classic',
                          style: TextStyle(
                              fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            )
          else
            // Bai khong co anh: hien o not nhac mac dinh cung kich
            // co o anh bia (khong de trong nhu truoc nua).
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: artSize,
                  height: artSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D9DE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.music_note,
                      size: artSize * 0.55, color: Colors.black38),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(track.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const Text('My Library - iPod Classic',
                          style: TextStyle(
                              fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
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
          );
        },
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
  final double size; // duong kinh num xoay, tinh theo chieu rong man hinh
  final bool isPlaying;
  final void Function(int direction) onRotate;
  final VoidCallback onCenter;
  final VoidCallback onMenu;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;

  const ClickWheel({
    super.key,
    required this.size,
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
        // Haptic "tach" moi khi xoay qua 1 nac - cam giac bam cua num xoay that.
        HapticFeedback.selectionClick();
        widget.onRotate(_accumulated > 0 ? 1 : -1);
        _accumulated = 0;
      }
    }
    _lastAngle = a;
  }

  void _handleTap(TapUpDetails d, Size s) {
    // Haptic "cuc" khi bam nut tren num xoay (MENU / Next / Prev / Play / giua).
    HapticFeedback.mediumImpact();
    final dx = d.localPosition.dx - s.width / 2;
    final dy = d.localPosition.dy - s.height / 2;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < s.width * 0.19) {
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
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          _lastAngle = _angleOf(d.localPosition, Size(size, size));
          _accumulated = 0;
        },
        onPanUpdate: (d) => _handlePan(d, Size(size, size)),
        onPanEnd: (_) => _lastAngle = null,
        onTapUp: (d) => _handleTap(d, Size(size, size)),
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
              Positioned(
                top: size * 0.059,
                child: Text('MENU',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF55555A),
                        fontSize: size * 0.055)),
              ),
              Positioned(
                left: size * 0.051,
                child: const Icon(Icons.skip_previous, color: Color(0xFF55555A)),
              ),
              Positioned(
                right: size * 0.051,
                child: const Icon(Icons.skip_next, color: Color(0xFF55555A)),
              ),
              Positioned(
                bottom: size * 0.051,
                child: Icon(
                  widget.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: const Color(0xFF55555A),
                ),
              ),
              Container(
                width: size * 0.382,
                height: size * 0.382,
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
