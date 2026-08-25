import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "sid.sqlite-viewer"
  ipcTarget: "sid.sqlite-viewer"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var databases: []
  property int selectedIndex: 0
  property bool scanning: false

  readonly property string scriptPath: Qt.resolvedUrl("open-db").toString().replace(/^file:\/\//, "")
  readonly property color dimmed: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)

  function open() {
    root.controller.show()
    refresh()
  }
  function openFromHotkey() { open() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? close() : open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    selectedIndex = 0
    if (!listProc.running) {
      scanning = true
      listProc.running = true
    }
  }

  function shellQuoted(path) { return "'" + String(path).replace(/'/g, "'\\''") + "'" }

  function openDatabase(path) {
    if (root.bar) root.bar.run(root.scriptPath + " " + shellQuoted(path))
    root.close()
  }

  function openEmptyViewer() {
    if (root.bar) root.bar.run(root.scriptPath)
    root.close()
  }

  function openSelected() {
    if (root.databases.length > 0) openDatabase(root.databases[root.selectedIndex].path)
    else openEmptyViewer()
  }

  function fmtSize(bytes) {
    var b = Number(bytes) || 0
    if (b >= 1073741824) return (b / 1073741824).toFixed(b >= 10737418240 ? 0 : 1) + " GB"
    if (b >= 1048576) return Math.round(b / 1048576) + " MB"
    if (b >= 1024) return Math.round(b / 1024) + " KB"
    return b + " B"
  }

  function fmtWhen(mtime) {
    var then = new Date(Number(mtime) * 1000)
    var now = new Date()
    var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    var days = Math.floor((startOfToday - then) / 86400000) + 1
    if (then >= startOfToday)
      return Qt.formatTime(then, "HH:mm")
    if (days === 1) return "yesterday"
    if (days < 7) return days + "d ago"
    return Qt.formatDate(then, "d MMM")
  }

  Process {
    id: listProc
    command: ["bash", root.scriptPath, "--list"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.scanning = false
        // Defense in depth: the helper bounds its output structurally, but
        // never hand an unexpectedly huge payload to JSON.parse either.
        if (text.length > 262144) { root.databases = []; return }
        try { root.databases = JSON.parse(text) } catch (e) { root.databases = [] }
        if (root.selectedIndex >= root.databases.length)
          root.selectedIndex = Math.max(0, root.databases.length - 1)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0 && root.databases.length > 0)
          root.selectedIndex = Math.max(0, Math.min(root.databases.length - 1, root.selectedIndex + dy))
      }
      onReturnRequested: root.openSelected()
      onActivateRequested: root.openSelected()
      onTextKey: function(text) {
        if (text === "r") root.refresh()
        else if (text === "o") root.openEmptyViewer()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(6)

        // ---- Hero: glyph, title, count.
        Item {
          width: parent.width
          height: Style.space(52)

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(14)

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "SQLite Databases"
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                text: root.scanning ? "Scanning…"
                  : (root.databases.length === 0 ? "No recent database files"
                    : root.databases.length + " touched in the last 60 days")
                color: root.dimmed
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        PanelSeparator { width: parent.width }

        // ---- Column headings.
        Item {
          width: parent.width
          height: headerName.implicitHeight + Style.space(6)
          visible: root.databases.length > 0

          PanelSectionHeader {
            id: headerName
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            text: "DATABASE"
            foreground: root.bar ? root.bar.foreground : Color.foreground
          }

          PanelSectionHeader {
            anchors.right: headerWhen.left
            anchors.rightMargin: Style.space(16)
            text: "SIZE"
            foreground: root.bar ? root.bar.foreground : Color.foreground
          }

          PanelSectionHeader {
            id: headerWhen
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            width: Style.space(72)
            horizontalAlignment: Text.AlignRight
            text: "MODIFIED"
            foreground: root.bar ? root.bar.foreground : Color.foreground
          }
        }

        // ---- Rows.
        Repeater {
          model: root.databases

          Rectangle {
            required property var modelData
            required property int index

            width: column.width
            height: rowName.implicitHeight + rowDir.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            color: (index === root.selectedIndex || rowArea.containsMouse)
              ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
              : "transparent"

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.right: rowMeta.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                id: rowName
                width: parent.width
                text: modelData.name
                // Filesystem-derived string: never let it near AutoText/rich text.
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: index === root.selectedIndex
              }

              Text {
                id: rowDir
                width: parent.width
                text: modelData.dir
                // Filesystem-derived string: never let it near AutoText/rich text.
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: root.dimmed
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              id: rowMeta
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(16)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtSize(modelData.size)
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(72)
                horizontalAlignment: Text.AlignRight
                text: root.fmtWhen(modelData.mtime)
                color: root.dimmed
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            MouseArea {
              id: rowArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = index
              onClicked: root.openDatabase(modelData.path)
            }
          }
        }

        PanelSeparator { width: parent.width }

        // ---- Footer: open-empty action and key hints.
        Item {
          width: parent.width
          height: footerAction.implicitHeight + Style.space(14)

          Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: footerAction.implicitWidth + Style.space(16)
            height: footerAction.implicitHeight + Style.space(8)
            radius: Style.cornerRadius
            color: footerArea.containsMouse
              ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
              : "transparent"

            Text {
              id: footerAction
              anchors.centerIn: parent
              text: "Open empty viewer"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: footerArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openEmptyViewer()
            }
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: "↵ open · r rescan · o empty · esc close"
            color: root.dimmed
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
