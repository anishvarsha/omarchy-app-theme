import QtQuick
import QtQuick.Controls
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
  property var desktopValues: DesktopEntries.applications.values || []
  property string busyText: ""
  property string errorText: ""
  property string view: "apps"
  property string selectedApp: ""
  property string appQuery: ""
  property string themeQuery: ""
  property int cursorIndex: -1
  property bool hookAttempted: false

  readonly property var apps: (status.apps || []).filter(function(app) { return app.installed })
  readonly property string currentTheme: status.currentTheme || ""
  readonly property bool helperReady: status.helper === true
  readonly property bool hookReady: status.hook === true
  readonly property bool perAppEnabled: status.enabled !== false
  readonly property var selectedInfo: {
    for (var i = 0; i < apps.length; i++)
      if (apps[i].id === selectedApp) return apps[i]
    return null
  }
  readonly property string targetApp: view === "all" ? "all" : selectedApp
  readonly property string allValue: {
    if (apps.length === 0) return "default"
    var first = apps[0].value
    for (var i = 1; i < apps.length; i++)
      if (apps[i].value !== first) return ""
    return first
  }
  readonly property var otherApps: {
    var values = desktopValues || []
    var seen = {}
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay === true) continue
      var id = String(entry.id || "").replace(/\.desktop$/, "")
      if (id === "" || seen[id] === true) continue
      if (desktopIsCovered(entry)) continue
      seen[id] = true
      out.push({
        id: "desktop:" + id,
        desktopId: id,
        label: String(entry.name || id),
        value: "system",
        supported: false,
        installed: true,
        iconName: String(entry.icon || ""),
        keywords: "desktop system " + String(entry.genericName || "") + " " + String(entry.keywords || "")
      })
    }
    out.sort(function(a, b) { return a.label.localeCompare(b.label) })
    return out
  }
  readonly property int totalApps: apps.length + otherApps.length
  readonly property var filteredApps: filterAppList(apps)
  readonly property var filteredOtherApps: filterAppList(otherApps)
  readonly property bool hasAppMatches: filteredApps.length + filteredOtherApps.length > 0
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

  function appKeywords(id) {
    switch (id) {
      case "browser": return "chrome chromium edge brave web"
      case "alacritty": return "terminal term"
      case "foot": return "terminal term"
      case "kitty": return "terminal term"
      case "ghostty": return "terminal term"
      case "btop": return "system monitor resources cpu"
      case "helix": return "editor hx text"
      case "nvim": return "neovim vim editor text code"
      case "tmux": return "terminal multiplexer term"
      case "vscode": return "code cursor vscodium insiders editor text"
      case "zed": return "zed editor text code rust"
      case "obsidian": return "notes markdown editor text"
      case "claude": return "ai agent anthropic assistant code terminal"
      case "pi": return "ai agent assistant code terminal"
      case "t3code": return "ai agent assistant t3 code editor"
      case "hermes": return "ai agent assistant code desktop"
      default: return ""
    }
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
      case "nvim": return ""
      case "tmux": return "󰆍"
      case "vscode": return "󰨞"
      case "zed": return "󰨞"
      case "obsidian": return "󱓷"
      case "claude": return "󰚩"
      case "pi": return "󰚩"
      case "t3code": return "󰚩"
      case "hermes": return "󰚩"
      default: return "󰏘"
    }
  }

  function filterAppList(list) {
    var query = appQuery.trim().toLowerCase()
    if (query === "") return list
    return list.filter(function(app) {
      return String(app.id).toLowerCase().indexOf(query) !== -1 ||
        String(app.label).toLowerCase().indexOf(query) !== -1 ||
        String(app.keywords || appKeywords(app.id)).toLowerCase().indexOf(query) !== -1
    })
  }

  // Supported apps already have a dedicated row in `apps`. Do not repeat the
  // same desktop entry in the "other installed apps" section.
  function desktopIsCovered(entry) {
    var id = String(entry.id || "").toLowerCase().replace(/\.desktop$/, "")
    var name = String(entry.name || "").toLowerCase()
    var text = id + " " + name + " " + String(entry.genericName || "").toLowerCase()

    if (id === "dev.zed.zed" || id === "zed" || name === "zed") return true
    if (text.indexOf("visual studio code") !== -1 || text.indexOf("vscodium") !== -1 ||
        text.indexOf("vscode") !== -1 || text.indexOf("code - oss") !== -1) return true
    if (id === "code" || id === "code-insiders" || id === "codium" ||
        id === "vscodium" || id === "cursor") return true
    if (text.indexOf("obsidian") !== -1) return true
    if (text.indexOf("claude code") !== -1) return true
    if (text.indexOf("t3 code") !== -1 || text.indexOf("t3code") !== -1) return true
    if (text.indexOf("hermes") !== -1) return true
    if (id === "pi" || name === "pi") return true
    if (id === "alacritty" || name === "alacritty") return true
    if (id === "foot" || name === "foot") return true
    if (id === "kitty" || name === "kitty") return true
    if (text.indexOf("ghostty") !== -1) return true
    if (id === "btop" || name === "btop") return true
    if (id === "helix" || name === "helix" || id === "hx") return true
    if (id === "nvim" || id === "neovim" || text.indexOf("neovim") !== -1) return true
    if (id === "tmux" || name === "tmux") return true
    if (id === "chromium" || id === "chromium-browser" ||
        id === "google-chrome" || id === "microsoft-edge" ||
        id === "brave-browser" || id === "brave" ||
        text.indexOf("chromium") !== -1) return true
    return false
  }

  function openApp(id) {
    if (actionProc.running || !root.perAppEnabled) return
    var supported = false
    for (var i = 0; i < apps.length; i++)
      if (apps[i].id === id) supported = true
    if (!supported) {
      var label = id
      for (var j = 0; j < otherApps.length; j++)
        if (otherApps[j].id === id) label = otherApps[j].label
      errorText = label + " follows Omarchy's system GTK theme. It does not have a separate app-theme adapter."
      return
    }
    selectedApp = id
    themeQuery = ""
    view = "detail"
    errorText = ""
  }

  function openAll() {
    if (actionProc.running || !root.perAppEnabled) return
    selectedApp = ""
    themeQuery = ""
    view = "all"
    errorText = ""
  }

  function backToApps() {
    if (actionProc.running) return
    view = "apps"
    selectedApp = ""
    themeQuery = ""
    cursorIndex = -1
    Qt.callLater(function() { appSearch.forceActiveFocus() })
  }

  function runSet(app, value) {
    if (actionProc.running) return
    errorText = ""
    busyText = app === "enabled"
      ? (value === "on" ? "Turning per-app theming on…" : "Applying Omarchy everywhere…")
      : "Applying " + valueLabel(value) + " to " + (app === "browser" ? "browsers" : app === "all" ? "all apps" : app) + "…"
    actionProc.command = [root.script, "set", app, value]
    actionProc.running = true
  }

  function togglePerApp() {
    runSet("enabled", root.perAppEnabled ? "off" : "on")
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
    if (view !== "apps" || filteredApps.length === 0) return
    if (cursorIndex < 0) cursorIndex = 0
    else cursorIndex = Math.max(0, Math.min(filteredApps.length - 1, cursorIndex + step))
  }

  onAppQueryChanged: {
    cursorIndex = filteredApps.length > 0 && appQuery !== "" ? 0 : -1
  }

  onOpenedChanged: {
    if (opened) {
      desktopValues = (DesktopEntries.applications.values || []).slice()
      refresh()
      errorText = ""
      appQuery = ""
      cursorIndex = -1
      view = "apps"
      selectedApp = ""
      themeQuery = ""
      Qt.callLater(function() { appSearch.forceActiveFocus() })
    }
  }

  Component.onCompleted: {
    desktopValues = (DesktopEntries.applications.values || []).slice()
    refresh()
    applyQuiet()
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.desktopValues = (DesktopEntries.applications.values || []).slice()
    }
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
      blocked: appSearch.activeFocus || themeSearch.activeFocus
      onMoveRequested: function(dx, dy) {
        root.moveCursor(dx !== 0 ? dx : dy)
      }
      onActivateRequested: {
        if (root.view === "apps" && root.cursorIndex >= 0 && root.cursorIndex < root.filteredApps.length)
          root.openApp(root.filteredApps[root.cursorIndex].id)
        else if (root.view === "detail" && root.selectedApp !== "")
          root.runSet(root.selectedApp, "default")
      }
      onCloseRequested: {
        if (root.view === "detail" || root.view === "all") root.backToApps()
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
            text: root.view === "detail"
              ? root.appIcon(root.selectedApp)
              : root.view === "all" ? "󰀻" : "󰏘"
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
                : root.view === "all" ? "All apps" : "App themes"
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

          Button {
            width: parent.width
            iconText: root.perAppEnabled ? "󰄬" : "󰅖"
            iconSize: Style.font.title
            text: root.perAppEnabled ? "Per-app theming is on" : "Per-app theming is off"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            leftAlign: true
            bordered: true
            active: root.perAppEnabled
            onClicked: root.togglePerApp()
          }

          Text {
            visible: !root.perAppEnabled
            text: "Every app follows the current Omarchy theme. Saved app choices return when you turn this back on."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Text {
            visible: root.totalApps === 0
            text: "No installed apps found."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          TextField {
            id: appSearch
            visible: root.totalApps > 0
            width: parent.width
            placeholderText: "Search " + root.totalApps + " apps…"
            foreground: root.bar.foreground
            accent: Color.accent
            font.family: root.bar.fontFamily
            text: root.appQuery
            onTextChanged: root.appQuery = text
            Keys.onEscapePressed: function(event) {
              if (root.appQuery !== "") root.appQuery = ""
              else root.close()
              event.accepted = true
            }
            Keys.onReturnPressed: function(event) {
              var index = root.cursorIndex >= 0 ? root.cursorIndex : 0
              if (root.filteredApps.length > index)
                root.openApp(root.filteredApps[index].id)
              else if (root.filteredOtherApps.length > 0)
                root.openApp(root.filteredOtherApps[0].id)
              event.accepted = true
            }
            Keys.onDownPressed: function(event) {
              root.moveCursor(1)
              event.accepted = true
            }
            Keys.onUpPressed: function(event) {
              root.moveCursor(-1)
              event.accepted = true
            }
          }

          Button {
            visible: root.apps.length > 0
            enabled: root.perAppEnabled
            width: parent.width
            iconText: "󰀻"
            iconSize: Style.font.title
            text: "All apps   ·   apply or remove a theme everywhere"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            leftAlign: true
            bordered: true
            onClicked: root.openAll()
          }

          Text {
            visible: root.totalApps > 0 && !root.hasAppMatches
            text: "No apps match “" + root.appQuery + "”."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            width: parent.width
          }

          Flickable {
            id: appScroll
            visible: root.totalApps > 0 && root.hasAppMatches
            width: parent.width
            height: Math.min(appRows.implicitHeight, Style.space(320))
            contentWidth: width
            contentHeight: appRows.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: appRows
              width: appScroll.width
              spacing: Style.space(6)

              PanelSectionHeader {
                visible: root.filteredApps.length > 0
                text: "SUPPORTED APPS"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              Repeater {
                model: root.filteredApps
                Button {
                  required property var modelData
                  required property int index
                  enabled: root.perAppEnabled
                  width: appRows.width
                  iconText: root.appIcon(modelData.id)
                  iconSize: Style.font.title
                  text: modelData.label + "   ·   " + (root.perAppEnabled ? root.valueLabel(modelData.value) : "Omarchy")
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

              PanelSectionHeader {
                visible: root.filteredOtherApps.length > 0
                text: "OTHER INSTALLED APPS · SYSTEM THEME"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              Repeater {
                model: root.filteredOtherApps
                Button {
                  required property var modelData
                  width: appRows.width
                  iconText: "󰏘"
                  iconSize: Style.font.title
                  text: modelData.label + "   ·   System theme"
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  leftAlign: true
                  bordered: true
                  opacity: 0.72
                  onClicked: root.openApp(modelData.id)
                }
              }

              Item { width: 1; height: Style.space(2) }
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

        // ---------- App detail / bulk actions ----------
        Column {
          visible: root.view === "detail" || root.view === "all"
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
              text: root.view === "all"
                ? (root.allValue !== "" ? root.valueLabel(root.allValue) : "Mixed")
                : root.selectedInfo ? root.valueLabel(root.selectedInfo.value) : ""
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Text {
            visible: root.view === "all"
            text: "These actions replace the theme choice for every supported app."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
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
              active: root.targetApp === "all"
                ? root.allValue === "default"
                : root.selectedInfo && root.selectedInfo.value === "default"
              onClicked: root.runSet(root.targetApp, "default")
            }

            Button {
              width: parent.cellWidth
              text: "Native look"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              active: root.targetApp === "all"
                ? root.allValue === "off"
                : root.selectedInfo && root.selectedInfo.value === "off"
              onClicked: root.runSet(root.targetApp, "off")
            }
          }

          PanelSectionHeader {
            text: root.view === "all"
              ? "APPLY ONE THEME TO ALL APPS"
              : "USE ANOTHER THEME FOR THIS APP"
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
                root.runSet(root.targetApp, root.filteredThemes[0])
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
                  active: root.targetApp !== "all" && root.selectedInfo && root.selectedInfo.value === modelData
                  onClicked: root.runSet(root.targetApp, modelData)
                }
              }
            }
          }
        }
      }
    }
  }
}
