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

1. The installed plugin is its own git clone of this repo (per the README),
   not a symlink to your working checkout:
   ```bash
   git clone https://github.com/anwarahmed/omarchy-prayer-times.git ~/.config/omarchy/plugins/anwar.prayer-times
   omarchy bar put anwar.prayer-times --after omarchy.weather
   ```
2. Edit `Panel.qml` / `Model.js`. Changes under `~/.config/omarchy/plugins/`
   hot-reload automatically, so to see a change from another checkout,
   `git pull` it into that clone once it's on `main` (or edit there directly
   while iterating). Hot-reload isn't reliable, though: after the icon change
   was pulled, the shell logged reloading this plugin (and
   `omarchy-shell shell rescanPlugins` ran) but kept showing the old icon.
   If a change doesn't show up, restart the shell with
   `omarchy-restart-shell`. It keeps `shell.json`, unlike
   `omarchy-refresh-shell`, which resets it to defaults. Check what's actually
   on screen with a screenshot, e.g. `grim -g "0,0 1536x40" bar.png`.
3. There are no automated tests. `Model.js` is written to be pure/testable in
   isolation (it CommonJS-exports its functions when `module` is defined) even
   though no test harness currently exercises it — keep new logic there
   side-effect free for the same reason.

## Changes and releases

- Every change lands on `main` through a PR from a short-lived branch, merged
  with **squash**. Delete the branch locally and on GitHub afterwards.
- The plugin version is the `version` field in `manifest.json`, using semver.
  Bump it in its own PR (`Bump version to X.Y.Z`); so far, fixes and small
  behaviour/visual changes have been patch bumps.
- After the bump PR merges, create an annotated tag `vX.Y.Z` on the bump
  commit, push it, then create a GitHub release from the tag with
  `gh release create vX.Y.Z --verify-tag`. The release notes list the merged
  PRs by number, give the update command
  (`cd ~/.config/omarchy/plugins/anwar.prayer-times && git pull`), and end
  with a `compare/vPREV...vX.Y.Z` "Full changelog" link.
- `v1.0.0` tags the initial commit (`c64de4d`). Its GitHub release was added
  after `v1.0.1`'s and isn't marked latest; pass `--latest=false` when
  creating a release for anything other than the newest version.

## Bar icon

The bar icon (`barIcon` in `Panel.qml`) must be a single-color Nerd Font
glyph that renders in JetBrainsMono Nerd Font. Other Omarchy bar widgets use
Material Design (`nf-md-*`, `U+F0xxx`) glyphs, so prefer those. It's currently
`nf-md-star_crescent` (`U+F0979`). Avoid `nf-md-mosque` (`U+F0D45`), which
draws an unrelated glyph in this font; `nf-md-mosque_outline` (`U+F1827`)
works if a mosque is wanted. Check a candidate by rendering it, e.g.
`pango-view --font="JetBrainsMono Nerd Font 36" --text="$(printf '\U000F0979')" -o out.png`.

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
