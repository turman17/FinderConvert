# FinderConvert

A native macOS utility that adds file conversion directly to Finder's right-click menu. Convert images, videos, audio, documents, and spreadsheets without opening separate apps.

## Features

### Supported Formats

| Category | Input | Output |
|----------|-------|--------|
| **Image** | JPEG, PNG, HEIC, TIFF, GIF, WebP, BMP, SVG, AVIF | JPEG, PNG, HEIC, TIFF, GIF, BMP, ICO, AVIF, WebP |
| **Video** | MP4, MOV, WebM | MP4, MOV, HEVC, GIF (animated) |
| **Audio** | MP3, M4A, WAV, AIFF, FLAC, OGG | MP3, M4A, WAV, AIFF, FLAC |
| **Document** | PDF, RTF, HTML, TXT, Markdown, DOCX, EPUB | PDF, RTF, HTML, TXT, DOCX |
| **Spreadsheet** | CSV, TSV, XLSX, JSON | CSV, TSV, XLSX |

### Key Capabilities

- **Right-click conversion** -- select files in Finder, right-click, choose target format
- **Folder conversion** -- right-click a folder to convert all files inside, preserving directory structure
- **Multi-sheet XLSX** -- splits into one CSV/TSV per sheet in a named folder
- **Multi-page PDF** -- splits into one image per page in a named folder
- **PDF merge** -- select multiple PDFs, merge into one
- **PDF split** -- split a PDF into one file per page
- **Video to audio** -- extract audio track from video (MP4/MOV to MP3/M4A/WAV/AIFF/FLAC)
- **SVG to raster** -- render vector graphics to PNG, JPEG, PDF at high resolution
- **EPUB to PDF/HTML/TXT** -- convert ebooks with chapter ordering
- **Markdown to HTML/PDF** -- renders headings, bold, italic, code blocks, lists, links
- **JSON to CSV/TSV** -- flattens object arrays into tabular format

### Per-Format Settings

Each format has configurable options accessible via the slider icon in the Formats tab:

- **JPEG/HEIC/AVIF/WebP** -- quality slider (10-100%)
- **All image formats** -- resize on convert (100%, 75%, 50%, 25%)
- **MP4/MOV/HEVC** -- export quality (Highest, High, Medium, Low)
- **MP3/M4A** -- bitrate (64, 128, 192, 256 kbps)
- **WAV/AIFF/M4A/MP3/FLAC** -- sample rate (22.05, 44.1, 48 kHz)
- **All image formats** -- strip EXIF/GPS metadata toggle

### App Features

- **Drag & drop converter** -- drop files into the app window, see per-file list, choose format
- **Smart format picker** -- only shows valid output formats for the dropped files
- **Custom output folder** -- choose where converted files go instead of beside the source
- **Preset profiles** -- save and load groups of settings (e.g., "Web optimized")
- **Batch rename** -- customize the output suffix (default: " converted")
- **Conversion history** -- view past conversions with file names, sizes, timestamps
- **Undo** -- trash output files from the history tab
- **Progress indicator** -- shows active conversion status
- **Notifications** -- start/complete notifications for large file conversions

## Prerequisites

- macOS 14 or later
- Xcode 16 or later
- Swift 6

## Build

```bash
bash scripts/build-and-sign.sh
```

This builds the app and extension, signs with ad-hoc identity, installs to `/Applications`, registers the Finder extension, and restarts Finder.

For manual builds:

```bash
xcodebuild -project FinderConvert.xcodeproj -scheme FinderConvert -destination 'platform=macOS' build
```

Run tests:

```bash
xcodebuild -project FinderConvert.xcodeproj -scheme FinderConvert -destination 'platform=macOS' test
```

## Setup

1. Build and install: `bash scripts/build-and-sign.sh`
2. Launch: `open /Applications/FinderConvert.app`
3. Enable the extension: **System Settings > Privacy & Security > Extensions > Finder Extensions** > enable FinderConvert
4. Right-click any file in Finder to see the **Convert File** menu

## Architecture

```
FinderConvert/                    # Main macOS app (SwiftUI)
  FinderConvertApp.swift          # AppDelegate, UI tabs, drag & drop
  AppIcon.icns                    # Anthropic-inspired icon

FinderConvertActionExtension/     # Finder extension (FIFinderSync)
  FinderSyncController.swift      # Context menu, IPC to main app

FinderConvertCore/                # SPM framework (shared logic)
  Sources/FinderConvertCore/
    Models.swift                  # OutputFormat, DetectedFileType, ConversionJob
    ConversionEngine.swift        # Protocol for all engines
    ConversionRegistry.swift      # Routes input+output to correct engine
    FileTypeDetector.swift        # UTType-based file detection
    OutputNaming.swift            # Collision-safe output naming
    PreferencesManager.swift      # Per-format settings, presets, custom output
    ConversionHistory.swift       # History storage
    PdfToolsService.swift         # PDF merge/split
    QuickActionConversionService.swift  # Main conversion orchestrator
    SecurityScopedAccess.swift    # Sandbox bookmark handling
    Engines/
      NativeImageConversionEngine.swift   # Image formats via CGImageDestination + libwebp
      PdfConversionEngine.swift           # PDF <-> image
      VideoConversionEngine.swift         # Video + audio extraction + GIF + HEVC
      AudioConversionEngine.swift         # Audio formats via AVFoundation + LAME MP3
      DocumentConversionEngine.swift      # RTF/HTML/TXT/Markdown + WebKit PDF
      SpreadsheetConversionEngine.swift   # CSV/TSV/XLSX with multi-sheet support
      JsonConversionEngine.swift          # JSON -> CSV/TSV
      SvgConversionEngine.swift           # SVG -> raster/PDF
      EpubConversionEngine.swift          # EPUB -> PDF/HTML/TXT
      DocxWriterEngine.swift              # DOCX output (ZIP+XML)
  Sources/CLame/                  # LAME MP3 encoder (static library)
  Sources/CWebP/                  # libwebp encoder (static library)
```

### Bundled Libraries

- **LAME 3.100** -- MP3 encoding (325 KB static library, LGPL)
- **libwebp 1.3.2** -- WebP encoding (612 KB static library, BSD)

## Configuration

The app uses these bundle identifiers:

- App bundle: `com.finderconvert.app`
- Extension bundle: `com.finderconvert.app.ActionExtension`
- App Group: `group.com.finderconvert.app.shared`

## Testing

The project includes comprehensive automated tests covering all conversion paths. Run the full test suite:

```bash
# Build first
bash scripts/build-and-sign.sh

# Compile and run tests
DERIVED=".local/DerivedData/Build/Products/Debug"
swiftc test_file.swift -I "$DERIVED" "$DERIVED/FinderConvertCore.o" \
    -L FinderConvertCore/Sources/CLame -lmp3lame \
    -L FinderConvertCore/Sources/CWebP -lwebp -lsharpyuv \
    -framework AppKit -framework AVFoundation -framework PDFKit -framework WebKit \
    -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers \
    -framework AudioToolbox \
    -o test_runner && ./test_runner
```

Test coverage includes:
- All format conversion paths (50+ combinations)
- Data integrity (round-trip CSV->XLSX->CSV, TXT->RTF->TXT)
- Real-world XLSX files (multi-sheet, inline strings, shared strings)
- Per-format settings (quality, resize, sample rate, bitrate)
- Folder conversion with nested structure preservation
- PDF merge/split
- Edge cases (empty folders, single-page PDFs, sparse XLSX columns)

## License

Third-party notices: see `THIRD_PARTY_NOTICES.md`
