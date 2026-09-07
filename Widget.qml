import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TeaLogic.js" as Logic

// Tea counter for the Omarchy bar.
//
// The bar label is today's caffeine load; the dropdown is a one-tap logger
// backed by user presets, with the week strip and the running week/month/year
// totals underneath. Every color comes off the bar/theme palette, so a theme
// switch repaints the whole thing with no per-theme code here.
BarWidget {
  id: root
  moduleName: "michael.tea"

  // ------------------------------------------------------------- settings

  readonly property int rolloverHour: Math.max(0, Math.min(12, Number(setting("rolloverHour", 4))))
  readonly property int baseMg: Math.max(1, Number(setting("baseMg", 47)))
  readonly property string barDisplay: String(setting("barDisplay", "Caffeine (mg)"))

  // --------------------------------------------------------------- palette

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.55)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.25)
  readonly property color accent: bar ? bar.urgent : Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string teaGlyph: "󰶞"

  // ------------------------------------------------------------ panel state

  property bool popupOpen: false
  readonly property bool opened: popupOpen
  property string page: "home"

  // Draft state for the custom-drink page.
  property string draftStrength: "black"
  property string draftSize: "1"
  property string draftStyle: "plain"
  property string draftDayKey: ""
  property string draftTime: ""

  // Draft state for the preset editor.
  property var editingPreset: null
  property string editName: ""
  property string editIcon: ""
  property string editStrength: "black"
  property string editSize: "1"
  property string editStyle: "plain"

  property string flash: ""
  property string stripHint: ""

  readonly property var stats: store.stats

  // --------------------------------------------------------------- helpers

  function say(message) {
    root.flash = message
    flashTimer.restart()
  }

  function open() {
    popupOpen = true
    page = "home"
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    popupOpen = false
    page = "home"
    editingPreset = null
  }

  function toggle() {
    if (popupOpen) close()
    else open()
  }

  function back() {
    if (page === "editor") page = "presets"
    else if (page === "home") close()
    else page = "home"
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function startCustom() {
    var now = new Date()
    draftStrength = "black"
    draftSize = "1"
    draftStyle = "plain"
    draftDayKey = stats.todayKey
    draftTime = Logic.pad2(now.getHours()) + ":" + Logic.pad2(now.getMinutes())
    page = "custom"
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function shiftDraftDay(delta) {
    var next = Logic.addDays(draftDayKey, delta)
    // Backfill only — logging into the future is always a mistake.
    if (next > stats.todayKey) return
    draftDayKey = next
  }

  // "9:05", "0905", "9" — anything unambiguous beats making the user type a
  // colon in the right place before the button will light up.
  function parseDraftTime() {
    var raw = String(draftTime).replace(/[^0-9]/g, "")
    if (raw.length === 0) return null
    var h, m
    if (raw.length <= 2) { h = Number(raw); m = 0 }
    else { h = Number(raw.substr(0, raw.length - 2)); m = Number(raw.substr(raw.length - 2)) }
    if (!isFinite(h) || !isFinite(m) || h < 0 || h > 23 || m < 0 || m > 59) return null
    return { hours: h, minutes: m }
  }

  readonly property bool draftTimeValid: parseDraftTime() !== null

  function logDraft() {
    var time = parseDraftTime()
    if (!time) return
    var ts = Logic.timestampFor(draftDayKey, time.hours, time.minutes, root.rolloverHour)
    store.logDrink(draftStrength, draftSize, draftStyle, "", ts)
    say("Logged " + Logic.describeDrink(draftStrength, draftSize, draftStyle))
    page = "home"
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function logPresetAt(index) {
    var preset = store.presetAt(index)
    if (!preset) return
    store.logPreset(preset, Date.now())
    say("Logged " + preset.name)
  }

  function startEditor(preset) {
    editingPreset = preset || null
    editName = preset ? preset.name : ""
    editIcon = preset ? preset.icon : root.teaGlyph
    editStrength = preset ? preset.strength : "black"
    editSize = preset ? preset.size : "1"
    editStyle = preset ? preset.style : "plain"
    page = "editor"
    Qt.callLater(function () { nameField.forceActiveFocus() })
  }

  function saveEditor() {
    var name = String(editName).replace(/^\s+|\s+$/g, "")
    if (name.length === 0) return
    store.savePreset({
      id: editingPreset ? editingPreset.id : "",
      name: name,
      icon: String(editIcon).replace(/^\s+|\s+$/g, "") || root.teaGlyph,
      strength: editStrength,
      size: editSize,
      style: editStyle
    })
    say("Saved " + name)
    page = "presets"
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function deleteEditor() {
    if (!editingPreset) return
    store.deletePreset(editingPreset.id)
    say("Deleted " + editingPreset.name)
    page = "presets"
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function doExport() {
    var path = store.exportCsv()
    say("Wrote " + path.replace(store.home, "~"))
  }

  // ---------------------------------------------------------- bar labelling

  readonly property string barLabel: {
    if (barDisplay === "Icon only") return root.teaGlyph
    var cups = Logic.formatCups(stats.day.cups)
    var mg = String(stats.day.mg)
    if (barDisplay === "Cups") return root.teaGlyph + " " + cups
    if (barDisplay === "Cups and mg") return root.teaGlyph + " " + cups + " · " + mg + "mg"
    return root.teaGlyph + " " + mg + "mg"
  }

  readonly property var verticalLines: barDisplay === "Icon only"
    ? [root.teaGlyph]
    : [root.teaGlyph, barDisplay === "Cups" ? Logic.formatCups(stats.day.cups) : String(stats.day.mg)]

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Timer {
    id: flashTimer
    interval: 2600
    onTriggered: root.flash = ""
  }

  TeaStore {
    id: store
    rolloverHour: root.rolloverHour
    baseMg: root.baseMg
  }

  IpcHandler {
    target: "tea"

    function log(): string {
      var preset = store.presetAt(0)
      if (!preset) return "no presets defined"
      store.logPreset(preset, Date.now())
      return "logged " + preset.name
    }

    function undo(): string {
      return store.undoLast() ? "removed last cup" : "nothing to undo"
    }

    function today(): string {
      return Logic.formatCups(root.stats.day.cups) + " cups · " + root.stats.day.mg + " mg"
    }

    function csv(): string { return store.exportCsv() }

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  // ------------------------------------------------------------- bar button

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.barLabel
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    active: root.popupOpen
    tooltipText: Logic.formatCups(root.stats.day.cups) + " cups today · "
      + root.stats.day.mg + " mg · week " + Logic.formatCups(root.stats.week.cups)

    onPressed: function (b) {
      // Right click is the fastest possible path: log preset one and get out
      // of the way. Middle click takes it back when that was a mis-click.
      if (b === Qt.RightButton) root.logPresetAt(0)
      else if (b === Qt.MiddleButton) store.undoLast()
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
          fontFamily: root.fontFamily
          fontSize: Style.bar.iconFont
          color: button.active ? button.activeColor : button.foreground
        }
      }
    }
  }

  // ---------------------------------------------------------------- panel

  component Chip: Button {
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    iconSize: Style.font.icon
    bordered: true
  }

  component Body: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: nameField.activeFocus || iconField.activeFocus || timeField.activeFocus

      onCloseRequested: root.back()
      onActivateRequested: {
        if (root.page === "custom" && root.draftTimeValid) root.logDraft()
        else if (root.page === "editor") root.saveEditor()
      }

      onTextKey: function (text) {
        var key = String(text || "").toLowerCase()

        // 1-9 log the matching preset from anywhere but the editor — the
        // whole point of presets is not having to aim at a button.
        if (root.page !== "editor" && key >= "1" && key <= "9") {
          root.logPresetAt(Number(key) - 1)
          return
        }
        if (root.page === "home") {
          if (key === "c") root.startCustom()
          else if (key === "p") root.page = "presets"
          else if (key === "u") { if (store.undoLast()) root.say("Removed last cup") }
          else if (key === "e") root.doExport()
          else if (key === "q") root.close()
        } else if (root.page === "presets") {
          if (key === "n") root.startEditor(null)
          else if (key === "q") root.close()
        }
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(11)

        // ------------------------------------------------------------ header

        Item {
          width: parent.width
          height: Math.max(headerLeft.implicitHeight, headerRight.implicitHeight)

          Row {
            id: headerLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(9)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.teaGlyph
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
            }

            Column {
              spacing: Style.space(1)

              Text {
                text: "TEA"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                text: root.page === "custom" ? "CUSTOM CUP"
                  : root.page === "presets" ? "PRESETS"
                  : root.page === "editor" ? (root.editingPreset ? "EDIT PRESET" : "NEW PRESET")
                  : "TODAY"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Column {
            id: headerRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              anchors.right: parent.right
              text: Logic.formatCups(root.stats.day.cups) + (root.stats.day.cups === 1 ? " cup" : " cups")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              text: root.stats.day.mg + " mg"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator { width: parent.width; foreground: root.foreground }

        // ------------------------------------------------------- home: log

        Column {
          visible: root.page === "home"
          width: parent.width
          spacing: Style.space(11)

          PanelSectionHeader {
            text: store.presets.length > 0 ? "LOG A CUP" : "NO PRESETS YET"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: store.presets

              Chip {
                required property var modelData
                required property int index

                iconText: modelData.icon
                text: modelData.name
                tooltipText: Logic.describeDrink(modelData.strength, modelData.size, modelData.style)
                  + " · " + Logic.caffeineMg(modelData.strength, modelData.size, root.baseMg) + " mg"
                  + "   [" + (index + 1) + "]"
                onClicked: root.logPresetAt(index)
              }
            }

            Chip {
              iconText: "󰐕"
              text: "Custom"
              tooltipText: "Pick type, size, style, and when  [c]"
              onClicked: root.startCustom()
            }

            Chip {
              iconText: "󰒓"
              text: "Presets"
              tooltipText: "Add, edit, and delete presets  [p]"
              onClicked: root.page = "presets"
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // ------------------------------------------------- today's cups

          PanelSectionHeader {
            text: "TODAY'S CUPS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Body {
            visible: root.stats.today.length === 0
            width: parent.width
            text: "Nothing yet today."
            color: root.dim
          }

          // Capped so a heavy day scrolls instead of pushing the week strip
          // off the bottom of the screen.
          ListView {
            width: parent.width
            height: Math.min(contentHeight, Style.space(132))
            visible: root.stats.today.length > 0
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: root.stats.today
            spacing: Style.space(2)

            delegate: Item {
              required property var modelData
              width: ListView.view.width
              height: Style.space(22)

              Body {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(46)
                text: Logic.formatTime(modelData.ts)
                color: root.dim
                font.pixelSize: Style.font.caption
              }

              Body {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(50)
                anchors.right: entryMg.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: Logic.describeEntry(modelData)
                elide: Text.ElideRight
              }

              Body {
                id: entryMg
                anchors.right: removeButton.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.mg + " mg"
                color: root.dim
                font.pixelSize: Style.font.caption
              }

              PanelActionButton {
                id: removeButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅖"
                tooltipText: "Remove this cup"
                foreground: root.dim
                hoverColor: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: store.removeEntry(modelData.id)
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // ----------------------------------------------------- history

          Item {
            width: parent.width
            height: weekHeader.implicitHeight

            PanelSectionHeader {
              id: weekHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "THIS WEEK"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: weekHeader.right
              anchors.leftMargin: Style.space(8)
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideRight
              text: root.stripHint
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.stats.strip

              Item {
                required property var modelData
                width: (parent.width - Style.space(4) * 6) / 7
                height: Style.space(46)

                // Bars are relative to the week's own peak: an honest shape
                // for the week beats a fixed ceiling that flattens light
                // weeks into nothing.
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: dayLetter.top
                  anchors.bottomMargin: Style.space(4)
                  width: parent.width - Style.space(6)
                  height: Style.space(30)
                  color: "transparent"

                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Math.max(modelData.mg > 0 ? Style.space(2) : Style.space(1),
                                     Math.round(parent.height * modelData.fill))
                    radius: Style.cornerRadius > 0 ? Math.min(Style.space(3), Style.cornerRadius) : 0
                    color: modelData.isToday ? root.accent
                      : modelData.mg > 0 ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
                      : root.faint
                  }

                  // Hovering a bar writes its numbers into the section
                  // header rather than floating a tooltip over the panel —
                  // the readout stays in one predictable place as the cursor
                  // sweeps the week.
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.stripHint = Logic.formatDayLabel(modelData.key, root.stats.todayKey)
                      + " · " + Logic.formatCups(modelData.cups) + " cups · " + modelData.mg + " mg"
                    onExited: root.stripHint = ""
                  }
                }

                Text {
                  id: dayLetter
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  text: modelData.letter
                  color: modelData.isToday ? root.accent : modelData.isFuture ? root.faint : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: modelData.isToday
                }
              }
            }
          }

          Item {
            width: parent.width
            height: totalsRow.implicitHeight

            Row {
              id: totalsRow
              anchors.left: parent.left
              spacing: Style.space(12)

              Repeater {
                model: [
                  { label: "WEEK",  bucket: root.stats.week },
                  { label: "MONTH", bucket: root.stats.month },
                  { label: "YEAR",  bucket: root.stats.year }
                ]

                Column {
                  required property var modelData
                  spacing: Style.space(1)

                  Text {
                    text: modelData.label
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    text: Logic.formatCups(modelData.bucket.cups)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }

                  Text {
                    text: modelData.bucket.mg + " mg"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            Column {
              anchors.right: parent.right
              anchors.verticalCenter: totalsRow.verticalCenter
              spacing: Style.space(4)

              Chip {
                anchors.right: parent.right
                iconText: "󰈙"
                text: "Export CSV"
                tooltipText: "Write the full history to ~/tea-history.csv  [e]"
                fontSize: Style.font.caption
                onClicked: root.doExport()
              }

              Text {
                anchors.right: parent.right
                visible: root.stats.loggedDays > 1
                text: "avg " + Logic.formatCups(root.stats.dailyAverageCups) + "/day"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---------------------------------------------------- custom page

        Column {
          visible: root.page === "custom"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "TYPE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            options: Logic.STRENGTHS
            value: root.draftStrength
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function (value) { root.draftStrength = value }
          }

          PanelSectionHeader {
            text: "SIZE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            options: Logic.SIZES
            value: root.draftSize
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function (value) { root.draftSize = value }
          }

          PanelSectionHeader {
            text: "STYLE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            options: Logic.STYLES
            value: root.draftStyle
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function (value) { root.draftStyle = value }
          }

          PanelSectionHeader {
            text: "WHEN"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰄽"
              tooltipText: "Earlier day"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.shiftDraftDay(-1)
            }

            Body {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(92)
              horizontalAlignment: Text.AlignHCenter
              text: root.draftDayKey === "" ? "" : Logic.formatDayLabel(root.draftDayKey, root.stats.todayKey)
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰄾"
              tooltipText: "Later day"
              enabled: root.draftDayKey < root.stats.todayKey
              opacity: enabled ? 1 : 0.35
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.shiftDraftDay(1)
            }

            TextField {
              id: timeField
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(72)
              text: root.draftTime
              placeholderText: "HH:MM"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              onTextChanged: root.draftTime = text
              onAccepted: if (root.draftTimeValid) root.logDraft()
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Item {
            width: parent.width
            height: logButton.implicitHeight

            Body {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: logButton.left
              anchors.rightMargin: Style.space(8)
              elide: Text.ElideRight
              color: root.dim
              text: Logic.describeDrink(root.draftStrength, root.draftSize, root.draftStyle)
                + " · " + Logic.caffeineMg(root.draftStrength, root.draftSize, root.baseMg) + " mg"
            }

            Chip {
              id: logButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.teaGlyph
              text: "Log it"
              enabled: root.draftTimeValid
              opacity: enabled ? 1 : 0.45
              tooltipText: root.draftTimeValid ? "Add this cup  [Enter]" : "Enter a time as HH:MM"
              onClicked: root.logDraft()
            }
          }
        }

        // --------------------------------------------------- presets page

        Column {
          visible: root.page === "presets"
          width: parent.width
          spacing: Style.space(6)

          Body {
            visible: store.presets.length === 0
            width: parent.width
            text: "No presets. Add one so logging a cup is a single click."
            color: root.dim
            wrapMode: Text.Wrap
          }

          Repeater {
            model: store.presets

            Item {
              required property var modelData
              width: parent.width
              height: Style.space(30)

              Text {
                id: presetIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.icon
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }

              Column {
                anchors.left: presetIcon.right
                anchors.leftMargin: Style.space(10)
                anchors.right: presetMg.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Body {
                  width: parent.width
                  text: modelData.name
                  elide: Text.ElideRight
                }

                Body {
                  width: parent.width
                  text: Logic.describeDrink(modelData.strength, modelData.size, modelData.style)
                  color: root.dim
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Body {
                id: presetMg
                anchors.right: editPresetButton.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: Logic.caffeineMg(modelData.strength, modelData.size, root.baseMg) + " mg"
                color: root.dim
                font.pixelSize: Style.font.caption
              }

              PanelActionButton {
                id: editPresetButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰏫"
                tooltipText: "Edit this preset"
                foreground: root.dim
                hoverColor: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.startEditor(modelData)
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Chip {
              iconText: "󰐕"
              text: "New preset"
              tooltipText: "Add a preset  [n]"
              onClicked: root.startEditor(null)
            }

            Chip {
              iconText: "󰁍"
              text: "Back"
              onClicked: root.back()
            }
          }
        }

        // ---------------------------------------------------- editor page

        Column {
          visible: root.page === "editor"
          width: parent.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: iconField
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(46)
              text: root.editIcon
              horizontalAlignment: Text.AlignHCenter
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              onTextChanged: root.editIcon = text
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }

            TextField {
              id: nameField
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - iconField.width - Style.space(6)
              text: root.editName
              placeholderText: "Preset name"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              onTextChanged: root.editName = text
              onAccepted: root.saveEditor()
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }
          }

          ButtonGroup {
            options: Logic.STRENGTHS
            value: root.editStrength
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function (value) { root.editStrength = value }
          }

          ButtonGroup {
            options: Logic.SIZES
            value: root.editSize
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function (value) { root.editSize = value }
          }

          ButtonGroup {
            options: Logic.STYLES
            value: root.editStyle
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            focusable: false
            onChanged: function (value) { root.editStyle = value }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Item {
            width: parent.width
            height: saveButton.implicitHeight

            Body {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: root.dim
              text: Logic.caffeineMg(root.editStrength, root.editSize, root.baseMg) + " mg per cup"
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Chip {
                visible: root.editingPreset !== null
                iconText: "󰩺"
                text: "Delete"
                foreground: root.accent
                onClicked: root.deleteEditor()
              }

              Chip {
                iconText: "󰁍"
                text: "Cancel"
                onClicked: root.back()
              }

              Chip {
                id: saveButton
                iconText: "󰆓"
                text: "Save"
                enabled: String(root.editName).replace(/^\s+|\s+$/g, "").length > 0
                opacity: enabled ? 1 : 0.45
                onClicked: root.saveEditor()
              }
            }
          }
        }

        // ---------------------------------------------------- flash notice

        Body {
          visible: root.flash !== ""
          width: parent.width
          text: root.flash
          color: root.dim
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
