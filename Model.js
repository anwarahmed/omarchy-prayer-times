// Pure helpers for the Prayer Times plugin. Kept side-effect free so they
// can be reasoned about (and unit tested) independent of QML/Quickshell.

// weather.json holds {"name": ..., "latitude": ..., "longitude": ...} (see
// omarchy-weather-location, which owns the format). Missing, blank, or
// unparseable means the location must fall back to IP geolocation. Reusing
// this file keeps prayer times pinned to the same location as the bar's
// weather widget instead of asking the user to configure a second one.
function parseLocationFile(raw) {
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset

    var latitude = parseFloat(data.latitude)
    var longitude = parseFloat(data.longitude)
    var hasCoordinates = !isNaN(latitude) && !isNaN(longitude)
    return {
      name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
      latitude: hasCoordinates ? latitude : null,
      longitude: hasCoordinates ? longitude : null
    }
  } catch (e) {
    return unset
  }
}

// wttr.in's full j1 response (https://wttr.in/?format=j1) carries precise
// IP-detected coordinates in nearest_area — the same field the built-in
// Weather widget uses for its own IP auto-detect. Geocoding a bare city name
// instead is ambiguous (e.g. "Scarborough" resolves to Tobago via Open-Meteo
// when the IP-detected one is a Toronto suburb), so read coordinates
// straight off this response rather than re-deriving them from the name.
function parseIpLocation(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    var area = data && data.nearest_area && data.nearest_area[0]
    if (!area) return null
    var lat = parseFloat(area.latitude)
    var lon = parseFloat(area.longitude)
    if (isNaN(lat) || isNaN(lon)) return null
    var city = area.areaName && area.areaName[0] ? area.areaName[0].value : ""
    var country = area.country && area.country[0] ? area.country[0].value : ""
    var name = [city, country].filter(function(p) { return !!p }).join(", ")
    return { name: name, latitude: lat, longitude: lon }
  } catch (e) {
    return null
  }
}

function pad2(n) {
  n = Math.floor(n)
  return (n < 10 ? "0" : "") + n
}

// Aladhan's /v1/timings/{date} expects DD-MM-YYYY.
function dateParam(date) {
  return pad2(date.getDate()) + "-" + pad2(date.getMonth() + 1) + "-" + date.getFullYear()
}

// Aladhan appends a timezone abbreviation, e.g. "05:12 (EDT)". Strip it.
function stripTimezone(value) {
  return String(value || "").split(" ")[0]
}

var TIMING_KEYS = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]

// Aladhan /v1/timings response -> {Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha}
// (each "HH:mm"), or null if the response doesn't look like a timings payload.
function parseTimingsResponse(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var timings = data && data.data && data.data.timings
    if (!timings) return null
    var out = {}
    for (var i = 0; i < TIMING_KEYS.length; i++) {
      var key = TIMING_KEYS[i]
      out[key] = stripTimezone(timings[key])
    }
    return out
  } catch (e) {
    return null
  }
}

// Combine a "HH:mm" time-of-day with a calendar date into a concrete Date.
function timeStringToDate(dateObj, hhmm) {
  var parts = String(hhmm || "").split(":")
  if (parts.length < 2) return null
  var h = parseInt(parts[0], 10)
  var m = parseInt(parts[1], 10)
  if (isNaN(h) || isNaN(m)) return null
  return new Date(dateObj.getFullYear(), dateObj.getMonth(), dateObj.getDate(), h, m, 0, 0)
}

var PRAYER_ORDER = [
  { key: "Fajr", label: "Fajr", info: false },
  { key: "Sunrise", label: "Sunrise", info: true },
  { key: "Dhuhr", label: "Dhuhr", info: false },
  { key: "Asr", label: "Asr", info: false },
  { key: "Maghrib", label: "Maghrib", info: false },
  { key: "Isha", label: "Isha", info: false }
]

// Builds the ordered day schedule: today's six markers plus tomorrow's Fajr
// appended so "next prayer" can resolve correctly after tonight's Isha.
// `info` entries (Sunrise) are shown but never treated as a "next" target.
function buildSchedule(todayTimings, tomorrowTimings, todayDate, tomorrowDate) {
  var list = []
  if (todayTimings) {
    for (var i = 0; i < PRAYER_ORDER.length; i++) {
      var entry = PRAYER_ORDER[i]
      list.push({
        key: entry.key,
        label: entry.label,
        info: entry.info,
        tomorrow: false,
        time: timeStringToDate(todayDate, todayTimings[entry.key])
      })
    }
  }
  if (tomorrowTimings && tomorrowTimings.Fajr) {
    list.push({
      key: "Fajr",
      label: "Fajr",
      info: false,
      tomorrow: true,
      time: timeStringToDate(tomorrowDate, tomorrowTimings.Fajr)
    })
  }
  return list
}

// First non-info entry strictly after `nowMs`, or null if the schedule is
// empty/unresolved (e.g. still waiting on the first fetch).
function nextPrayer(schedule, nowMs) {
  for (var i = 0; i < schedule.length; i++) {
    var entry = schedule[i]
    if (entry.info || !entry.time) continue
    if (entry.time.getTime() > nowMs) return entry
  }
  return null
}

function formatRemaining(ms) {
  if (ms === undefined || ms === null || isNaN(ms) || ms < 0) ms = 0
  var totalMin = Math.floor(ms / 60000)
  var h = Math.floor(totalMin / 60)
  var m = totalMin % 60
  if (h > 0) return h + "h " + m + "m"
  if (m > 0) return m + "m"
  return "<1m"
}

function formatClock(hhmmOrDate, use24h) {
  var h, m
  if (hhmmOrDate instanceof Date) {
    h = hhmmOrDate.getHours()
    m = hhmmOrDate.getMinutes()
  } else {
    var parts = String(hhmmOrDate || "").split(":")
    if (parts.length < 2) return String(hhmmOrDate || "")
    h = parseInt(parts[0], 10)
    m = parseInt(parts[1], 10)
    if (isNaN(h) || isNaN(m)) return String(hhmmOrDate || "")
  }
  if (use24h) return pad2(h) + ":" + pad2(m)
  var period = h >= 12 ? "PM" : "AM"
  var h12 = h % 12
  if (h12 === 0) h12 = 12
  return h12 + ":" + pad2(m) + " " + period
}

var CALCULATION_METHODS = [
  { value: "3", label: "Muslim World League" },
  { value: "2", label: "Islamic Society of North America (ISNA)" },
  { value: "5", label: "Egyptian General Authority" },
  { value: "4", label: "Umm al-Qura, Makkah" },
  { value: "1", label: "University of Islamic Sciences, Karachi" },
  { value: "8", label: "Gulf Region" },
  { value: "9", label: "Kuwait" },
  { value: "10", label: "Qatar" },
  { value: "11", label: "Singapore" },
  { value: "13", label: "Diyanet (Turkey)" },
  { value: "15", label: "Moonsighting Committee Worldwide" }
]

var ASR_SCHOOLS = [
  { value: "0", label: "Standard", tooltip: "Shafi‘i, Maliki, Hanbali" },
  { value: "1", label: "Hanafi" }
]

var TIME_FORMATS = [
  { value: "12h", label: "12-hour" },
  { value: "24h", label: "24-hour" }
]

function methodLabel(value) {
  for (var i = 0; i < CALCULATION_METHODS.length; i++)
    if (CALCULATION_METHODS[i].value === String(value)) return CALCULATION_METHODS[i].label
  return String(value)
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLocationFile: parseLocationFile,
    parseIpLocation: parseIpLocation,
    pad2: pad2,
    dateParam: dateParam,
    stripTimezone: stripTimezone,
    parseTimingsResponse: parseTimingsResponse,
    timeStringToDate: timeStringToDate,
    buildSchedule: buildSchedule,
    nextPrayer: nextPrayer,
    formatRemaining: formatRemaining,
    formatClock: formatClock,
    CALCULATION_METHODS: CALCULATION_METHODS,
    ASR_SCHOOLS: ASR_SCHOOLS,
    TIME_FORMATS: TIME_FORMATS,
    methodLabel: methodLabel
  }
}
