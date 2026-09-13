import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget + detail panel showing the next Islamic prayer time.
//
// Location: reused from ~/.local/state/omarchy/settings/weather.json (the
// same file `omarchy-weather-location` and the Weather bar widget use), so
// this widget tracks wherever weather is already configured for. If that
// file has no coordinates yet, falls back to IP geolocation.
//
// Times: fetched from the Aladhan API (https://aladhan.com/prayer-times-api)
// for today and tomorrow (tomorrow only to resolve the countdown after
// tonight's Isha, until the next scheduled refetch).
Panel {
  id: root
  moduleName: "anwar.prayer-times"
  ipcTarget: "anwar.prayer-times"

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.45)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"
  // U+F186 (nf-fa-moon_o): the color mosque emoji broke the bar's flat,
  // monochrome icon style (every other widget renders a single-color Nerd
  // Font glyph). This crescent renders correctly in JetBrainsMono Nerd Font;
  // nf-md-mosque does not (falls back to an unrelated glyph in this font).
  readonly property string barIcon: ""

  readonly property string calcMethod: setting("calculationMethod", "3")
  readonly property string asrSchool: setting("asrSchool", "0")
  readonly property bool use24h: setting("timeFormat", "12h") === "24h"

  property var locationState: ({ name: "", latitude: null, longitude: null })
  property bool locationFromIp: false
  property bool locationResolving: true
  property int locationRetries: 0

  property var todayTimings: null
  property var tomorrowTimings: null
  property int todayRetries: 0
  property int tomorrowRetries: 0

  property real nowMs: Date.now()

  property bool settingsMode: false
  property var draftSettings: ({})
  property string settingsStatusText: ""

  readonly property var schedule: Model.buildSchedule(todayTimings, tomorrowTimings, new Date(), tomorrowDateObj())
  readonly property var displaySchedule: schedule.filter(function(e) { return !e.tomorrow })
  readonly property var nextEntry: Model.nextPrayer(schedule, nowMs)

  readonly property string locationLabel: locationResolving
    ? "Locating…"
    : (locationState.name || "Unknown location") + (locationFromIp ? " (IP)" : "")

  readonly property string barText: nextEntry
    ? barIcon + " " + nextEntry.label + " " + Model.formatRemaining(nextEntry.time.getTime() - nowMs)
    : barIcon

  function tomorrowDateObj() {
    var d = new Date()
    d.setDate(d.getDate() + 1)
    return d
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // ---- Location resolution --------------------------------------------

  FileView {
    id: weatherFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyWeatherLocation(Model.parseLocationFile(text()))
    onLoadFailed: root.applyWeatherLocation(Model.parseLocationFile(""))
  }

  function applyWeatherLocation(parsed) {
    if (parsed.latitude !== null && parsed.longitude !== null) {
      root.locationState = parsed
      root.locationFromIp = false
      root.locationResolving = false
      root.fetchTimings()
    } else if (!ipLocationProc.running) {
      ipLocationProc.running = true
    }
  }

  Process {
    id: ipLocationProc
    command: ["curl", "-fsS", "--max-time", "8", "https://wttr.in/?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseIpLocation(text)
        if (parsed) {
          root.locationResolving = false
          root.locationRetries = 0
          root.locationState = parsed
          root.locationFromIp = true
          root.fetchTimings()
        } else {
          root.scheduleLocationRetry()
        }
      }
    }
  }

  function scheduleLocationRetry() {
    if (locationRetries >= 3) { root.locationResolving = false; return }
    locationRetries++
    locationRetryTimer.restart()
  }

  Timer {
    id: locationRetryTimer
    interval: 4000
    onTriggered: if (!ipLocationProc.running) ipLocationProc.running = true
  }

  // ---- Prayer time fetching ---------------------------------------------

  function fetchTimings() {
    var lat = root.locationState.latitude
    var lon = root.locationState.longitude
    if (lat === null || lon === null || lat === undefined || lon === undefined) return

    var params = "?latitude=" + encodeURIComponent(String(lat))
      + "&longitude=" + encodeURIComponent(String(lon))
      + "&method=" + encodeURIComponent(root.calcMethod)
      + "&school=" + encodeURIComponent(root.asrSchool)
    var base = "https://api.aladhan.com/v1/timings/"

    todayProc.command = ["curl", "-fsS", "--max-time", "8", base + Model.dateParam(new Date()) + params]
    todayProc.running = true
    tomorrowProc.command = ["curl", "-fsS", "--max-time", "8", base + Model.dateParam(tomorrowDateObj()) + params]
    tomorrowProc.running = true
  }

  function refresh() {
    locationRetries = 0
    todayRetries = 0
    tomorrowRetries = 0
    locationResolving = true
    weatherFile.reload()
  }

  Process {
    id: todayProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseTimingsResponse(text)
        if (parsed) { root.todayTimings = parsed; root.todayRetries = 0 }
        else root.scheduleTodayRetry()
      }
    }
  }

  function scheduleTodayRetry() {
    if (todayRetries >= 3) return
    todayRetries++
    todayRetryTimer.restart()
  }

  Timer {
    id: todayRetryTimer
    interval: 3000
    onTriggered: if (!todayProc.running) todayProc.running = true
  }

  Process {
    id: tomorrowProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseTimingsResponse(text)
        if (parsed) { root.tomorrowTimings = parsed; root.tomorrowRetries = 0 }
        else root.scheduleTomorrowRetry()
      }
    }
  }

  function scheduleTomorrowRetry() {
    if (tomorrowRetries >= 3) return
    tomorrowRetries++
    tomorrowRetryTimer.restart()
  }

  Timer {
    id: tomorrowRetryTimer
    interval: 3000
    onTriggered: if (!tomorrowProc.running) tomorrowProc.running = true
  }

  // Refetch periodically to pick up date rollover, DST, and any location
  // change beyond what the weather.json watch already reruns.
  Timer {
    id: dailyRefreshTimer
    interval: 6 * 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Cheap re-render of the countdown text; no network involved.
  Timer {
    id: tickTimer
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Component.onCompleted: root.refresh()

  // ---- Settings -----------------------------------------------------

  function canPersistSettings() {
    return !!(bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
  }

  function openSettings() {
    draftSettings = {
      calculationMethod: root.calcMethod,
      asrSchool: root.asrSchool,
      timeFormat: setting("timeFormat", "12h")
    }
    settingsStatusText = ""
    settingsMode = true
    open()
  }

  function showMain() {
    settingsMode = false
    settingsStatusText = ""
  }

  function saveSettings() {
    root.settings = draftSettings
    if (canPersistSettings()) {
      bar.shell.updateEntryInline(root.moduleName, draftSettings)
      settingsStatusText = "Saved to shell.json"
    } else {
      settingsStatusText = "Saved for this session"
    }
    fetchTimings()
  }

  function triggerPress(button) {
    if (button === Qt.RightButton) { openSettings(); return }
    if (button === Qt.MiddleButton) { refresh(); return }
    if (opened) {
      close()
    } else {
      // Always land on the times view on open, even if settings was left
      // showing last time it closed. Right-click still goes straight to
      // settings via openSettings() above.
      settingsMode = false
      open()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText
    // Suppressed: the panel is the detail view (same convention as
    // omarchy.weather), so a stale hover tooltip can't linger on top of it
    // when a click opens the panel mid-hover.
    tooltipText: ""
    onPressed: function(b) { root.triggerPress(b) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.settingsMode ? root.saveSettings() : root.openSettings()
        if (t === "r" || t === "R") root.refresh()
      }

      ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: root.settingsMode ? "Prayer Times Settings" : "Prayer Times"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
          }

          TooltipButton {
            visible: root.settingsMode
            text: "Times"
            foreground: root.fg
            tooltip: "Back to prayer times"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.showMain()
          }

          TooltipButton {
            visible: root.settingsMode
            text: "Save"
            foreground: root.fg
            tooltip: "Save settings"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            active: true
            onClicked: root.saveSettings()
          }

          TooltipButton {
            visible: !root.settingsMode
            text: "Settings"
            foreground: root.fg
            tooltip: "Prayer time settings"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.openSettings()
          }

          TooltipButton {
            visible: !root.settingsMode
            text: "Refresh"
            foreground: root.fg
            tooltip: "Refresh prayer times"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.refresh()
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.fg
        }

        // ---- Main view ------------------------------------------------

        ColumnLayout {
          visible: !root.settingsMode
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            Layout.fillWidth: true
            text: root.locationLabel
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          BorderSurface {
            visible: root.nextEntry !== null
            Layout.fillWidth: true
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.055)
            borderSpec: Border.flat(Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05), 1)
            radius: Style.cornerRadius
            id: heroCard
            padding: 12
            implicitHeight: heroBody.implicitHeight + heroCard.contentTopInset + heroCard.contentBottomInset

            ColumnLayout {
              id: heroBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: heroCard.contentTopInset
              anchors.leftMargin: heroCard.contentLeftInset
              anchors.rightMargin: heroCard.contentRightInset
              spacing: 4

              Text {
                text: root.nextEntry ? "Next: " + root.nextEntry.label + (root.nextEntry.tomorrow ? " (tomorrow)" : "") : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                text: root.nextEntry
                  ? Model.formatClock(root.nextEntry.time, root.use24h) + "  ·  in " + Model.formatRemaining(root.nextEntry.time.getTime() - root.nowMs)
                  : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            visible: root.nextEntry === null
            Layout.fillWidth: true
            text: root.locationResolving ? "Resolving location…" : "Fetching prayer times…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Repeater {
              model: root.displaySchedule

              delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4

                readonly property bool isNext: modelData === root.nextEntry

                Text {
                  text: modelData.label
                  color: isNext ? Color.accent : (modelData.info ? root.dim : root.fg)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: isNext
                }

                Item { Layout.fillWidth: true }

                Text {
                  text: modelData.time ? Model.formatClock(modelData.time, root.use24h) : "—"
                  color: isNext ? Color.accent : (modelData.info ? root.dim : root.fg)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: isNext
                }
              }
            }
          }
        }

        // ---- Settings view ---------------------------------------------

        ColumnLayout {
          visible: root.settingsMode
          Layout.fillWidth: true
          spacing: Style.space(12)

          Dropdown {
            Layout.fillWidth: true
            label: "Calculation method"
            options: Model.CALCULATION_METHODS
            value: root.draftSettings.calculationMethod || root.calcMethod
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFamily
            onChanged: function(v) { root.draftSettings = Object.assign({}, root.draftSettings, { calculationMethod: v }) }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "Asr method"
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            ButtonGroup {
              options: Model.ASR_SCHOOLS
              value: root.draftSettings.asrSchool || root.asrSchool
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onChanged: function(v) { root.draftSettings = Object.assign({}, root.draftSettings, { asrSchool: v }) }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: "Time format"
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            ButtonGroup {
              options: Model.TIME_FORMATS
              value: root.draftSettings.timeFormat || (root.use24h ? "24h" : "12h")
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onChanged: function(v) { root.draftSettings = Object.assign({}, root.draftSettings, { timeFormat: v }) }
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Location follows the Weather widget (" + root.locationLabel + "). Set it with `omarchy-weather-location --set <name> [lat,lon]`."
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.settingsStatusText !== ""
            Layout.fillWidth: true
            text: root.settingsStatusText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.settingsMode ? "s saves · esc closes" : "s settings · r refresh · esc closes"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  // Button's own built-in tooltip (driven by its `tooltipText` property)
  // hardcodes a square corner, unlike PanelToolTip and every rounded
  // surface elsewhere in the shell. Track hover locally and pair it with
  // PanelToolTip instead, so these tooltips match the rest of the panel.
  component TooltipButton: Button {
    id: tooltipButton
    property string tooltip: ""
    property bool _hovered: false
    onHovered: function(h) { tooltipButton._hovered = h }

    PanelToolTip {
      visible: tooltipButton.tooltip !== "" && tooltipButton._hovered
      text: tooltipButton.tooltip
    }
  }
}
