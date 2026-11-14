# TV Remote App

A free, open-source universal Wi-Fi remote for smart TVs, for Android and iOS (Flutter). No ads, no tracking, no paywall.

**Supports** (all over Wi-Fi, no IR): LG webOS, Samsung (2013 and older, 2014-2015, and 2016 or newer), Amazon Fire TV, Roku, and Android TV / Google TV (which covers Sony, Philips, TCL, Hisense, Nvidia Shield and more).

**Status:** early development. The protocols are implemented from public documentation and checked against open-source reference libraries where possible, but most have not been verified on real TVs yet; see `docs/lg-hardware-checklist.md` for what to try on each TV.

## Docs
- Design: `docs/superpowers/specs/2026-11-13-tv-remote-design.md`
- Implementation plan: `docs/superpowers/plans/2026-11-13-foundation-and-lg.md`
- Privacy policy: `docs/PRIVACY.md`

## Development
```
flutter pub get
flutter test
flutter analyze
```

## License
Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option.
