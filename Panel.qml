import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Per-app theme policy for Omarchy.
//
// The engine ships in bin/ so the widget works right after `omarchy plugin
// add`. It reads ~/.config/omarchy/app-theme/config.conf and applies the
// chosen value to browsers, terminals, btop, Helix, VS Code, and Obsidian.
Panel {
  id: root
  moduleName: "io.github.anishvarsha.app-theme"
  ipcTarget: "io.github.anishvarsha.app-theme"

  readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("bin/omarchy-app-theme")).replace(/^(file|qs):\/\//, ""))
  readonly property string setupScript: decodeURIComponent(String(Qt.resolvedUrl("bin/install-privileged.sh")).replace(/^(file|qs):\/\//, ""))
  readonly property string home: Quickshell.env("HOME") || ""

  property var status: ({})
  property string busyText: ""
  property string errorText: ""
  property string view: "apps"
  property string selectedApp: ""
  property string themeQuery: ""
  property int cursorIndex: -1
  property bool hookAttempted: false

  readonly property var apps: (status.apps || []).filter(function(app) { return app.installed })
  readonly property string currentTheme: status.currentTheme || ""
  readonly property bool helperReady: status.helper === true
  readonly property bool hookReady: status.hook === true
  readonly property var selectedInfo: {
    for (var i = 0; i < apps.length; i++)
      if (apps[i].id === selectedApp) return apps[i]
    return null
  }
  readonly property var filteredThemes: {
    var all = status.themes || []
    var query = themeQuery.trim().toLowerCase()
    if (query === "") return all
    return all.filter(function(slug) {
      return String(slug).toLowerCase().indexOf(query) !== -1 ||
        themeLabel(slug).toLowerCase().indexOf(query) !== -1
    })
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function applyQuiet() {
    if (!applyProc.running) applyProc.running = true
  }

  function themeLabel(slug) {
    return String(slug || "").split("-").map(function(part) {
      return part.charAt(0).toUpperCase() + part.slice(1)
    }).join(" ")
  }

  function valueLabel(value) {
    if (!value || value === "default") return "Omarchy"
    if (value === "off") return "Native"
    return themeLabel(value)
  }

  function appIcon(id) {
    switch (id) {
      case "browser": return "󰖟"
      case "alacritty": return "󰆍"
      case "foot": return "󰆍"
      case "kitty": return "󰆍"
      case "ghostty": return "󰆍"
      case "btop": return "󰍛"
      case "helix": return "󰽎"
      case "vscode": return "󰨞"
      case "obsidian": return "󱓷"
      default: return "󰏘"
    }
  }

  function openApp(id) {
    if (actionProc.running) return
    selectedApp = id
    themeQuery = ""
    view = "detail"
    errorText = ""
  }

  function backToApps() {
    if (actionProc.running) return
    view = "apps"
    selectedApp = ""
    themeQuery = ""
    cursorIndex = -1
  }

  function runSet(app, value) {
    if (actionProc.running) return
    errorText = ""
    busyText = "Applying " + valueLabel(value) + " to " + (app === "browser" ? "browsers" : app) + "…"
    actionProc.command = [root.script, "set", app, value]
    actionProc.running = true
  }

  function resetAll() {
    if (actionProc.running) return
    errorText = ""
    busyText = "Resetting every app to Omarchy defaults…"
    actionProc.command = [root.script, "reset"]
    actionProc.running = true
  }

  function setupBrowser() {
    if (setupProc.running) return
    errorText = ""
    busyText = "Waiting for the one-time browser setup…"
    setupProc.command = ["pkexec", root.setupScript]
    setupProc.running = true
  }

  function installHook() {
    if (hookProc.running) return
    hookAttempted = true
    hookProc.running = true
  }

  function ensureHook() {
    if (!hookReady && !hookAttempted) installHook()
  }

  function moveCursor(step) {
    if (view !== "apps" || apps.length === 0) return
    if (cursorIndex < 0) cursorIndex = 0
    else cursorIndex = Math.max(0, Math.min(apps.length - 1, cursorIndex + step))
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      errorText = ""
      if (view === "detail" && !selectedInfo) backToApps()
    }
  }

  Component.onCompleted: {
    refresh()
    applyQuiet()
  }

  // Keep a browser-native app native even if Omarchy's own theme pipeline
  // rewrites its policy files. The hook installed below is the primary path;
  // this debounced watcher also covers a missing hook and manual edits.
  FileView {
    id: themeNameFile
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: themeDebounce.restart()
  }

  Timer {
    id: themeDebounce
    interval: 1600
    onTriggered: {
      if (!actionProc.running) applyQuiet()
    }
  }

  Timer {
    interval: 90000
    running: true
    repeat: true
    onTriggered: if (!actionProc.running && !setupProc.running) refresh()
  }

  Process {
    id: statusProc
    command: [root.script, "json"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
      onStreamFinished: {
        try {
          root.status = JSON.parse(text)
          root.ensureHook()
        } catch (e) {
          root.errorText = "Could not read app theme status."
        }
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.errorText === "")
        root.errorText = "Could not run " + root.script
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      root.busyText = ""
      if (code !== 0)
        root.errorText = String(actionErr.text || "Could not apply the change.").trim().split("\n").pop()
      root.refresh()
    }
  }

  Process {
    id: setupProc
    stderr: StdioCollector { id: setupErr; waitForEnd: true }
    onExited: function(code) {
      root.busyText = ""
      if (code === 126 || code === 127) {
        root.errorText = "Setup cancelled."
      } else if (code !== 0) {
        root.errorText = String(setupErr.text || "Setup failed.").trim().split("\n").pop()
      } else {
        root.applyQuiet()
      }
      root.refresh()
    }
  }

  Process {
    id: hookProc
    command: [root.script, "install-hook"]
    stderr: StdioCollector { id: hookErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0)
        root.errorText = String(hookErr.text || "Could not install the theme hook.").trim().split("\n").pop()
      root.refresh()
    }
  }

  Process {
    id: applyProc
    command: [root.script, "apply", "--quiet"]
    onExited: function(code) {
      if (code === 0) root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏘"
    tooltipText: root.currentTheme === "" ? "App themes" : "App themes · " + root.themeLabel(root.currentTheme)
    onPressed: function(b) { root.toggle() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        root.moveCursor(dx !== 0 ? dx : dy)
      }
      onActivateRequested: {
        if (root.view === "apps" && root.cursorIndex >= 0 && root.cursorIndex < root.apps.length)
          root.openApp(root.apps[root.cursorIndex].id)
        else if (root.view === "detail" && root.selectedApp !== "")
          root.runSet(root.selectedApp, "default")
      }
      onCloseRequested: {
        if (root.view === "detail") root.backToApps()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Header ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: root.view === "detail" ? root.appIcon(root.selectedApp) : "󰏘"
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
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.view === "detail" && root.selectedInfo
                ? root.selectedInfo.label
                : "App themes"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.busyText !== ""
                ? root.busyText.toUpperCase()
                : "CURRENT THEME · " + root.themeLabel(root.currentTheme).toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        Text {
          visible: root.errorText !== ""
          text: root.errorText
          color: Color.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          width: parent.width
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- App list ----------
        Column {
          visible: root.view === "apps"
          width: parent.width
          spacing: Style.space(8)

          Text {
            visible: root.apps.length === 0
            text: "No supported apps found."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.apps
            Button {
              required property var modelData
              required property int index
              width: column.width
              iconText: root.appIcon(modelData.id)
              iconSize: Style.font.title
              text: modelData.label + "   ·   " + root.valueLabel(modelData.value)
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              leftAlign: true
              bordered: true
              active: modelData.value !== "default"
              hasCursor: root.cursorIndex === index
              onClicked: root.openApp(modelData.id)
              onHovered: function(hovered) { if (hovered) root.cursorIndex = index }
            }
          }

          Item { width: 1; height: Style.space(2) }

          Button {
            width: parent.width
            iconText: "󰑓"
            text: "Reset everything to Omarchy defaults"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.resetAll()
          }

          // ---------- One-time browser setup ----------
          Row {
            visible: !root.helperReady
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width - setupButton.width - parent.spacing
              text: "Browser control needs a one-time system setup."
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              id: setupButton
              text: "Set up"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.setupBrowser()
            }
          }

          // ---------- Background sync ----------
          Row {
            visible: !root.hookReady
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width - hookButton.width - parent.spacing
              text: "Background sync is off: theme switches will not be remembered."
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              id: hookButton
              text: "Enable"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.installHook()
            }
          }
        }

        // ---------- App detail ----------
        Column {
          visible: root.view === "detail"
          width: parent.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: "‹  All apps"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: root.backToApps()
            }

            Text {
              text: root.selectedInfo ? root.valueLabel(root.selectedInfo.value) : ""
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSectionHeader {
            text: "MODE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: parent.cellWidth
              text: "Follow Omarchy"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              active: root.selectedInfo && root.selectedInfo.value === "default"
              onClicked: root.runSet(root.selectedApp, "default")
            }

            Button {
              width: parent.cellWidth
              text: "Native look"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              active: root.selectedInfo && root.selectedInfo.value === "off"
              onClicked: root.runSet(root.selectedApp, "off")
            }
          }

          PanelSectionHeader {
            text: "USE ANOTHER THEME FOR THIS APP"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          TextField {
            id: themeSearch
            width: parent.width
            placeholderText: "Search " + root.filteredThemes.length + " themes…"
            foreground: root.bar.foreground
            accent: Color.accent
            font.family: root.bar.fontFamily
            text: root.themeQuery
            onTextChanged: root.themeQuery = text
            Keys.onEscapePressed: function(event) {
              if (root.themeQuery !== "") root.themeQuery = ""
              else root.backToApps()
              event.accepted = true
            }
            Keys.onReturnPressed: function(event) {
              if (root.filteredThemes.length > 0)
                root.runSet(root.selectedApp, root.filteredThemes[0])
              event.accepted = true
            }
          }

          Text {
            visible: root.filteredThemes.length === 0
            text: "No themes match “" + root.themeQuery + "”."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            width: parent.width
          }

          Flickable {
            width: parent.width
            height: Math.min(themeGrid.implicitHeight, Style.space(230))
            contentWidth: width
            contentHeight: themeGrid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Grid {
              id: themeGrid
              width: parent.width
              columns: 2
              spacing: Style.space(6)
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.filteredThemes
                Button {
                  required property var modelData
                  width: themeGrid.cellWidth
                  text: root.themeLabel(modelData)
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  bordered: true
                  active: root.selectedInfo && root.selectedInfo.value === modelData
                  onClicked: root.runSet(root.selectedApp, modelData)
                }
              }
            }
          }
        }
      }
    }
  }
}
