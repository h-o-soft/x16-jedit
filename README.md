# jedit for Commander X16

English | [日本語](README.ja.md)

A simple text editor for Commander X16 with SKK-style Japanese input support.

## Overview

jedit is a Japanese-enabled text editor developed for the Commander X16. It implements an SKK-style kanji input system, allowing Japanese text input and editing.

## ⚠️ Warning

This software is in beta and may have the following critical issues:

- Unexpected file loss
- System instability
- Data corruption
- Other unexpected behavior

Please take the following precautions before use:

- Back up important files
- Avoid use in critical environments
- Exit the program immediately if abnormal behavior occurs

The developer cannot be held responsible for any damages caused by these issues.

## Features

### Japanese Input
- SKK-style Japanese kanji input
  - Hiragana/Katakana input
  - Standard kanji conversion
  - Kanji conversion with okurigana position specification
- Basic text editor functionality
  - Text input and editing
  - File save and load

## Requirements

- Commander X16 hardware or emulator
- Required files:
  - `jedit.prg`: Main editor program
  - `skkdicm.bin`: SKK dictionary file (generated using steps below)
  - `jfont.bin`: Japanese font file (generated using steps below)

## Installation

### 1. Generate Dictionary File

Generate `skkdicm.bin` using these steps:

1. Navigate to the `dicconv/` directory
2. Prepare SKK dictionary file `SKK-JISYO.M` (in EUC-JP encoding)
3. Run `python dicconv.py`
4. Place the generated `skkdicm.bin` in the same directory as jedit

### 2. Generate Font File

Generate `jfont.bin` using these steps:

1. Navigate to the `fontconv/` directory
2. Prepare the following font images:
   - `k8x12_jisx0201.png`: JIS X 0201 character set (4x12 dots)
   - `k8x12_jisx0208.png`: JIS X 0208 character set (8x12 dots)
3. Run `python mkfont.py`
4. Place the generated `jfont.bin` in the same directory as jedit

The kanji font "k8x12" can be obtained from:
https://littlelimit.net/k8x12.htm

### 3. File Placement

Place the generated files and the editor executable as follows:

```
Commander X16 Storage
├── jedit.prg    # Editor executable
├── skkdicm.bin  # Conversion dictionary
└── jfont.bin    # Font data
```

## Usage

### Basic Operations

- Launch: `LOAD "JEDIT.PRG"` then `RUN`
- Kanji input: Press 「Ctrl + j」 to enter kanji input mode
- Half-width input: Press 「l」 in kanji input mode to enter half-width input mode
- Hiragana/Katakana toggle: Press 「q」 in kanji input mode to switch between hiragana and katakana
- Overwrite/Insert toggle: Press 「Ctrl + O」 to toggle insert mode
- Save: Press 「Ctrl + X」 to confirm save and exit
- Load: Press 「Ctrl + R」 to input filename and load
- Kanji conversion: 
  - Type reading starting with uppercase (e.g., `Kanji`)
  - Press space to convert
  - Press space for next candidate, Enter to confirm

### SKK Input Examples

- `Kanji` → 漢字
- `KanJi` → 感じ
- `TukaU` → 使う

## Developer Information

### Build Instructions

Building requires the [Prog8 compiler](https://github.com/irmen/prog8). Use the following command:

```
java -jar /usr/local/bin/prog8c-11.1-all.jar -target cx16 -dontsplitarrays jedit.p8
```

### Project Structure

- Source files:
  - `jedit.p8`: Main editor program
  - `tinyskk.p8`: SKK-style kanji conversion system implementation
  - `jtxt.p8`: Japanese text display
  - `bmem.p8`: Bank memory management
- Conversion tools:
  - `dicconv/`: Dictionary conversion tools
    - `dicconv.py`: Tool to convert SKK dictionary to binary format
  - `fontconv/`: Font conversion tools
    - `mkfont.py`: Tool to convert font images to binary format

## License

This software is released under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

Special thanks to:

- The Commander X16 development team
  - For providing an excellent retro computer platform
- Namu Kadoma
  - For providing beautiful Japanese fonts 