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

Copy or symlink this folder into `~/.config/omarchy/plugins/anwar.prayer-times/`,
then add it to the bar:

```bash
ln -s "$(pwd)" ~/.config/omarchy/plugins/anwar.prayer-times
omarchy bar put anwar.prayer-times --after omarchy.weather
```

Edits under `~/.config/omarchy/plugins/` hot-reload automatically; force a
reload with `omarchy-shell shell rescanPlugins` if a change doesn't pick up.

## Controls

- **Left click** — open/close the detail panel
- **Middle click** — refresh (re-resolve location + refetch times)
- **Right click** — open settings directly
- Inside the panel: `s` opens/saves settings, `r` refreshes, `Esc` closes
