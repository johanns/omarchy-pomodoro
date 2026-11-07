import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Full-screen break view, one per monitor, shown while a break runs or is
// paused and the Break screen toggle is on. Its actions mirror the panel's
// (Pause/Resume, Reset, Skip) with the same keys, plus +5 min. Esc or a
// click on the backdrop hides it for the rest of the break; the service
// owns that flag.
PanelWindow {
  id: win

  required property var modelData
  property var service: null

  readonly property bool shown: service ? service.breakScreenShown === true : false
  readonly property bool running: service ? service.running : false
  readonly property int remainingMs: service ? service.remainingMs : 0
  readonly property real progress: service ? service.progress : 0
  readonly property int completedFocus: service ? service.completedFocus : 0
  readonly property color fg: Commons.Color.foreground
  readonly property string fontFamily: Style.font.family

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function localizeDigits(text) {
    return String(text).split("").map(ch => ch >= "0" && ch <= "9" ? Commons.I18n.formatNumber(Number(ch)) : ch).join("");
  }

  readonly property string clockText: localizeDigits(Model.formatClock(remainingMs))
  readonly property string resumeText: {
    if (!running)
      return strings.t("status.paused");
    const at = new Date(Date.now() + remainingMs);
    return strings.t("break.resumeAt").arg(at.toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat));
  }

  screen: modelData
  visible: shown
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors {
    top: true
    left: true
    bottom: true
    right: true
  }

  WlrLayershell.namespace: "jg-pomodoro-break"
  WlrLayershell.layer: WlrLayer.Overlay
  // Constant: the window is unmapped while hidden, and a focus mode that
  // changes together with `visible` could map the surface before it applies.
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

  onShownChanged: if (shown)
    Qt.callLater(() => {
      keys.forceActiveFocus();
    })

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.background
    opacity: 0.94
  }

  // Backdrop click hides. The content block below swallows its own clicks.
  MouseArea {
    anchors.fill: parent
    onClicked: if (win.service)
      win.service.hideBreakScreen()
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true
    Keys.onPressed: event => {
      if (!win.service)
        return;
      if (event.key === Qt.Key_Escape) {
        win.service.hideBreakScreen();
        event.accepted = true;
      } else if (event.key === Qt.Key_Space) {
        win.service.toggle();
        event.accepted = true;
      } else if (event.text === "r" || event.text === "R") {
        win.service.reset();
        event.accepted = true;
      } else if (event.text === "s" || event.text === "S" || event.text === "n" || event.text === "N") {
        win.service.skip();
        event.accepted = true;
      } else if (event.text === "e" || event.text === "E") {
        win.service.extend();
        event.accepted = true;
      }
    }

    // The content block swallows its own clicks so only the backdrop hides.
    Item {
      id: card
      anchors.centerIn: parent
      width: content.width
      height: content.height

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Column {
        id: content
        spacing: Style.space(14)
        width: Math.min(win.width - Style.space(80), Style.space(560))

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: strings.t("phase.break").toUpperCase()
          color: Qt.darker(win.fg, 1.4)
          font.family: win.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          font.letterSpacing: 2
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: win.clockText
          color: win.fg
          font.family: win.fontFamily
          font.pixelSize: Style.font.displayLarge * 2.4
          font.bold: true
        }

        // Progress: a line of dots, and a Pac-Man at the elapsed position that
        // has eaten the ones behind it.
        Item {
          id: pacRow
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(parent.width, Style.space(384))
          height: Style.space(28)
          readonly property int dotCount: 16
          readonly property real pitch: width / dotCount
          readonly property real pacSize: Style.space(24)
          readonly property real pacX: win.progress * (width - pacSize)

          Repeater {
            model: pacRow.dotCount
            Rectangle {
              required property int index
              readonly property real cx: pacRow.pitch * (index + 0.5)
              x: cx - width / 2
              y: (pacRow.height - height) / 2
              width: Style.space(6)
              height: width
              radius: width / 2
              color: win.fg
              visible: cx > pacRow.pacX + pacRow.pacSize * 0.6
            }
          }

          Canvas {
            id: pacman
            x: pacRow.pacX
            y: (pacRow.height - height) / 2
            width: pacRow.pacSize
            height: pacRow.pacSize
            readonly property real mouth: win.running && !Style.reduceMotion ? mouthAnim : 0.35
            property real mouthAnim: 0.35
            // Read through a property so a theme change repaints.
            readonly property color fill: Commons.Color.accent
            onFillChanged: requestPaint()
            SequentialAnimation on mouthAnim {
              running: win.shown && win.running && !Style.reduceMotion
              loops: Animation.Infinite
              NumberAnimation {
                from: 0.35
                to: 0.05
                duration: Style.duration(220)
                easing.type: Easing.InOutSine
              }
              NumberAnimation {
                from: 0.05
                to: 0.35
                duration: Style.duration(220)
                easing.type: Easing.InOutSine
              }
            }
            onMouthChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
              const ctx = getContext("2d");
              ctx.reset();
              const r = width / 2;
              ctx.fillStyle = fill;
              ctx.beginPath();
              ctx.moveTo(r, r);
              ctx.arc(r, r, r, mouth * Math.PI, (2 - mouth) * Math.PI, false);
              ctx.closePath();
              ctx.fill();
            }
          }
        }

        // Two whole phrases side by side, never glued into one string.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Repeater {
            model: [win.resumeText, "·", strings.tn("sessions.done", win.completedFocus).arg(Commons.I18n.formatNumber(win.completedFocus))]
            Text {
              required property string modelData
              textFormat: Text.PlainText
              text: modelData
              color: Qt.darker(win.fg, 1.4)
              font.family: win.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          Button {
            iconText: win.running ? "" : ""
            text: (win.running ? strings.t("action.pause") : strings.t("action.resume")) + " · Space"
            foreground: win.fg
            fontFamily: win.fontFamily
            bordered: true
            horizontalPadding: Style.space(16)
            verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
            onClicked: if (win.service)
              win.service.toggle()
          }
          Button {
            iconText: ""
            text: strings.t("action.reset") + " · R"
            foreground: win.fg
            fontFamily: win.fontFamily
            bordered: true
            horizontalPadding: Style.space(16)
            verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
            onClicked: if (win.service)
              win.service.reset()
          }
          Button {
            iconText: ""
            text: strings.t("action.skip") + " · S"
            foreground: win.fg
            fontFamily: win.fontFamily
            bordered: true
            horizontalPadding: Style.space(16)
            verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
            onClicked: if (win.service)
              win.service.skip()
          }
          Button {
            iconText: ""
            text: strings.t("action.extend") + " · E"
            foreground: win.fg
            fontFamily: win.fontFamily
            bordered: true
            horizontalPadding: Style.space(16)
            verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
            onClicked: if (win.service)
              win.service.extend()
          }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: strings.t("break.escHint")
          color: Qt.darker(win.fg, 1.7)
          font.family: win.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
