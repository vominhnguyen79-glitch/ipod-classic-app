# iPod Classic App — Hướng dẫn từng bước (chỉ tay như em bé)

Mục tiêu: 1 bộ code duy nhất chạy cả iOS + Android. Giao diện iPod Classic Gen 7,
núm xoay (Click Wheel) xoay được thật, bỏ nhạc vào là phát, tắt/khóa màn hình vẫn phát,
điều khiển được từ màn hình khóa + Dynamic Island (iPhone) và thanh thông báo (Android),
phát được video, xem được ảnh.

> Nguyên tắc làm việc: **làm từng bước, chạy được bước nào chụp màn hình gửi trợ lý bước đó.**
> Đừng làm liền 10 bước rồi mới báo lỗi — lỗi dồn lại sẽ không biết hỏng từ đâu.

---

## 0. Nói thẳng trước khi bắt đầu — để khỏi vỡ mộng giữa chừng

| Điều bạn muốn | Sự thật |
|---|---|
| 1 code chạy 2 nền tảng | ✅ Được — nhờ **Flutter**. Viết Swift cho iOS + Kotlin cho Android riêng là 2 app, gấp đôi công, người mới không kham nổi. Flutter viết 1 lần bằng Dart. |
| Tắt màn hình nhạc vẫn phát, pause/seek ở màn hình khóa | ✅ Được — gói `just_audio` + `just_audio_background` lo việc này, hỗ trợ cả play/pause/seek trên Android và iOS. |
| Dynamic Island | ⚠️ Nhạc đang phát sẽ **tự** hiện trên Dynamic Island qua hệ thống Now Playing của iOS (nhấn giữ Island sẽ mở nút pause/next) — giống Spotify/Apple Music. Đây là tính năng của hệ điều hành, không phải mình vẽ thêm 1 widget riêng. Chỉ máy có Dynamic Island (iPhone 14 Pro trở lên, hoặc Simulator chọn đúng model đó) mới thấy. |
| Cài lên iPhone thật miễn phí | ⚠️ Được nhưng app **hết hạn sau 7 ngày** với Apple ID miễn phí (phải cắm máy tính chạy lại). Muốn cài lâu dài/TestFlight: Apple Developer 99 USD/năm. Android thì thoải mái: xuất file `.apk` gửi ai cũng cài được. |
| Đưa lên GitHub cho mọi người tải | ✅ Code thì public thoải mái. Người dùng Android tải `.apk` ở mục Releases. Người dùng iPhone **không** cài được file từ GitHub nếu không có tài khoản dev — đây là luật của Apple, không phải lỗi của app. |
| Bỏ file vào là phát mãi mãi | ⚠️ **Giới hạn của bản v1 này:** danh sách file chỉ nhớ trong lúc app đang mở. Tắt hẳn app mở lại phải Import lại. Bản v2 sẽ nâng cấp: tự copy file vào thư mục riêng của app + lưu danh sách. Làm v1 chạy được đã rồi hãy lên v2. |
| Video `.mkv` | ⚠️ Trình phát gốc của iOS/Android thường không đọc `.mkv`. Ưu tiên `.mp4` / `.mov`. |

Thời gian ước tính: Buổi 0 (cài công cụ) 1–2 tiếng chủ yếu chờ tải. Buổi 1 (dựng + chạy thử) 1–1,5 tiếng nếu không kẹt lỗi lạ.

---

## 1. Bạn còn THẾU công cụ nào?

Bạn đã có: Xcode ✅, Android Studio ✅, Git/GitHub ✅ (đã dùng ở repo game-dev-journey).

Còn thiếu — đây là thứ quan trọng nhất:

1. **Flutter SDK** — Xcode + Android Studio *chưa đủ*. Chúng chỉ là "xưởng" của từng hãng.
   Flutter mới là bộ khung để 1 code chạy cả 2 nơi.
2. **CocoaPods** — thợ phụ để iOS tải thư viện (Flutter sẽ báo nếu thiếu).
3. VS Code (bạn đã có) + 2 extension: `Flutter` và `Dart` — để mở code dễ nhìn.

### Buổi 0 — Cài Flutter (làm đúng thứ tự)

Mở **Terminal** trên Mac (Cmd + Space, gõ `Terminal`, Enter). Gõ từng lệnh, chờ chạy xong mới gõ lệnh tiếp.

```bash
# Cach de nhat tren Mac: cai bang Homebrew (neu chua co Homebrew thi bao tro ly truoc)
brew install --cask flutter

# Kiem tra da nhan chua
flutter --version
```

Nếu hiện ra dòng có chữ `Flutter 3.x` là xong bước này. Nếu báo `command not found`, chụp màn hình gửi trợ lý, đừng tự mò lệnh lạ trên mạng.

Tiếp theo, lệnh "bác sĩ khám tổng quát" — lệnh này sẽ dùng rất nhiều lần:

```bash
flutter doctor
```

Nó in ra danh sách dấu ✅ / ❌. Xử lý từng ❌ thường gặp:

```bash
# Loi lien quan Xcode:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept

# Thieu CocoaPods:
brew install cocoapods

# Loi Android licenses: chay lenh nay, cu bam phim y + Enter cho moi cau hoi
flutter doctor --android-licenses
```

Mở Android Studio 1 lần → SDK Manager → kiểm tra đã có **Android SDK Command-line Tools (latest)** chưa, chưa có thì tick vào → Apply.
Mở Xcode 1 lần → đồng ý điều khoản nếu nó hỏi.

Chạy lại `flutter doctor` đến khi chỉ còn toàn ✅ (hoặc còn ❌ nào lạ thì chụp gửi trợ lý).
**Xong Buổi 0 thì nhắn trợ lý: "xong flutter doctor" + chụp ảnh kết quả.** Chưa qua bước sau vội.

---

## 2. Tạo khung app trống

Vẫn ở Terminal. ⚠️ Bạn đang có 2 thư mục tên gần giống nhau (`projects` / `Project`) từng gây nhầm lẫn — lần này cd đúng 1 chỗ và kiểm tra bằng `pwd` trước:

```bash
cd ~/Documents/Projects
pwd
flutter create ipod_classic
cd ipod_classic
flutter run
```

`flutter run` lần đầu sẽ hỏi chạy trên máy nào — chọn Android Emulator hoặc iOS Simulator đang mở.
Thấy app đếm số (Counter App) mặc định hiện lên và bấm nút `+` số tăng được = khung xương đã sống.
App mặc định chán ngắt là bình thường — bước sau mới thay ruột iPod vào.

Mở thư mục này bằng VS Code để lát dán code:

```bash
code .
```
(Nếu lệnh `code` chưa có: mở VS Code thủ công rồi File > Open Folder > chọn `ipod_classic`.)

---

## 3. Thay ruột: dán code iPod vào

Gói trợ lý đã chuẩn bị sẵn gồm: `pubspec.yaml`, `lib/main.dart`, thư mục `config-snippets/`.

1. Trong VS Code, mở file `pubspec.yaml` của project → xóa hết → dán toàn bộ nội dung file `pubspec.yaml` trong gói vào → Cmd + S.
2. Mở `lib/main.dart` → xóa hết → dán toàn bộ file `main.dart` trong gói vào → Cmd + S.
   File này ~780 dòng, dán 1 lần là xong, **không cần hiểu hết ngay** — cuối hướng dẫn có bản đồ giải thích từng khối.
3. Quay lại Terminal (vẫn đang đứng trong `ipod_classic`):

```bash
flutter pub get
```

Lệnh này tải các thư viện: phát nhạc, phát nền, chọn file, phát video. Báo lỗi đỏ thì chụp gửi trợ lý nguyên văn, đừng sửa bừa.

---

## 4. Cấu hình iOS (để khóa màn hình vẫn phát)

1. Trong VS Code mở file: `ios/Runner/Info.plist`
2. Tìm đến gần cuối file, ngay **trước** dòng `</dict>` cuối cùng, dán khối trong file mẫu
   `config-snippets/Info.plist.snippet.xml` (khối `UIBackgroundModes` = audio).
3. Cmd + S.

Chỉ vậy thôi. Không sửa file Swift nào khác ở phía iOS.

---

## 5. Cấu hình Android (3 chỗ — làm chậm, đúng từng chỗ)

**Chỗ 1 — `android/app/src/main/AndroidManifest.xml`:**
Mở file mẫu `config-snippets/AndroidManifest.xml` (có đánh số 1-2-3 trong comment) và đối chiếu:
thêm 4 dòng `<uses-permission .../>` lên trên, và thêm khối `<service>` + `<receiver>` của AudioService vào trong `<application>`. Cmd + S.

**Chỗ 2 — MainActivity:**
Tìm file theo đường cây thư mục: `android/app/src/main/kotlin/com/example/ipod_classic/MainActivity.kt`
Xóa hết nội dung, dán file mẫu `config-snippets/MainActivity.kt` vào. ⚠️ Dòng đầu tiên `package com.example.ipod_classic` phải khớp tên package của project bạn — nếu lúc `flutter create` bạn đặt tên khác, giữ lại dòng package cũ của file gốc, chỉ thay phần dưới. Chỗ này hay sai nhất, làm xong chụp gửi trợ lý kiểm tra trước khi chạy.

**Chỗ 3:** Không có chỗ 3. Xong rồi.

---

## 6. Chạy thử lần đầu + checklist kiểm tra

```bash
flutter run
```

App hiện thân máy iPod bạc, màn hình trắng có menu: Music / Videos / Photos / Now Playing / Import Media...

Checklist — tick từng ô, kẹt ô nào báo ô đó:

- [ ] Xoay ngón tay vòng quanh núm tròn: dòng chọn trong menu chạy lên/xuống theo
- [ ] Chạm **giữa** núm ở mục `Import Media...` → chọn 1 file `.mp3` trong máy → báo "Đã thêm 1 file"
- [ ] MENU (chạm phía **trên** núm) để quay lại → Music → chạm giữa để chọn bài → nhạc phát, hiện màn Now Playing
- [ ] Kéo thanh trượt (slider): nhạc tua được. Chạm phía **dưới** núm: pause/phát tiếp. Chạm **phải/trái** núm: qua bài (nếu có ≥2 bài)
- [ ] **Bài kiểm tra quan trọng nhất:** đang phát nhạc → bấm Home/thoát ra ngoài → nhạc **vẫn phát**. Khóa màn hình (máy thật) hoặc mở Control Center / thanh thông báo (Android) → thấy tên bài + nút pause/next, bấm được
- [ ] iPhone có Dynamic Island (máy thật 14 Pro+ hoặc Simulator model Pro): thấy sóng nhạc/Now Playing trên Island, nhấn giữ Island mở được nút điều khiển
- [ ] Import 1 video `.mp4` → Videos → phát được trong màn hình iPod, nút dưới núm pause được video
- [ ] Import 1 ảnh `.jpg/.png` → Photos → xem được, xoay núm để chuyển ảnh

⚠️ Simulator giả lập không khóa màn hình + không có Dynamic Island giống máy thật 100% được.
Muốn test 2 tính năng đó chuẩn nhất phải chạy trên **iPhone thật**: cắm cáp → mở `ios/Runner.xcworkspace` bằng Xcode → mục Signing & Capabilities → tick Automatically manage signing → chọn Team là Apple ID cá nhân của bạn → rồi `flutter run`.

---

## 7. Xuất bản để chia sẻ

**Android (dễ, làm trước):**
```bash
flutter build apk --release
```
File ra ở `build/app/outputs/flutter-apk/app-release.apk` — gửi trực tiếp cho bạn bè hoặc đính vào GitHub Releases.

**iOS:** `flutter build ios --release --no-codesign` chỉ để kiểm tra code biên dịch được.
Chia sẻ cho người khác cài iPhone cần tài khoản dev 99 USD/năm (TestFlight) — để sau, khi app đáng tiền đó.

---

## 8. Đẩy lên GitHub (bạn đã biết quy trình này ở repo game)

1. Tạo repo mới trên GitHub tên `ipod-classic-app`, chọn **Public**, không tick tạo README (project Flutter đã có sẵn).
2. Ở Terminal trong thư mục `ipod_classic`:

```bash
git init
git add .
git commit -m "v1: iPod Classic player - music background, video, photos, click wheel"
git branch -M main
git remote add origin https://github.com/vominhnguyen79-glitch/ipod-classic-app.git
git push -u origin main
```

3. Dùng file `README_GITHUB.md` trong gói làm nội dung README của repo — trong đó đã có sẵn
   đoạn công khai quá trình làm bằng AI đúng như ý bạn muốn minh bạch. Điền thêm ảnh chụp app của bạn vào.
4. Mục Releases → Create a new release → tag `v1.0.0` → kéo file `.apk` vào → Publish.
   Từ giờ ai vào repo cũng tải Android về trải nghiệm được.

⚠️ Token GitHub classic của bạn hết hạn ~14/11/2026 — nếu push báo lỗi 403 thì đó là nó, tạo token mới như lần trước.

---

## 9. Lỗi hay gặp — tra nhanh trước khi hoảng

| Hiện tượng | Nguyên nhân thường gặp |
|---|---|
| `command not found: flutter` | Chưa cài Flutter hoặc chưa mở Terminal mới sau khi cài |
| `flutter pub get` đỏ lòm | Sai/thiếu dòng trong `pubspec.yaml` — thường do dán thiếu khúc cuối |
| Nhạc dừng khi thoát app (Android) | Chưa thêm `<service>` vào AndroidManifest hoặc chưa thay MainActivity |
| Nhạc dừng khi khóa màn hình (iOS) | Thiếu `UIBackgroundModes` trong Info.plist |
| Màn hình đỏ "setState after dispose" / lỗi video | Đang mở video `.mkv` — đổi sang `.mp4` |
| Xoay núm mà menu không chạy | Ngón tay đang xoay ở tâm núm — phải xoay ở **vành** ngoài, như núm iPod thật |
| Push GitHub lỗi 403 | Token hết hạn (xem mục 8) |

Kẹt ở đâu: chụp màn hình **nguyên khung** (thấy cả dòng lỗi đỏ + tên file) gửi trợ lý, kèm câu "em đang ở Bước số mấy". Trợ lý đọc lỗi theo đúng vị trí file(dòng,cột) như cách mình vẫn làm ở lớp C#.

---

## 10. Bản đồ code — để sau này bạn đọc lại không bị ngợp

Trong `lib/main.dart` chỉ có 4 khối:

1. `main()` — bật chế độ phát nền trước khi app mở.
2. `kindFromPath()` — nhìn đuôi file (.mp3/.mp4/.jpg) để phân loại nhạc/video/ảnh.
3. `IPodHomePage` — bộ não: giữ danh sách file, đang ở màn hình nào, phát/tạm dừng/tua.
4. `ClickWheel` — núm xoay: tính góc ngón tay, xoay đủ ~20° thì nhảy 1 mục; chạm trên = MENU, phải = Next, dưới = Play/Pause, trái = Previous, giữa = Chọn.

Lộ trình nâng cấp sau khi v1 chạy ngon: **v2** lưu danh sách + copy file vào thư mục app (khỏi import lại), **v3** lấy ảnh bìa album + tên bài hát thật từ metadata của file nhạc, **v4** làm giao diện đen (iPod Classic có bản black) và hiệu ứng Cover Flow nếu muốn.
