# 🛟 HeySOS — Free & Open-Source Data Recovery for MacOS

![Platform](https://img.shields.io/badge/Platform-macOS%2013.0+-blue)
![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-lightgrey)
![License](https://img.shields.io/badge/License-GPLv3-green)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![Status](https://img.shields.io/badge/Status-In%20Development-yellow)

**HeySOS** is a modern, native macOS GUI application that makes data recovery accessible to everyone. Powered by the legendary open-source engines **TestDisk** and **PhotoRec**, HeySOS brings robust file and partition recovery to Apple Silicon and Intel Macs — without the hefty price tag.

> ⚠️ **HeySOS is currently in active development.** Contributions, feedback, and testing are welcome!

---

## ✨ Features

- **Native SwiftUI Interface** — Clean, intuitive, and designed exclusively for macOS.
- **Deep File Scan (PhotoRec Engine)** — Recover lost photos, videos, documents, and archives from corrupted or formatted drives.
- **Partition Recovery (TestDisk Engine)** — Rebuild lost partition tables and repair damaged boot sectors.
- **External Device Support** — Works with SD cards, USB flash drives, external HDDs, and SSDs.
- **Privacy First** — 100% open-source. No telemetry, no hidden data uploads. Everything runs locally on your machine.

---

## 🖼 Screenshots

> _Screenshots and demo GIFs will be added as the UI matures._

---

## 🏗 Architecture

HeySOS acts as a Swift wrapper around compiled C/C++ binaries:

- **Frontend** — SwiftUI provides a seamless, native macOS experience.
- **Task Manager** — Uses Swift's `Process` class to asynchronously execute `photorec` and `testdisk` binaries.
- **Log Parser** — Parses CLI stdout in real-time to drive UI progress bars and recovery file lists.

---

## ⚙️ Prerequisites

To build HeySOS from source, you will need:

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Basic familiarity with compiling C/C++ projects (for building TestDisk/PhotoRec targeting `arm64`)

---

## 🛠 Building from Source

**1. Clone the repository:**

```bash
git clone https://github.com/phucdhh/HeySOS.git
cd HeySOS
```

**2. Compile the core engines:**

> Detailed instructions for compiling TestDisk/PhotoRec for macOS (both `arm64` and `x86_64`) will be added to the [Wiki](../../wiki).

**3. Place the compiled binaries:**

Copy the compiled `photorec` and `testdisk` binaries into:

```
Sources/Resources/Binaries/
```

**4. Open and run in Xcode:**

```bash
open HeySOS.xcodeproj
```

Then press **⌘R** to build and run.

> **⚠️ Important:** HeySOS requires **Full Disk Access** to interact with physical drives (`/dev/disk*`).
> Grant access at: **System Settings → Privacy & Security → Full Disk Access**

---

## 🗺 Roadmap

- [ ] Basic SwiftUI shell and navigation
- [ ] PhotoRec integration (scan & recover files)
- [ ] TestDisk integration (partition recovery)
- [ ] Real-time progress parsing and log display
- [ ] Drive/device selector UI
- [ ] Localization (Vietnamese 🇻🇳, and more)
- [ ] Notarized release build
- [ ] Homebrew Cask distribution

---

## 🤝 Contributing

Contributions are warmly welcome! Here are some ways you can help:

- Improve the Swift wrapper or async task handling
- Enhance CLI output parsing for better progress reporting
- Translate the UI into other languages
- Write tests or improve documentation
- Report bugs and suggest features via [Issues](../../issues)

Please check the **[Issues](../../issues)** tab for open tasks before starting work, and feel free to open a discussion if you have questions.

---

## 📜 License

HeySOS is released under the **[GNU General Public License v3.0 (GPLv3)](LICENSE)**.

This project utilizes **TestDisk & PhotoRec** by Christophe Grenier, which are also licensed under the GPL.