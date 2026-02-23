# 📋 HeySOS — Project Development Plan

> **Vision:** A free, open-source, native macOS application that makes data recovery from any connected storage device (SD cards, USB drives, SSDs, HDDs) accessible to everyone — no technical knowledge required.

**Version:** 1.0  
**Last updated:** 2026-02-23  
**Status:** Phase 1 In Progress — Core engine integration (Milestone 1.1–1.4 complete)

---

## ✅ Feasibility Assessment

> Đánh giá ngày 2026-02-23. Kết luận: **Dự án khả thi cao.** Không có bào cản kỹ thuật mang tính khó vượt qua — toàn bộ dựa trên công nghệ đã được kiểm chứng.

| Tiêu chí | Đánh giá | Ghi chú |
|----------|----------|---------|
| Tính khả thi kỹ thuật | 🟢 Cao | PhotoRec/TestDisk đã proven, Swift Process API ổn định |
| Rủi ro kỹ thuật chính | 🟡 Trung bình | PhotoRec là TUI ncurses → phải dùng `--cmd` batch mode (xem Milestone 1.2) |
| Xác nhận stack | 🟢 | SwiftUI + Swift Concurrency là lựa chọn đúng cho native macOS |
| macOS target | 🟢 Đã sửa | Đổi từ macOS 13 → **macOS 14** để dùng SwiftData (yêu cầu tối thiểu 14) |
| Phân phối | 🟢 | Notarized DMG + Homebrew Cask là tiêu chuẩn ngành |
| License compliance | 🟢 | GPLv3 bắt buộc vì bundle PhotoRec/TestDisk (GPL) — đúng |
| Thời gian ước tính | 🟡 | 14 tuần full-time là realistic nếu developer có Swift & macOS experience |

**Các điểm đã điều chỉnh trong plan này:**
1. Deployment target nâng từ macOS 13 → **macOS 14** (SwiftData yêu cầu)
2. Milestone 1.2 bổ sung chi tiết về PhotoRec `--cmd` batch mode (thay vì pipe stdin)
3. TestDisk scope đã làm rõ: Phase 1 chỉ build backend, **UI đầy đủ ở v1.3**
4. Entitlements cho subprocess trong Hardened Runtime đã được cụ thể hoá

---

## 🗂 Table of Contents

1. [Project Scope](#1-project-scope)
2. [Technical Stack](#2-technical-stack)
3. [Architecture Overview](#3-architecture-overview)
4. [Phase 0 — Foundation](#phase-0--foundation-weeks-1-2)
5. [Phase 1 — Core Engine Integration](#phase-1--core-engine-integration-weeks-3-6)
6. [Phase 2 — MVP UI](#phase-2--mvp-ui-weeks-7-10)
7. [Phase 3 — Polish & Distribution](#phase-3--polish--distribution-weeks-11-14)
8. [Phase 4 — Post-Launch & Growth](#phase-4--post-launch--growth-ongoing)
9. [Risk Register](#9-risk-register)
10. [Success Metrics](#10-success-metrics)

---

## 1. Project Scope

### Trong phạm vi (In Scope)

- Recover files từ các **thiết bị lưu trữ ngoài** cắm vào Mac: thẻ nhớ SD/microSD, USB flash drive, External SSD, External HDD, Memory Stick
- Recover files từ **internal drives** của Mac (với Full Disk Access)
- Hỗ trợ các format file phổ biến: ảnh (JPG, PNG, RAW, HEIC), video (MP4, MOV, MKV), tài liệu (PDF, DOCX, XLSX), nhạc (MP3, FLAC, AAC), lưu trữ (ZIP, RAR)
- Giao diện **SwiftUI native** — không phải Electron, không phải web wrapper
- **Hoàn toàn miễn phí và mã nguồn mở** (GPLv3)

### Ngoài phạm vi (Out of Scope — v1.0)

- Recovery qua mạng (NAS, network drives)
- Recovery cho iOS/Android devices
- RAID array recovery
- Forensic-grade imaging (dd, clone drives)
- Windows/Linux support

---

## 2. Technical Stack

| Layer | Technology | Lý do chọn |
|---|---|---|
| UI Framework | SwiftUI | Native macOS, hiệu suất tốt, Apple-idiomatic |
| Language | Swift 5.9+ | Type-safe, modern, async/await support |
| Recovery Engine | PhotoRec (CGI) | Proven, hỗ trợ 480+ file types |
| Partition Engine | TestDisk | Industry standard cho partition recovery |
| Binary Management | Bundled binaries | Đảm bảo version consistency |
| Concurrency | Swift Concurrency (async/await + Actor) | Không block UI thread |
| Persistence | SwiftData + UserDefaults | SwiftData yêu cầu macOS 14+; UserDefaults cho preferences đơn |
| Packaging | Xcode + Notarization | Yêu cầu bắt buộc của macOS |
| Distribution | GitHub Releases + Homebrew Cask | Tiếp cận developer community |
| CI/CD | GitHub Actions | Build, test, notarize tự động |

> ⚠️ **Deployment Target: macOS 14.0 (Sonoma)+** — Sonoma đã có từ 09/2023 và là yêu cầu tối thiểu để dùng SwiftData. Đây là quyết định có chủ ý nhằm tránh overhead của CoreData.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    HeySOS.app (SwiftUI)                 │
│                                                         │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │  DeviceView  │  │   ScanView   │  │  ResultsView  │  │
│  │  (Chọn ổ)   │  │ (Tiến trình) │  │  (File list)  │  │
│  └──────┬──────┘  └──────┬───────┘  └───────┬───────┘  │
│         └────────────────┼──────────────────┘           │
│                          │                              │
│              ┌───────────▼──────────┐                   │
│              │    RecoveryManager   │                   │
│              │  (Swift Actor/Class) │                   │
│              └───────────┬──────────┘                   │
│                          │                              │
│         ┌────────────────┼─────────────────┐            │
│         │                │                 │            │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌───────▼─────┐     │
│  │PhotoRecTask │  │TestDiskTask │  │  LogParser  │     │
│  │(Process)    │  │(Process)    │  │(Regex/State)│     │
│  └──────┬──────┘  └──────┬──────┘  └─────────────┘     │
└─────────┼────────────────┼─────────────────────────────┘
          │                │
   ┌──────▼──────┐  ┌──────▼──────┐
   │  photorec   │  │  testdisk   │
   │  (binary)   │  │  (binary)   │
   └─────────────┘  └─────────────┘
```

### Luồng dữ liệu chính

```
User chọn device → RecoveryManager khởi tạo Process
→ Binary chạy trong subprocess → stdout được pipe ra
→ LogParser phân tích real-time → ViewModel update
→ SwiftUI re-render progress + file list
→ Recovery hoàn tất → User chọn file để save
```

---

## Phase 0 — Foundation
### ⏱ Thời gian: Tuần 1–2

Mục tiêu: Thiết lập môi trường, cấu trúc project, và compile được engine binaries.

### Milestone 0.1 — Project Setup

- [x] Tạo Xcode project với cấu hình đúng (Bundle ID, deployment target macOS 14+, signing)
- [x] Thiết lập cấu trúc thư mục theo kiến trúc đã định
- [x] Cấu hình `.gitignore`, `README.md`, `LICENSE`, `PLAN.md`
- [x] Thiết lập GitHub repository với branch protection cho `main`
- [x] Tạo GitHub Actions workflow cơ bản (build check on PR)

```
Sources/                       # Swift source code (Xcode target)
├── App/
│   ├── HeySOS.swift          # App entry point
│   └── AppDelegate.swift
├── Features/
│   ├── DeviceSelector/       # Chọn thiết bị
│   ├── Scanner/              # Màn hình scan
│   └── Results/              # Hiển thị kết quả
├── Core/
│   ├── RecoveryManager.swift
│   ├── PhotoRecTask.swift
│   ├── TestDiskTask.swift
│   └── LogParser.swift
├── Models/
│   ├── StorageDevice.swift
│   └── RecoveredFile.swift
├── Resources/
│   └── Binaries/
│       ├── photorec           # compiled binary (arm64 + x86_64)
│       └── testdisk
Tests/
├── LogParserTests/
    └── RecoveryManagerTests/
```

### Milestone 0.2 — Compile Engine Binaries

- [x] Compile TestDisk/PhotoRec cho `arm64` (Apple Silicon) — qua Homebrew bottle `testdisk 7.2`
- [ ] Compile TestDisk/PhotoRec cho `x86_64` (Intel) — cần khi chuẩn bị release
- [ ] Tạo Universal Binary (`lipo`) hoặc dùng fat binary
- [x] Viết script `scripts/build-engines.sh` để tự động hóa bước này
- [x] Verify binaries chạy được trên arm64: `photorec --version` + `testdisk --version` OK
- [ ] Document quá trình build vào Wiki

### Milestone 0.3 — Permissions & Entitlements

> ⚠️ **Lưu ý quan trọng về Hardened Runtime:** Vì app dùng `Process` để chạy binary bên ngoài (photorec, testdisk), cần cấu hình entitlements cẩn thận. App **KHÔNG** cần sandbox (không lên Mac App Store), giúp đơn giản hoá đáng kể.

- [x] Cấu hình entitlements file (`HeySOS.entitlements`):
  - `com.apple.security.cs.disable-library-validation` → `true` (cho phép bundle binary unsigned)
  - `com.apple.security.files.all` → `true` (tương đương Full Disk Access)
  - `com.apple.security.temporary-exception.files.absolute-path.read-write` → `['/dev/']`
- [x] **Không bật** App Sandbox (`com.apple.security.app-sandbox`) — sẽ chặn `/dev/disk*` access
- [ ] Test Full Disk Access flow: app tự detect và hướng dẫn user cấp quyền nếu thiếu
- [ ] Verify `photorec` binary có thể chạy dưới subprocess (Hardened Runtime + `--cmd` mode)
- [ ] Verify Gatekeeper pass sau khi notarize với entitlements đúng

**Deliverable:** Project scaffold hoàn chỉnh, binaries build được, chạy `photorec --help` từ trong app.

---

## Phase 1 — Core Engine Integration
### ⏱ Thời gian: Tuần 3–6

Mục tiêu: HeySOS có thể thực sự recover file, dù chưa có UI đẹp.

### Milestone 1.1 — Device Discovery

- [x] Implement `DiskUtilWrapper` — parse output của `diskutil list -plist` + `diskutil info -plist` để lấy danh sách devices
- [x] Model `StorageDevice`: tên, kích thước, mount point, loại (internal/external), file system
- [ ] Detect khi device được cắm vào / rút ra (IOKit notifications hoặc polling)
- [x] Lọc ra các external devices để ưu tiên hiển thị (sort: external first)
- [x] Unit test: `DiskUtilWrapperTests` — 4 tests pass

```swift
// StorageDevice model
struct StorageDevice: Identifiable {
    let id: String           // /dev/disk2
    let name: String         // "SONY 64GB"
    let size: Int64          // bytes
    let fileSystem: String   // FAT32, exFAT, APFS...
    let isExternal: Bool
    let mountPoint: String?  // /Volumes/SONY
    let mediaType: MediaType // .sdCard, .usb, .ssd, .hdd
}
```

### Milestone 1.2 — PhotoRec Integration

> ⚠️ **Quan trọng — PhotoRec CLI Mode:** PhotoRec mặc định là ứng dụng **ncurses TUI** (interactive terminal). **Không thể** điều khiển bằng cách pipe stdin như một CLI thông thường. Giải pháp: dùng **`--cmd` batch mode** của PhotoRec:
> ```
> photorec /d /path/to/output /cmd "/dev/disk2,fileopt,everything,enable,search"
> ```
> Mode này chạy hoàn toàn non-interactive, xuất log ra stdout — phù hợp để parse. Đây là cách được dùng bởi các tool như `testdisk-qt` và nhiều GUI wrapper khác.

- [ ] Implement `PhotoRecTask` dùng `Foundation.Process` + async/await
- [ ] Dùng `--cmd` batch mode (NON-interactive) — **không** cố pipe vào ncurses interface
- [ ] Pipe stdout/stderr ra để đọc real-time qua `FileHandle.readabilityHandler`
- [ ] Parse tiến trình từ output (số file đã recover, tốc độ, % hoàn thành)
- [ ] Implement cancel/stop gracefully: gửi `SIGTERM` → đợi process exit → cleanup temp files
- [ ] Test với disk image (`.img`) trước khi test với physical device
- [ ] Test với thẻ nhớ thực tế có dữ liệu đã xóa

```swift
actor PhotoRecTask {
    func start(device: StorageDevice, outputDir: URL) -> AsyncStream<RecoveryEvent>
    func cancel()
}

enum RecoveryEvent {
    case progress(filesFound: Int, speed: String, percent: Double)
    case fileRecovered(name: String, type: String, size: Int64)
    case completed(totalFiles: Int, outputDir: URL)
    case failed(error: RecoveryError)
}
```

### Milestone 1.3 — TestDisk Integration (Backend Only — v1.0)

> 📌 **Scope v1.0:** TestDisk backend được build ở Phase 1 để kiểm chứng tích hợp, nhưng **UI đầy đủ cho TestDisk sẽ ra ở v1.3**. v1.0 chỉ expose PhotoRec cho end user. TestDisk trong v1.0 chỉ dùng nội bộ (ẩn sau "Advanced" tab hoặc chưa expose).

> ⚠️ **TestDisk và stdin:** TestDisk tương tự PhotoRec, cũng là ncurses TUI. Dùng `testdisk /cmd device.log "/dev/disk2,analyse,list"` để batch mode.

- [ ] Implement `TestDiskTask` tương tự PhotoRecTask, dùng `--cmd` / `/cmd` mode
- [x] Parse partition table output từ log file mà TestDisk tạo ra
- [ ] Chỉ implement **read-only modes** (Analyse, List) trong v1.0 — **chưa** implement Write mode
- [ ] Write mode (ghi partition table) để dành cho v1.3 với UX confirmation đầy đủ

### Milestone 1.4 — LogParser

- [x] Viết parser cho PhotoRec output format (`PhotoRecLogParser`) — regex-based, Swift 6 safe
- [x] Viết parser cho TestDisk output format (`TestDiskLogParser`) — multi-word type support
- [x] Unit test với captured output samples thực tế — **22/22 tests pass** (`swift test`)
- [x] Handle edge cases: empty lines, garbage output, single vs multi-word partition types

**Deliverable:** Chạy recovery từ command line / test harness, recover file thật từ thẻ nhớ test.

---

## Phase 2 — MVP UI
### ⏱ Thời gian: Tuần 7–10

Mục tiêu: Giao diện đủ dùng, người không rành kỹ thuật có thể tự recover.

### Milestone 2.1 — Main Navigation & Shell

- [ ] Implement `ContentView` với sidebar navigation
- [ ] 3 tab chính: **Recover Files** (PhotoRec), **Fix Partition** (TestDisk), **History**
- [ ] App icon (thiết kế hoặc placeholder)
- [ ] Onboarding screen lần đầu mở app (giải thích quyền cần cấp)
- [ ] Full Disk Access check — hướng dẫn nếu chưa cấp

### Milestone 2.2 — Device Selector View

- [ ] Danh sách thiết bị với icon phân loại (SD card, USB, SSD...)
- [ ] Hiển thị: tên thiết bị, dung lượng, file system, trạng thái mount
- [ ] Làm nổi bật external devices
- [ ] Refresh button + auto-refresh khi device thay đổi
- [ ] Warning nếu user chọn internal system drive

```
┌─────────────────────────────────────────┐
│  Chọn thiết bị cần khôi phục dữ liệu   │
├─────────────────────────────────────────┤
│  💾  SONY SD Card          59.7 GB  ●  │  ← External (recommended)
│      /dev/disk2 · exFAT               │
├─────────────────────────────────────────┤
│  🔌  SanDisk USB           14.9 GB     │
│      /dev/disk3 · FAT32               │
├─────────────────────────────────────────┤
│  🖥  Macintosh HD         499.9 GB     │  ← Internal (warning)
│      /dev/disk1 · APFS                │
└─────────────────────────────────────────┘
```

### Milestone 2.3 — Scan Configuration View

- [ ] Chọn loại file cần recover (ảnh, video, tài liệu, tất cả)
- [ ] Chọn thư mục output để lưu file recover
- [ ] Estimate thời gian (dựa trên dung lượng device)
- [ ] Chế độ: **Quick Scan** vs **Deep Scan**
- [ ] Start button với confirmation

### Milestone 2.4 — Progress View

- [ ] Progress bar tổng thể (%)
- [ ] Counter: số file đã tìm thấy theo loại (📷 124 ảnh, 🎬 8 video...)
- [ ] Tốc độ scan hiện tại (MB/s)
- [ ] Thời gian còn lại (estimated)
- [ ] Log view có thể toggle ẩn/hiện (cho user kỹ thuật)
- [ ] Pause / Cancel button

### Milestone 2.5 — Results View

- [ ] Grid view các file đã recover (ảnh có thumbnail)
- [ ] List view với thông tin chi tiết (tên, kích thước, loại, ngày recover)
- [ ] Filter theo loại file
- [ ] Search
- [ ] Multi-select + "Save Selected" / "Save All"
- [ ] Preview panel cho ảnh và video
- [ ] Mở file trong Finder

**Deliverable:** App chạy được end-to-end: cắm thẻ nhớ → chọn → scan → xem kết quả → lưu file.

---

## Phase 3 — Polish & Distribution
### ⏱ Thời gian: Tuần 11–14

Mục tiêu: App đủ chất lượng để release công khai.

### Milestone 3.1 — UX Polish

- [ ] Animations và transitions mượt mà
- [ ] Empty states có ý nghĩa (khi không có device, khi scan trống)
- [ ] Error states rõ ràng với hướng dẫn khắc phục
- [ ] Haptic feedback (nếu applicable)
- [ ] Keyboard shortcuts cho các action chính
- [ ] Accessibility: VoiceOver labels, Dynamic Type support

### Milestone 3.2 — Error Handling & Edge Cases

- [ ] Device bị rút trong khi đang scan
- [ ] Không đủ dung lượng ở thư mục output
- [ ] Binary bị corrupt hoặc không chạy được
- [ ] Permission bị từ chối mid-session
- [ ] Device bị hỏng nặng (I/O errors)
- [ ] Xử lý tên file với ký tự đặc biệt / Unicode

### Milestone 3.3 — Testing

- [ ] Unit tests cho LogParser (coverage > 80%)
- [ ] Unit tests cho DeviceDiscovery
- [ ] Integration test với disk image (`.img` file) thay vì physical device
- [ ] Manual testing checklist: SD card, USB, SSD ngoài, nhiều file system khác nhau
- [ ] Test trên cả Apple Silicon và Intel Mac
- [ ] Test trên macOS 13, 14, 15

### Milestone 3.4 — Build & Signing

- [ ] Code signing với Developer ID Certificate
- [ ] Notarization với Apple (bắt buộc để Gatekeeper pass)
- [ ] Staple notarization ticket vào app
- [ ] Tạo `.dmg` installer với background image
- [ ] Verify dmg mở được trên clean macOS install

### Milestone 3.5 — Distribution

- [ ] GitHub Release v1.0.0 với changelog đầy đủ
- [ ] Tạo Homebrew Cask: `brew install --cask heysos`
- [ ] Viết README đầy đủ với screenshots thực tế
- [ ] Tạo landing page đơn giản (GitHub Pages) với download link
- [ ] Submit to AlternativeTo, MacUpdate, Softpedia

**Deliverable:** HeySOS v1.0.0 release — bất kỳ ai cũng có thể download và dùng.

---

## Phase 4 — Post-Launch & Growth
### ⏱ Thời gian: Ongoing (sau v1.0)

### v1.1 — Localization & Accessibility
- [ ] Tiếng Việt 🇻🇳 (ngôn ngữ đầu tiên ngoài English)
- [ ] Tiếng Nhật, Hàn, Trung (thị trường dùng nhiều thẻ nhớ)
- [ ] Full VoiceOver support
- [ ] Hỗ trợ màn hình Retina và non-Retina

### v1.2 — Advanced Features
- [ ] **Scan History** — lưu lại các lần scan trước, không cần scan lại
- [ ] **Preview trước khi recover** — xem file có bị hỏng không trước khi lưu
- [ ] **File filter mở rộng** — chọn extension cụ thể (`.cr2`, `.arw` cho photographer)
- [ ] **Disk Image support** — recover từ file `.img`, `.iso`

### v1.3 — Power User Features
- [ ] TestDisk full UI — Analyse, Advanced, **Write partition table** (với multi-step confirmation)
- [ ] Drive health indicator (S.M.A.R.T. data)
- [ ] Export recovery report (PDF/CSV)
- [ ] CLI mode cho automation

### Cộng đồng & Ecosystem
- [ ] Xây dựng Contributors Guide đầy đủ
- [ ] Tạo Discord server / GitHub Discussions
- [ ] Blog posts về kiến trúc và bài học kỹ thuật
- [ ] Xem xét Open Collective để nhận donation duy trì dự án

---

## 9. Risk Register

| Rủi ro | Khả năng xảy ra | Mức độ ảnh hưởng | Phương án giảm thiểu |
|--------|----------------|-----------------|----------------------|
| Apple thay đổi policy, chặn bundled binaries | Thấp | Cao | Theo dõi WWDC, chuẩn bị phương án dùng Privileged Helper |
| PhotoRec CLI thay đổi output format | Trung bình | Trung bình | Pin version binary, viết test với captured output |
| App bị Gatekeeper chặn sau notarization | Trung bình | Cao | Test kỹ hardened runtime, có fallback hướng dẫn manual |
| Thiếu maintainer dài hạn | Cao | Trung bình | Document kỹ kiến trúc, xây dựng contributor community sớm |
| PhotoRec gây hỏng thêm data khi scan | Rất thấp | Rất cao | PhotoRec chỉ đọc (read-only), không ghi vào source device |
| Scope creep làm trễ v1.0 | Cao | Trung bình | Giữ v1.0 scope cứng, mọi feature mới vào backlog v1.x |

---

## 10. Success Metrics

### v1.0 Launch (3 tháng sau release)
- 500+ GitHub stars
- 100+ downloads qua GitHub Releases + Homebrew
- 0 critical bugs (crash, data loss) được báo cáo
- Hoạt động trên tối thiểu 3 loại thiết bị khác nhau

### v1.0 Ổn định (6 tháng sau release)
- 1,000+ GitHub stars
- 3+ contributors bên ngoài
- Được list trên ít nhất 2 "awesome macOS" repositories

---

## 📅 Timeline Tổng quan

```
Tuần  1–2   │ Phase 0  │ Foundation, scaffold, compile engines
Tuần  3–6   │ Phase 1  │ Core engine integration, device discovery
Tuần  7–10  │ Phase 2  │ MVP UI — đủ dùng end-to-end
Tuần 11–14  │ Phase 3  │ Polish, testing, signing, release v1.0
Tuần 15+    │ Phase 4  │ Post-launch features và community
```

**Tổng thời gian ước tính đến v1.0: ~14 tuần (1 developer full-time) hoặc ~6 tháng (part-time)**

---

*Tài liệu này là living document — cập nhật theo tiến độ thực tế của dự án.*