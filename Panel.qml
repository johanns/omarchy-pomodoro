import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar widget and control panel. The countdown itself runs in Service.qml;
// this file shows it in the bar slot and in a KeyboardPanel, and forwards
// start, pause, reset and skip to the service.
Panel {
  id: root
  moduleName: "jg.pomodoro"
  ipcTarget: "jg.pomodoro"
  manageIpc: false

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("jg.pomodoro") : null
  readonly property bool vertical: bar ? bar.vertical === true : false
  readonly property var cfg: Model.normalizeSettings(settings)

  readonly property string phase: service ? service.phase : "focus"
  readonly property bool running: service ? service.running : false
  readonly property bool paused: service ? service.paused : false
  readonly property bool onBreak: Model.isBreak(phase)
  readonly property int remainingMs: service ? service.remainingMs : Model.phaseDurationMs("focus", cfg)
  readonly property int completedFocus: service ? service.completedFocus : 0
  readonly property real progress: service ? service.progress : 0
  readonly property bool engaged: running || paused

  readonly property string phaseGlyph: onBreak ? "" : ""
  readonly property string clockText: localizeDigits(Model.formatClock(remainingMs))
  readonly property string shortText: localizeDigits(Model.formatShort(remainingMs))
  readonly property string phaseTitle: strings.t("phase." + phase)
  readonly property string statusTitle: running ? strings.t("status.running")
    : (paused ? strings.t("status.paused") : strings.t("status.ready"))
  readonly property string tooltip: running
    ? strings.t("tooltip.running").arg(phaseTitle).arg(clockText)
    : (paused ? strings.t("tooltip.paused").arg(phaseTitle).arg(clockText)
      : strings.t("tooltip.idle").arg(phaseTitle))

  readonly property var focusOptions: Model.FOCUS_PRESETS
  readonly property var breakOptions: Object.keys(Model.BREAK_LENGTHS)

  // Keyboard cursor: a row name and a column inside it. Rows run top to
  // bottom; Left/Right walks the chips of the actions, Focus and Break rows.
  readonly property var rows: ["actions", "focus", "break", "notify", "chime", "breakScreen"]
  readonly property var rowWidths: ({ actions: 3, focus: focusOptions.length, break: breakOptions.length, notify: 1, chime: 1, breakScreen: 1 })
  property string row: "actions"
  property int col: 0
  property bool cursorActive: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function localizeDigits(text) {
    return String(text).split("")
      .map((ch) => ch >= "0" && ch <= "9" ? Commons.I18n.formatNumber(Number(ch)) : ch)
      .join("")
  }

  function pushSettings() {
    if (service) service.settings = root.settings
  }

  function startTimer() { if (service) service.start() }
  function pauseTimer() { if (service) service.pause() }
  function toggleTimer() { if (service) service.toggle() }
  function resetTimer() { if (service) service.reset() }
  function skipPhase() { if (service) service.skip() }
  function stopPhase() { if (service) service.stop() }
  function extendPhase() { if (service) service.extend() }
  function hideBreakScreen() { if (service) service.hideBreakScreen() }
  function resetCount() { if (service) service.resetCount() }
  function playChime() { if (service) service.chime() }

  // Writes carry only the keys this version knows, so obsolete ones from
  // version 1.0 drop out of the bar entry on the first change.
  function updateSetting(key, value) {
    const entry = { id: root.moduleName }
    for (const k of Object.keys(root.cfg)) if (k in root.settings) entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function breakLabel(value) {
    return strings.t(value === "long" ? "break.long" : "break.short").arg(Commons.I18n.formatNumber(Model.BREAK_LENGTHS[value]))
  }

  function placeCursor(nextRow, nextCol) {
    cursorActive = true
    row = nextRow
    col = Math.max(0, Math.min(rowWidths[nextRow] - 1, nextCol))
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) { cursorActive = true; return }
    if (dy !== 0) {
      const index = Math.max(0, Math.min(rows.length - 1, rows.indexOf(row) + dy))
      // Landing on a chip row keeps the current choice under the cursor.
      const next = rows[index]
      let landing = 0
      if (next === "focus") landing = focusOptions.indexOf(cfg.focusMinutes)
      else if (next === "break") landing = breakOptions.indexOf(cfg.breakLength)
      placeCursor(next, next === row ? col : landing)
      return
    }
    placeCursor(row, col + dx)
  }

  // Enter or Space before the cursor is placed acts on the first control,
  // which is what the key hint promises.
  function activateCursor() {
    if (!cursorActive) { toggleTimer(); return }
    if (row === "actions") {
      if (col === 0) toggleTimer()
      else if (col === 1) resetTimer()
      else skipPhase()
    }
    else if (row === "focus") updateSetting("focusMinutes", focusOptions[col])
    else if (row === "break") updateSetting("breakLength", breakOptions[col])
    else updateSetting(row, !cfg[row])
  }

  function handleTextKey(text) {
    if (text === "r" || text === "R") resetTimer()
    else if (text === "s" || text === "S" || text === "n" || text === "N") skipPhase()
  }

  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()
  onOpenedChanged: if (opened) { cursorActive = false; row = "actions"; col = 0 }

  ShellIpc {
    target: "jg.pomodoro"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function start(): void { root.startTimer() }
    function pause(): void { root.pauseTimer() }
    function toggleTimer(): void { root.toggleTimer() }
    function reset(): void { root.resetTimer() }
    function skip(): void { root.skipPhase() }
    function stop(): void { root.stopPhase() }
    function extend(): void { root.extendPhase() }
    function hideBreakScreen(): void { root.hideBreakScreen() }
    function resetCount(): void { root.resetCount() }
    function chime(): void { root.playChime() }
    function status(): string { return root.service ? root.service.statusText() : "{}" }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The open-panel mark under the slot: the label's width horizontally, one
  // icon-sized line vertically, as the clock does.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property var verticalLines: engaged ? [phaseGlyph, shortText] : [phaseGlyph]

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : (root.engaged ? root.phaseGlyph + "  " + root.clockText : root.phaseGlyph)
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    dimmed: root.paused
    tooltipText: Model.plainText(root.tooltip)

    onPressed: (b) => {
      if (b === Qt.RightButton) root.toggleTimer()
      else if (b === Qt.MiddleButton) root.skipPhase()
      else root.toggle()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 2 ? button.fontSize * 0.85 : button.fontSize
          color: button.foreground
        }
      }
    }
  }

  // A row of equal-width chips; `selected` marks the current value, the
  // cursor follows the panel's row/col state.
  component ChipRow: Row {
    id: chipRow
    property var values: []
    property var labels: []
    property string rowName: ""
    property string current: ""
    signal picked(int index)
    width: parent.width
    spacing: Style.space(6)
    readonly property real cellWidth: values.length > 0 ? (width - spacing * (values.length - 1)) / values.length : 0

    Repeater {
      model: chipRow.values
      Button {
        required property var modelData
        required property int index
        width: chipRow.cellWidth
        text: chipRow.labels[index]
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        fontSize: Style.font.bodySmall
        bordered: true
        selected: String(modelData) === chipRow.current
        hasCursor: root.cursorActive && root.row === chipRow.rowName && root.col === index
        onClicked: chipRow.picked(index)
        onHovered: (h) => { if (h) root.placeCursor(chipRow.rowName, index) }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: (dx, dy) => root.moveCursor(dx, dy)
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: (direction) => root.switchPanel(direction)
      onTextKey: (text, modifiers) => root.handleTextKey(text)

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: phase and status · countdown ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroLabels.implicitHeight, heroClock.implicitHeight)

          Column {
            id: heroLabels
            anchors.left: parent.left
            anchors.right: heroClock.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.phaseTitle
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.statusTitle.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroClock
            textFormat: Text.PlainText
            text: root.clockText
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Progress through the current phase ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: track
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            anchors.left: track.left
            anchors.verticalCenter: track.verticalCenter
            height: track.height
            radius: track.radius
            color: root.bar.foreground
            opacity: root.paused ? 0.5 : 1
            width: Math.max(track.height, track.width * root.progress)

            Behavior on width { NumberAnimation { duration: Style.duration(280); easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
          }
        }

        // ---------- Sessions done ----------
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: strings.tn("sessions.done", root.completedFocus).arg(Commons.I18n.formatNumber(root.completedFocus))
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        // ---------- Actions ----------
        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(6)
          readonly property real cellWidth: (width - spacing * 2) / 3

          Button {
            width: actionRow.cellWidth
            iconText: root.running ? "" : ""
            text: root.running ? strings.t("action.pause") : (root.paused ? strings.t("action.resume") : strings.t("action.start"))
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            active: root.running
            hasCursor: root.cursorActive && root.row === "actions" && root.col === 0
            onClicked: root.toggleTimer()
            onHovered: (h) => { if (h) root.placeCursor("actions", 0) }
          }

          Button {
            width: actionRow.cellWidth
            iconText: ""
            text: strings.t("action.reset")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            hasCursor: root.cursorActive && root.row === "actions" && root.col === 1
            onClicked: root.resetTimer()
            onHovered: (h) => { if (h) root.placeCursor("actions", 1) }
          }

          Button {
            width: actionRow.cellWidth
            iconText: ""
            text: strings.t("action.skip")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            hasCursor: root.cursorActive && root.row === "actions" && root.col === 2
            onClicked: root.skipPhase()
            onHovered: (h) => { if (h) root.placeCursor("actions", 2) }
          }
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: strings.t("hint.keys")
          color: Qt.darker(root.bar.foreground, 1.6)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        // ---------- Focus length ----------
        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: strings.t("section.focus")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        ChipRow {
          rowName: "focus"
          values: root.focusOptions
          labels: root.focusOptions.map((m) => Commons.I18n.formatNumber(m))
          current: String(root.cfg.focusMinutes)
          onPicked: (index) => root.updateSetting("focusMinutes", root.focusOptions[index])
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: strings.t("focus.caption")
          color: Qt.darker(root.bar.foreground, 1.6)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---------- Break length ----------
        PanelSectionHeader {
          text: strings.t("section.break")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        ChipRow {
          rowName: "break"
          values: root.breakOptions
          labels: root.breakOptions.map((v) => root.breakLabel(v))
          current: root.cfg.breakLength
          onPicked: (index) => root.updateSetting("breakLength", root.breakOptions[index])
        }

        // ---------- Behavior ----------
        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: strings.t("section.behavior")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: ["notify", "chime", "breakScreen"]

            Toggle {
              required property string modelData
              width: parent.width
              label: strings.t("setting." + modelData)
              description: strings.t("setting." + modelData + ".description")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.cfg[modelData] === true
              hasCursor: root.cursorActive && root.row === modelData
              onHovered: (h) => { if (h) root.placeCursor(modelData, 0) }
              onClicked: root.updateSetting(modelData, !root.cfg[modelData])
            }
          }
        }
      }
    }
  }
}
