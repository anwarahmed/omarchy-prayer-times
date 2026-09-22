# Prayer Times — Omarchy shell plugin

Shows the next Islamic prayer time and a countdown in the Omarchy bar,
right alongside the clock and weather widgets. Click it for a detail panel
listing all five daily prayers plus Sunrise.

## Location

Reuses whatever location the Weather widget is already configured for
(`~/.local/state/omarchy/settings/weather.json`, owned by
`omarchy-weather-location`). If nothing is configured there, falls back to
IP-based geolocation automatically.

To set an explicit location (also updates the Weather widget):

```bash
omarchy-weather-location --set "Alexandria, VA" 38.8048,-77.0469
```

## Prayer time source

Times come from the [Aladhan API](https://aladhan.com/prayer-times-api).
Right-click the widget (or use the in-panel Settings screen) to change the
calculation method and Asr juristic method (Standard vs. Hanafi).

## Installing

Clone this repo directly into `~/.config/omarchy/plugins/anwar.prayer-times/`
and add it to the bar:

```bash
git clone https://github.com/anwarahmed/omarchy-prayer-times.git ~/.config/omarchy/plugins/anwar.prayer-times
omarchy bar put anwar.prayer-times --after omarchy.weather
```

To update, pull the latest changes in that directory:

```bash
cd ~/.config/omarchy/plugins/anwar.prayer-times && git pull
```

Edits under `~/.config/omarchy/plugins/` are supposed to hot-reload
automatically, but that doesn't always work. If the bar still shows the old
version after an update, restart the shell:

```bash
omarchy-restart-shell
```

## Controls

- **Left click** — open/close the detail panel
- **Middle click** — refresh (re-resolve location + refetch times)
- **Right click** — open settings directly
- Inside the panel: `s` opens/saves settings, `r` refreshes, `Esc` closes
