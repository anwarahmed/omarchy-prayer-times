# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Omarchy shell plugin (`anwar.prayer-times`) — a bar widget written in QML for
[Quickshell](https://quickshell.org/) that shows the next Islamic prayer time and
countdown, with a click-to-open detail panel. It's declared entirely by
`manifest.json` (schema, settings schema, entry point) and `Panel.qml`
(UI + all runtime logic), with `Model.js` holding pure, side-effect-free helper
functions used by `Panel.qml`.

There is no build step, package manager, or test runner in this repo — it's
plain QML/JS consumed directly by the Omarchy shell at runtime.

## Development workflow

This plugin only runs inside an Omarchy shell environment (it imports
`Quickshell`, `qs.Commons`, `qs.Ui`, and the `Panel`/`KeyboardPanel` base
components those provide), so there is no standalone way to run or test it in
this repo. To iterate:

1. Symlink the repo into the Omarchy plugin directory:
   ```bash
   ln -s "$(pwd)" ~/.config/omarchy/plugins/anwar.prayer-times
   omarchy bar put anwar.prayer-times --after omarchy.weather
   ```
2. Edit `Panel.qml` / `Model.js` — changes under
   `~/.config/omarchy/plugins/` hot-reload automatically. Force a reload with
   `omarchy-shell shell rescanPlugins` if a change doesn't pick up.
3. There are no automated tests. `Model.js` is written to be pure/testable in
   isolation (it CommonJS-exports its functions when `module` is defined) even
   though no test harness currently exercises it — keep new logic there
   side-effect free for the same reason.

## Architecture

- **`manifest.json`** — plugin metadata consumed by the Omarchy shell: the bar
  widget entry point (`Panel.qml`), default settings, and the settings
  `schema` array (calculation method, Asr school, time format) that drives the
  in-shell settings UI as well as `Panel.qml`'s own in-panel settings screen.
  Keep the two in sync — e.g. option values in `Model.js`'s
  `CALCULATION_METHODS`/`ASR_SCHOOLS`/`TIME_FORMATS` must match the `options`
  arrays here.

- **`Model.js`** — pure helpers with no Quickshell/QML dependency: parsing
  `weather.json` and the wttr.in IP-geolocation response, building the day's
  prayer schedule, finding the next prayer, and formatting times/countdowns.
  Anything that can be expressed as a pure function of inputs → output belongs
  here rather than in `Panel.qml`, both for testability and so the two files
  stay separable.

- **`Panel.qml`** — everything else: the bar button, the detail/settings
  panel UI, and all stateful/async logic (`Process`/`FileView`/`Timer`
  Quickshell elements). Key flows:
  - **Location resolution**: watches
    `~/.local/state/omarchy/settings/weather.json` (owned by
    `omarchy-weather-location`, shared with the built-in Weather widget) via
    `FileView`. If it has no coordinates, falls back to IP geolocation by
    curling `https://wttr.in/?format=j1` and reading `nearest_area` — see the
    comment in `Model.js` on why coordinates come from wttr.in's IP detection
    rather than geocoding a bare city name (ambiguous results, e.g.
    "Scarborough" → Tobago instead of the intended Toronto suburb).
  - **Prayer time fetching**: curls the
    [Aladhan API](https://aladhan.com/prayer-times-api)
    (`api.aladhan.com/v1/timings/{DD-MM-YYYY}`) for both today and tomorrow —
    tomorrow's Fajr is needed to resolve the countdown correctly after
    tonight's Isha, until the next scheduled refetch.
  - **Retries**: location resolution and each day's timings fetch each retry
    independently up to 3 times on failure, via their own `Timer`s
    (`locationRetryTimer`, `todayRetryTimer`, `tomorrowRetryTimer`).
  - **Refresh cadence**: `dailyRefreshTimer` refetches everything every 6h
    (date rollover, DST, location drift); `tickTimer` re-renders the countdown
    text every 30s with no network call.
  - **Settings**: `draftSettings` holds in-progress edits in the settings
    view; `saveSettings()` commits them to `root.settings` and, when the host
    shell exposes `bar.shell.updateEntryInline`, persists them to
    `shell.json` — otherwise the save is session-only (see
    `canPersistSettings()`).
  - **Controls**: left click toggles the panel, middle click refreshes
    (re-resolves location + refetches), right click jumps straight to
    settings; inside the panel, `s` opens/saves settings, `r` refreshes, `Esc`
    closes (wired through `PanelKeyCatcher`).
