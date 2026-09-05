# Contributing to FinderConvert

Thanks for your interest! Bug reports, feature requests, and pull requests are all welcome.

## Reporting bugs

Open an issue with the bug report template. The most useful reports include:

- macOS version and Mac model (Apple Silicon or Intel)
- The exact conversion that failed (input format → output format)
- What happened vs. what you expected
- If relevant, a sample file that reproduces the problem (strip anything private first)

## Building from source

Requirements: macOS 14+, Xcode 16+, Swift 6.

```bash
bash scripts/build-and-sign.sh   # build, sign, install to /Applications, register the extension
bash scripts/preview.sh          # fast UI iteration: rebuilds and relaunches a preview app on save
```

The project layout is described in the README's Architecture section. The short version:

- `FinderConvertCore/` — SPM package with all conversion logic (engines, registry, detection, naming). Most changes happen here.
- `FinderConvert/FinderConvertApp.swift` — the SwiftUI app (UI tabs, menu bar, drag & drop).
- `FinderConvertActionExtension/` — the Finder right-click extension.

Run tests with:

```bash
xcodebuild -project FinderConvert.xcodeproj -scheme FinderConvert -destination 'platform=macOS' test
```

## Pull requests

- Keep PRs focused — one fix or feature per PR.
- Match the surrounding code style; the codebase is plain Swift with no linter config yet.
- Commit messages follow Conventional Commits: `type(scope): summary` (types: feat, fix, refactor, chore, docs, test).
- New conversion engines should implement `ConversionEngine` and be registered in `ConversionRegistry`.
- Adding tests with your change is very welcome — automated coverage is currently thin and it's the area that most needs help.

## Licensing

FinderConvert is GPL-3.0. By contributing, you agree your contributions are licensed under the same terms.
