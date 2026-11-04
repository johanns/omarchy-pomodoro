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

  // Keyboard cursor over the panel's controls, top to bottom. The three
  // action buttons share the first row and are walked with Left/Right.
  readonly property var controls: [
    "start", "reset", "skip",
    "focusMinutes", "shortBreakMinutes", "longBreakMinutes", "sessionsBeforeLongBreak",
    "autoStartBreaks", "autoStartFocus", "notify"
  ]
  property int cursor: 0
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

  function updateSetting(key, value) {
    const entry = { id: root.moduleName }
    for (const k of Object.keys(root.settings)) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function controlAt(index) {
    return root.controls[Math.max(0, Math.min(root.controls.length - 1, index))]
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) { cursorActive = true; return }
    const id = controlAt(cursor)
    if (dy !== 0) {
      if (cursor < 3) cursor = dy > 0 ? 3 : cursor
      else if (cursor === 3 && dy < 0) cursor = 0
      else cursor = Math.max(0, Math.min(controls.length - 1, cursor + dy))
      return
    }
    if (cursor < 3) {
      cursor = Math.max(0, Math.min(2, cursor + dx))
      return
    }
    if (Model.LIMITS[id]) {
      const limit = Model.LIMITS[id]
      updateSetting(id, Math.max(limit.min, Math.min(limit.max, cfg[id] + dx)))
    }
  }

  function activateCursor() {
    if (!cursorActive) return
    const id = controlAt(cursor)
    if (id === "start") toggleTimer()
    else if (id === "reset") resetTimer()
    else if (id === "skip") skipPhase()
    else if (id === "autoStartBreaks" || id === "autoStartFocus" || id === "notify") updateSetting(id, !cfg[id])
  }

  function handleTextKey(text) {
    if (text === "r" || text === "R") resetTimer()
    else if (text === "s" || text === "S" || text === "n" || text === "N") skipPhase()
  }

  onSettingsChanged: pushSettings()
  onServiceChanged: pushSettings()
  Component.onCompleted: pushSettings()
  onOpenedChanged: if (opened) { cursorActive = false; cursor = 0 }

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
      blocked: focusField.field.activeFocus || shortField.field.activeFocus
        || longField.field.activeFocus || sessionsField.field.activeFocus
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

        // ---------- Hero: phase glyph · phase/status · countdown ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroClock.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.phaseGlyph
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
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

        // ---------- Sessions toward the long break ----------
        Row {
          width: parent.width
          spacing: Style.space(10)

          Row {
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
              model: root.cfg.sessionsBeforeLongBreak

              Rectangle {
                required property int index
                width: Style.space(10)
                height: width
                radius: width / 2
                color: root.bar.foreground
                opacity: index < root.completedFocus ? 1 : 0.18
                Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: strings.tn("sessions.completed", root.completedFocus)
              .arg(Commons.I18n.formatNumber(root.completedFocus))
              .arg(Commons.I18n.formatNumber(root.cfg.sessionsBeforeLongBreak))
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
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
            hasCursor: root.cursorActive && root.cursor === 0
            onClicked: root.toggleTimer()
            onHovered: (h) => { if (h) { root.cursorActive = true; root.cursor = 0 } }
          }

          Button {
            width: actionRow.cellWidth
            iconText: ""
            text: strings.t("action.reset")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            hasCursor: root.cursorActive && root.cursor === 1
            onClicked: root.resetTimer()
            onHovered: (h) => { if (h) { root.cursorActive = true; root.cursor = 1 } }
          }

          Button {
            width: actionRow.cellWidth
            iconText: ""
            text: strings.t("action.skip")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            hasCursor: root.cursorActive && root.cursor === 2
            onClicked: root.skipPhase()
            onHovered: (h) => { if (h) { root.cursorActive = true; root.cursor = 2 } }
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

        // ---------- Durations ----------
        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: strings.t("section.durations")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        // Two equal columns; each field stretches to its column so the four
        // controls fill the panel width edge to edge.
        Grid {
          id: durationsGrid
          width: parent.width
          columns: 2
          columnSpacing: Style.space(12)
          rowSpacing: Style.space(10)
          readonly property real cellWidth: Math.floor((width - columnSpacing) / 2)

          NumberField {
            id: focusField
            width: durationsGrid.cellWidth
            fieldWidth: durationsGrid.cellWidth
            label: strings.t("setting.focusMinutes")
            from: Model.LIMITS.focusMinutes.min
            to: Model.LIMITS.focusMinutes.max
            value: root.cfg.focusMinutes
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorActive && root.cursor === 3
            onModified: (v) => root.updateSetting("focusMinutes", v)
            onHovered: (on) => { if (on) { root.cursorActive = true; root.cursor = 3 } }
          }

          NumberField {
            id: shortField
            width: durationsGrid.cellWidth
            fieldWidth: durationsGrid.cellWidth
            label: strings.t("setting.shortBreakMinutes")
            from: Model.LIMITS.shortBreakMinutes.min
            to: Model.LIMITS.shortBreakMinutes.max
            value: root.cfg.shortBreakMinutes
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorActive && root.cursor === 4
            onModified: (v) => root.updateSetting("shortBreakMinutes", v)
            onHovered: (on) => { if (on) { root.cursorActive = true; root.cursor = 4 } }
          }

          NumberField {
            id: longField
            width: durationsGrid.cellWidth
            fieldWidth: durationsGrid.cellWidth
            label: strings.t("setting.longBreakMinutes")
            from: Model.LIMITS.longBreakMinutes.min
            to: Model.LIMITS.longBreakMinutes.max
            value: root.cfg.longBreakMinutes
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorActive && root.cursor === 5
            onModified: (v) => root.updateSetting("longBreakMinutes", v)
            onHovered: (on) => { if (on) { root.cursorActive = true; root.cursor = 5 } }
          }

          NumberField {
            id: sessionsField
            width: durationsGrid.cellWidth
            fieldWidth: durationsGrid.cellWidth
            label: strings.t("setting.sessionsBeforeLongBreak")
            from: Model.LIMITS.sessionsBeforeLongBreak.min
            to: Model.LIMITS.sessionsBeforeLongBreak.max
            value: root.cfg.sessionsBeforeLongBreak
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorActive && root.cursor === 6
            onModified: (v) => root.updateSetting("sessionsBeforeLongBreak", v)
            onHovered: (on) => { if (on) { root.cursorActive = true; root.cursor = 6 } }
          }
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

          Toggle {
            width: parent.width
            label: strings.t("setting.autoStartBreaks")
            description: strings.t("setting.autoStartBreaks.description")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            checked: root.cfg.autoStartBreaks
            hasCursor: root.cursorActive && root.cursor === 7
            onHovered: (h) => { if (h) { root.cursorActive = true; root.cursor = 7 } }
            onClicked: root.updateSetting("autoStartBreaks", !root.cfg.autoStartBreaks)
          }

          Toggle {
            width: parent.width
            label: strings.t("setting.autoStartFocus")
            description: strings.t("setting.autoStartFocus.description")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            checked: root.cfg.autoStartFocus
            hasCursor: root.cursorActive && root.cursor === 8
            onHovered: (h) => { if (h) { root.cursorActive = true; root.cursor = 8 } }
            onClicked: root.updateSetting("autoStartFocus", !root.cfg.autoStartFocus)
          }

          Toggle {
            width: parent.width
            label: strings.t("setting.notify")
            description: strings.t("setting.notify.description")
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            checked: root.cfg.notify
            hasCursor: root.cursorActive && root.cursor === 9
            onHovered: (h) => { if (h) { root.cursorActive = true; root.cursor = 9 } }
            onClicked: root.updateSetting("notify", !root.cfg.notify)
          }
        }
      }
    }
  }
}
