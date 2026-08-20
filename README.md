# Pulse for Omarchy

**Glanceable market data in the Omarchy bar.**

A port of [Pulse](https://github.com/fatwang2/Pulse) — the macOS menu-bar
market watcher — to the Omarchy shell. Same idea, same data model: see how the
symbols you care about are doing in the shortest possible time, without leaving
what you are working on. It is a market watcher, not a trading terminal.

## Requirements

- Omarchy 4 (the Quickshell-based `omarchy-shell`)
- Internet access

There is no account, no API key and no daemon. Quotes come from public
endpoints, and the plugin says which source and what delay is behind every
number.

## Install

```bash
omarchy plugin add https://github.com/fatwang2/omarchy-pulse.git --enable
```

For development, symlink this checkout into Omarchy instead:

```bash
./install.sh          # add --no-restart to leave the running shell alone
```

Either way the first install seeds a starter watchlist at
`~/.config/omarchy/pulse/watchlist.json` and never touches it again.

## The watchlist

Omarchy configures through files, so the watchlist is a file. Edits land
without restarting the shell — save it and the rows change.

```json
{
  "version": 1,
  "symbols": ["AAPL", "NVDA", "^GSPC", "00700.HK", "600519.SH", "7203.T", "005930.KS"],
  "pollIntervalSeconds": 60,
  "barDisplay": "icon",
  "pinnedSymbol": "NVDA",
  "carouselIntervalSeconds": 6
}
```

| Key | What it does |
|---|---|
| `symbols` | What to watch, in the order you want it grouped |
| `pollIntervalSeconds` | Refresh cadence, clamped to 15–3600 |
| `barDisplay` | `icon` (discreet), `pinned` (one quote in the bar), `carousel` (rotates) |
| `pinnedSymbol` | Which symbol `pinned` shows |
| `carouselIntervalSeconds` | How long each symbol holds the bar in `carousel` |

### Writing symbols

A symbol is written the way Pulse writes it: an exchange code with a market
suffix, and no suffix for the US.

| Market | Form | Example |
|---|---|---|
| US | bare ticker | `AAPL`, `BRK-B` |
| Hong Kong | `.HK` | `00700.HK` (stored as `700.HK`) |
| Shanghai / Shenzhen | `.SH` / `.SZ` | `600519.SH`, `300750.SZ` |
| Tokyo | `.T` | `7203.T` |
| Korea | `.KS` (KOSPI) / `.KQ` (KOSDAQ) | `005930.KS`, `035720.KQ` |
| Indices | semantic code or a vendor spelling | `^GSPC`, `SPX`, `INX`, `^HSI`, `N225` |
| Metals | contract code | `GC`, `SI`, `PL`, `PA` |

The Korean board is part of the address and cannot be derived from the code —
`035720` is KOSPI even though its neighbours are not — so `.KS` and `.KQ` name
different things and are not interchangeable.

A code that cannot resolve is dropped rather than kept as a row that can never
quote, so a typo shows up as a missing row, not a permanently blank one.

## Reading the panel

- Rows are grouped by market and hold watchlist order inside a market. Nothing
  re-sorts on a value that moves — ordering that shuffles as prices tick is
  worse than ordering that holds still.
- Both Chinese boards share one `CN` badge and both Korean boards share `KR`;
  which board a symbol sits on is already in its suffix.
- `LIVE` / `LOADING` / `OFFLINE` sits where a refresh button would be. The
  panel either has current prices or says why it does not.
- `STALE` means a price has stopped arriving **while its market is open**, past
  the source's own delay. A closed market's last print is the close — final,
  not stale — and is never marked.
- Press `/` or `f` to filter, `r` to refresh, `↑`/`↓` to move, `Enter` for the
  quote detail, `Esc` to back out.

## Data

Quotes come from Yahoo Finance's chart endpoint, covering US, Hong Kong,
Shanghai, Shenzhen, Tokyo, both Korean boards and the COMEX/NYMEX metal
contracts. US symbols are read over an extended-session window, so a pre- or
post-market price shows as such and is measured against the regular close
rather than yesterday's.

Delay is per market and is shown in the quote detail: the US is real time,
Hong Kong and the Chinese boards about fifteen minutes, Tokyo and Seoul about
twenty, the metal contracts about ten.

Requests are serialised one symbol per second, and a closed market is not
polled at all. A twenty-symbol watchlist therefore refreshes over twenty
seconds and never trips the rate limit.

### Not yet wired

The macOS app routes across several sources; this port currently ships one.
Still to come: crypto through Binance (including the 1-second websocket
ticker), spot precious metals and the Shanghai Gold Exchange, Korean real-time
and Korean-language search through Naver, the Sina and Tencent providers,
Longbridge real-time for HK/US/A-shares, charts, and position tracking. The
symbol layer already models all of them, which is why `BTC/USDT` and `XAU`
parse but are refused by the Yahoo adapter rather than quietly priced off the
wrong instrument.

## IPC

```bash
omarchy-shell pulse.omarchy toggle
omarchy-shell pulse.omarchy refresh
omarchy-shell pulse.omarchy status   # symbols, quote count, per-row errors, feed state
```

## Development

```bash
make test       # JavaScript reducers and source regression checks
make validate   # the above, plus qmllint and omarchy plugin validate
```

`qmllint` cannot resolve `qs.Ui` and `qs.Commons` outside the quickshell
runtime; those import warnings are expected and the first-party Omarchy plugins
produce them too.

See [AGENTS.md](AGENTS.md) for the working agreements — theming rules, why the
data layer is a port rather than a rewrite, and how the JavaScript modules are
shared between QML and Node.

## License

MIT. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
