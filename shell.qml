// Aurora: audio and load reactive shader wallpaper.
// Run with `qs -c aurora`. Settings live in ~/.config/aurora/config.json.
// Rebuild the shader after editing aurora.frag:
//   /usr/lib/qt6/bin/qsb --qt6 -o aurora.frag.qsb aurora.frag
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property bool isHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    // Defaults, overridden by config.json
    property var cfg: ({
        wallpaper: "auto",
        colours: "auto",
        tint: false,
        tintGamma: 1.6,
        pauseWhenCovered: true,
        fps: 30,
        idleFps: 12
    })

    function expand(p) {
        return p.startsWith("~/") ? home + p.slice(1) : p;
    }

    FileView {
        path: root.configHome + "/aurora/config.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.cfg = Object.assign({}, root.cfg, JSON.parse(text()));
            } catch (e) {
                console.warn("aurora: config.json is not valid JSON, using defaults");
            }
        }
    }

    property real bass: 0
    property real mid: 0
    property real treble: 0
    property real load: 0
    property real time: 0
    property real wave: 0
    property real flicker: 0
    property real pulse: 0
    property real bassAvg: 0
    property real lastBeat: 0
    property real lastBass: 0
    property bool silent: bass + mid + treble < 0.02

    property string wallpaper: ""
    property color colA: "#29a298"
    property color colB: "#cabd24"
    property color colC: "#cb642e"

    // Attack fast, decay slow, so beats punch and fade smoothly
    function smooth(prev, next) {
        return next > prev ? prev + (next - prev) * 0.6 : prev + (next - prev) * 0.12;
    }

    Process {
        running: true
        command: ["cava", "-p", Quickshell.shellDir + "/cava.conf"]
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";").filter(s => s !== "").map(Number);
                if (v.length < 24) return;
                const avg = (a, b) => v.slice(a, b).reduce((s, x) => s + x, 0) / ((b - a) * 1000);
                const b = avg(0, 4);
                root.bass = root.smooth(root.bass, b);
                // A beat is a bass spike well above the recent average (~0.5 s)
                const now = Date.now();
                if (b > root.bassAvg * 1.15 + 0.04 && b > root.lastBass && now - root.lastBeat > 180) {
                    root.pulse = 1;
                    root.lastBeat = now;
                }
                root.bassAvg = root.bassAvg * 0.97 + b * 0.03;
                root.lastBass = b;
                root.mid = root.smooth(root.mid, avg(4, 14));
                root.treble = root.smooth(root.treble, Math.min(1, avg(14, 24) * 1.8));
            }
        }
    }

    // Window floating state lives in lastIpcObject, which only updates on refresh
    Component.onCompleted: if (isHyprland) Hyprland.refreshToplevels()
    Connections {
        target: root.isHyprland ? Hyprland : null
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode"].includes(event.name))
                Hyprland.refreshToplevels();
        }
    }

    property var lastStat: null
    Process {
        id: statProc
        command: ["head", "-1", "/proc/stat"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().split(/\s+/).slice(1).map(Number);
                const idle = n[3] + n[4];
                const total = n.reduce((s, x) => s + x, 0);
                if (root.lastStat) {
                    const dt = total - root.lastStat.total;
                    if (dt > 0) root.load = root.load * 0.5 + (1 - (idle - root.lastStat.idle) / dt) * 0.5;
                }
                root.lastStat = { idle, total };
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statProc.running = true
    }

    // Full fps with sound, idle fps when silent. CPU load speeds up the flow.
    property real lastTick: Date.now()
    Timer {
        interval: 1000 / Math.max(1, root.silent ? root.cfg.idleFps : root.cfg.fps)
        running: true
        repeat: true
        onTriggered: {
            const now = Date.now();
            const dt = Math.min(0.1, (now - root.lastTick) / 1000);
            root.lastTick = now;
            root.time += dt * (0.6 + root.load * 1.6 + root.bass * 0.8);
            // The aurora waves run on their own clock: each beat surges them, then they ease off
            root.pulse *= Math.exp(-dt * 5);
            root.wave += dt * (0.4 + root.load * 1.6 + root.pulse * 8.0);
            root.flicker += dt * (0.5 + root.treble * 4.0);
        }
    }

    // Colours: "auto" (DMS, then pywal), "dms", "pywal", or a list of three hex colours
    readonly property var colourMode: cfg.colours
    // null until the DMS file has been tried, so pywal is only read once DMS is known missing
    property var dmsColoursFound: null

    // Wallpaper tint stops, dark to light
    property color tint0: "#001419"
    property color tint1: "#103a3c"
    property color tint2: "#29a298"
    property color tint3: "#b7fefa"

    function mixColour(a, b, t) {
        a = Qt.color(a);
        b = Qt.color(b);
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    function setTint(stops) {
        const own = cfg.tintColours;
        if (Array.isArray(own) && own.length >= 4) stops = own;
        tint0 = stops[0];
        tint1 = stops[1];
        tint2 = stops[2];
        tint3 = stops[3];
    }

    onColourModeChanged: {
        if (Array.isArray(colourMode) && colourMode.length >= 3) {
            colA = colourMode[0];
            colB = colourMode[1];
            colC = colourMode[2];
            // No theme to read, so build the tint ramp from the first colour
            setTint([mixColour("#000000", colA, 0.08), mixColour("#000000", colA, 0.4), colA, mixColour(colA, "#ffffff", 0.6)]);
        }
    }

    FileView {
        path: root.colourMode === "auto" || root.colourMode === "dms"
            ? root.home + "/.cache/DankMaterialShell/dms-colors.json" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: root.dmsColoursFound = false
        onLoaded: {
            try {
                const j = JSON.parse(text());
                const c = j.colors[j.mode === "light" ? "light" : "dark"];
                root.colA = c.primary;
                root.colB = c.tertiary;
                root.colC = c.secondary;
                root.setTint([c.background, c.primary_container, c.primary, c.on_primary_container]);
                root.dmsColoursFound = true;
            } catch (e) {}
        }
    }

    FileView {
        path: root.colourMode === "pywal" || (root.colourMode === "auto" && root.dmsColoursFound === false)
            ? root.home + "/.cache/wal/colors.json" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                const c = j.colors;
                root.colA = c.color4;
                root.colB = c.color5;
                root.colC = c.color6;
                const bg = j.special?.background ?? c.color0;
                root.setTint([bg, root.mixColour(bg, c.color4, 0.5), c.color4, j.special?.foreground ?? c.color7]);
            } catch (e) {}
        }
    }

    // Wallpaper: "auto"/"dms" follows DankMaterialShell, anything else is an image path
    readonly property bool followDms: cfg.wallpaper === "auto" || cfg.wallpaper === "dms"

    Connections {
        target: root
        function onCfgChanged() {
            if (!root.followDms) root.wallpaper = "file://" + encodeURI(root.expand(root.cfg.wallpaper));
        }
    }

    FileView {
        path: root.followDms ? root.home + "/.local/state/DankMaterialShell/session.json" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: console.warn("aurora: no DMS wallpaper found, set \"wallpaper\" in config.json")
        onLoaded: {
            try {
                const p = JSON.parse(text()).wallpaperPath;
                if (p && !p.startsWith("#")) root.wallpaper = "file://" + encodeURI(p);
            } catch (e) {}
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            // On Hyprland, only animate when no tiled windows cover the workspace
            // (floating ones are fine); otherwise show the wallpaper still.
            // Other compositors always animate.
            property var hyprMon: root.isHyprland ? Hyprland.monitorFor(modelData) : null
            property var ws: hyprMon?.activeWorkspace
            property int tiled: (ws?.toplevels?.values ?? []).filter(t => !(t.lastIpcObject?.floating ?? false)).length
            property bool hidden: (ws?.hasFullscreen ?? false) || (root.cfg.pauseWhenCovered && tiled > 0)

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "aurora"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            mask: Region {}

            Image {
                id: wall
                anchors.fill: parent
                source: root.wallpaper
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(win.width, win.height)
                asynchronous: true
            }

            ShaderEffectSource {
                id: wallTex
                sourceItem: wall
                hideSource: true
            }

            // Tint pass: only redraws when the image or palette changes. While paused it is
            // shown directly, so there is no need for a wallpaper underneath.
            ShaderEffect {
                id: tinted
                anchors.fill: parent
                visible: wall.status === Image.Ready
                fragmentShader: Quickshell.shellDir + "/tint.frag.qsb"

                property var source: wallTex
                property real enabled: root.cfg.tint ? 1 : 0
                property real gamma: root.cfg.tintGamma
                property color tint0: root.tint0
                property color tint1: root.tint1
                property color tint2: root.tint2
                property color tint3: root.tint3
            }

            ShaderEffectSource {
                id: tintTex
                sourceItem: tinted
                hideSource: !win.hidden
            }

            ShaderEffect {
                anchors.fill: parent
                visible: wall.status === Image.Ready && !win.hidden
                fragmentShader: Quickshell.shellDir + "/aurora.frag.qsb"

                property var source: tintTex
                property real time: root.time
                property real wave: root.wave
                property real flicker: root.flicker
                property real treble: root.treble
                property real bass: root.bass
                property real mid: Quickshell.env("AURORA_DEBUG") ? 0.7 : root.mid
                property real load: root.load
                property real aspect: win.width / Math.max(1, win.height)
                property color colA: root.colA
                property color colB: root.colB
                property color colC: root.colC
            }
        }
    }
}
