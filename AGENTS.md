# Repository working agreements

## Colors

- Use colors from the active Omarchy system theme. Do not hard-code UI colors.
- Pass semantic colors down from `Panel.qml` as **required** component
  properties, so a theme change propagates through every view and a component
  cannot quietly fall back to a literal.
- `ThemePalette.rise` and `ThemePalette.fall` carry market direction. They read
  the theme's own ANSI green and red, because the shell's `Color` singleton
  exposes red as `urgent` but has no green role at all.
- Everything else derives from `Color.foreground`, `Color.background`,
  `Color.accent` or `Color.urgent`, with muted, hover and selected variants
  produced by alpha on an inherited color — never by a second hex value.
- `ThemePalette.qml` is the one file allowed to contain a hex pattern, and only
  because it is parsing the theme's `colors.toml`, not painting with it.
- `tests/test_panel_source.sh` enforces this. Keep it updated rather than
  working around it.

## Color is never the only indicator

A rise and a fall must be separable without seeing color:

- percentages always carry their sign (`+0.94%`, `-2.17%`),
- a flat row takes the neutral foreground rather than the rise color,
- feed state shows a labelled `LIVE` / `LOADING` / `OFFLINE`, not just a dot.

## The data layer is a port, not a rewrite

`Market.js`, `SymbolID.js` and `YahooAdapter.js` are ports of PulseCore's
`Market.swift`, `SymbolID.swift` and `YahooProvider.swift`. When the two
disagree, the Swift version is the reference implementation — it is the one
that has been in front of users. Port the behavior, including the reasons in
its comments; do not improve it in passing and do not drop a case because the
plugin does not reach it yet.

The one deliberate divergence is symbol validation. Pulse gets every symbol
from a provider's search index, so it never needs to check one. Here the
watchlist is a file a person edits by hand, so `SymbolID.create` refuses a code
that cannot resolve rather than creating a row that can never quote.

## JavaScript modules

QML resources declare dependencies with `.import "X.js" as X`, which must be
the first statements in the file. That is not valid JavaScript, so the Node
tests load these files through `tests/qmljs.js`, which rewrites `.import` into
`require`. Keep that shim literal: if it starts interpreting, the tests stop
testing what the shell runs.

Every module ends with a `typeof module !== "undefined"` export guard so the
same file works in both places.

## Requests

Yahoo rate-limits hard per IP and answers one symbol per request. Requests are
serialised through a queue with a one-second spacing, and a closed market is
not polled at all. Do not add a parallel fan-out, a shorter floor than the
15-second clamp in `Watchlist.qml`, or a refresh on a timer faster than the
source can actually change.

## Tests

`make test` runs the JavaScript reducers and the source checks; `make validate`
adds `qmllint` and `omarchy plugin validate`. `qmllint` cannot resolve `qs.Ui`
or `qs.Commons` outside the quickshell runtime, so those import warnings are
expected — the reference Omarchy plugins produce them too. The real runtime
check is installing the plugin and calling `omarchy-shell pulse.omarchy status`.
