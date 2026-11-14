import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "acer-sense"

    property var telemetry: ({})
    property var gpuData: ({})
    property bool popoutVisible: false
    property string ctlError: ""
    property string gpuSwitchingTo: ""
    property string gpuPendingRebootMode: ""
    property bool gpuRebootRequired: false

    property string platformProfile: ""
    property string fanHwmonPath: ""
    readonly property string effectiveProfile: root.platformProfile || root.telemetry.profile || "balanced"
    readonly property int gpuTabIndex: root.telemetry.hasRgb ? 3 : 2

    readonly property string pillContent: pluginData.pillContent || "cpuTemp"
    readonly property int pollInterval: (pluginData.pollInterval || 4) * 1000
    readonly property bool hasNs: root.telemetry.hasNs !== false
    readonly property bool hasHelper: root.telemetry.hasHelper === true

    readonly property string pluginPath: PluginService.getPluginPath(root.pluginId) || (PluginService.pluginDirectory + "/acerSensePro")
    readonly property string readerPath: root.pluginPath + "/acer-read"

    readonly property int pillFontSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)

    readonly property var profileFallback: ["low-power", "quiet", "balanced", "balanced-performance"]
    readonly property var profileValues: root.parseProfileChoices(root.telemetry.profileChoices)
    readonly property var profileLabels: root.profileValues.map(p => root.profileLabel(p))

    FileView {
        id: profileFileView
        path: "/sys/firmware/acpi/platform_profile"
        onLoaded: {
            const p = profileFileView.text().trim();
            if (p)
                root.platformProfile = p;
        }
    }

    FileView {
        id: fanFileView
        path: root.fanHwmonPath
    }

    Timer {
        id: fanReloadTimer
        interval: root.pollInterval
        running: !root.popoutVisible && root.pillContent === "fanRpm" && root.fanHwmonPath !== ""
        repeat: true
        onTriggered: fanFileView.reload()
    }

    // Active Tab in Popout: 0=Overview, 1=Features, 2=Keyboard RGB, 3=GPU
    property int activeTab: 0

    // Fan Control State
    property string activeFanMode: "auto"
    property bool customExplicitlyPicked: false
    property int customCpuFan: 50
    property int customGpuFan: 50
    property bool fanCustomInitialized: false

    onPopoutVisibleChanged: {
        if (!popoutVisible) {
            root.fanCustomInitialized = false;
        } else {
            profileFileView.reload();
            root.refreshSysfs();
            root.refreshGpu();
        }
    }
    onActiveTabChanged: {
        if (root.popoutVisible && root.activeTab === root.gpuTabIndex)
            root.refreshGpu();
    }

    property bool cpuSubscribed: false
    function updateCpuSubscription() {
        if (typeof DgopService === "undefined" || !DgopService.addRef)
            return;
        const needed = (root.pillContent === "cpuTemp");
        if (needed && !root.cpuSubscribed) {
            DgopService.addRef(["cpu"]);
            root.cpuSubscribed = true;
        } else if (!needed && root.cpuSubscribed) {
            DgopService.removeRef(["cpu"]);
            root.cpuSubscribed = false;
        }
    }
    onPillContentChanged: updateCpuSubscription()

    Component.onCompleted: {
        updateCpuSubscription();
        root.refreshSysfs();
        root.refreshGpu();
    }

    Component.onDestruction: {
        if (root.cpuSubscribed && typeof DgopService !== "undefined" && DgopService.removeRef) {
            DgopService.removeRef(["cpu"]);
            root.cpuSubscribed = false;
        }
    }

    // RGB Controls State
    property int rgbMode: 0
    property int rgbSpeed: 1
    property int rgbBrightness: 100
    property int rgbDirection: 2
    property string rgbColorHex: "00aec7"
    property int rgbSubTab: 0 // 0=Effects, 1=Per-Zone

    property string zone1Color: "00aec7"
    property string zone2Color: "00aec7"
    property string zone3Color: "00aec7"
    property string zone4Color: "00aec7"
    property int zoneBrightness: 100
    property int activeZoneIndex: 0 // 0=All, 1=Z1, 2=Z2, 3=Z3, 4=Z4

    readonly property var rgbModes: [
        "Static", "Breathing", "Neon", "Wave",
        "Shifting", "Zoom", "Meteor", "Twinkling"
    ]

    readonly property var presetColors: [
        { name: "Cyan", hex: "00aec7" },
        { name: "Red", hex: "ff3333" },
        { name: "Orange", hex: "ff8800" },
        { name: "Yellow", hex: "ffdd00" },
        { name: "Green", hex: "33ff57" },
        { name: "Blue", hex: "3388ff" },
        { name: "Purple", hex: "aa33ff" },
        { name: "Magenta", hex: "ff00aa" },
        { name: "White", hex: "ffffff" }
    ]

    property var pendingCtlArgs: null
    property string pendingCtlDesc: ""
    property bool pendingCtlSilent: false

    property bool rgbSyncing: false

    onRgbModeChanged: root.scheduleRgbEffectApply()
    onRgbSpeedChanged: root.scheduleRgbEffectApply()
    onRgbBrightnessChanged: root.scheduleRgbEffectApply()
    onRgbDirectionChanged: root.scheduleRgbEffectApply()
    onRgbColorHexChanged: root.scheduleRgbEffectApply()

    onZone1ColorChanged: root.scheduleRgbZonesApply()
    onZone2ColorChanged: root.scheduleRgbZonesApply()
    onZone3ColorChanged: root.scheduleRgbZonesApply()
    onZone4ColorChanged: root.scheduleRgbZonesApply()
    onZoneBrightnessChanged: root.scheduleRgbZonesApply()

    function scheduleRgbEffectApply() {
        if (root.rgbSyncing) return;
        if (root.rgbSubTab === 0) {
            rgbDebounceTimer.restart();
        }
    }

    function scheduleRgbZonesApply() {
        if (root.rgbSyncing) return;
        if (root.rgbSubTab === 1) {
            zoneDebounceTimer.restart();
        }
    }

    Timer {
        id: rgbDebounceTimer
        interval: 180
        repeat: false
        onTriggered: root.applyRgbEffect(true)
    }

    Timer {
        id: zoneDebounceTimer
        interval: 180
        repeat: false
        onTriggered: root.applyRgbZones(true)
    }

    Timer {
        id: ctlCooldownTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (root.pendingCtlArgs) {
                const nextArgs = root.pendingCtlArgs;
                const nextDesc = root.pendingCtlDesc;
                const nextSilent = root.pendingCtlSilent;
                root.pendingCtlArgs = null;
                root.pendingCtlDesc = "";
                root.pendingCtlSilent = false;
                root.runCtl(nextArgs, nextDesc, nextSilent);
            }
        }
    }

    popoutWidth: Math.min(Theme.dialogMaxWidth, 440)

    component SegSelector: DButtonGroup {
        id: seg
        property var labels: []
        property int current: -1
        signal picked(int index)

        model: seg.labels
        currentIndex: seg.current
        checkEnabled: false
        fillWidth: true
        size: seg.labels.length >= 5 ? "small" : "medium"
        onSelectionChanged: (index, selected) => {
            if (selected)
                seg.picked(index);
        }
    }

    function parseProfileChoices(raw) {
        const s = (raw || "").trim();
        if (!s)
            return root.profileFallback;
        const list = s.split(/\s+/).filter(x => x.length > 0);
        return list.length > 0 ? list : root.profileFallback;
    }

    function profileLabel(p) {
        switch (p) {
        case "low-power":
            return "Eco";
        case "cool":
            return "Cool";
        case "quiet":
            return "Quiet";
        case "balanced":
            return "Balanced";
        case "balanced-performance":
            return "Performance";
        case "performance":
        case "turbo":
            return "Turbo";
        }
        return p;
    }

    function profileIcon(p) {
        switch (p) {
        case "low-power":
            return "energy_savings_leaf";
        case "cool":
            return "ac_unit";
        case "quiet":
            return "bedtime";
        case "balanced":
            return "balance";
        case "balanced-performance":
            return "bolt";
        case "performance":
        case "turbo":
            return "rocket_launch";
        }
        return "tune";
    }

    function setCpuFanStep(delta) {
        root.customCpuFan = Math.max(20, Math.min(100, Math.round((root.customCpuFan + delta) / 5) * 5));
    }

    function setGpuFanStep(delta) {
        root.customGpuFan = Math.max(20, Math.min(100, Math.round((root.customGpuFan + delta) / 5) * 5));
    }

    function setBothFans(val) {
        const snapped = Math.max(20, Math.min(100, Math.round(val / 5) * 5));
        root.customCpuFan = snapped;
        root.customGpuFan = snapped;
    }

    function pillSecondary() {
        if (root.pillContent === "cpuTemp") {
            if (typeof DgopService !== "undefined" && DgopService.cpuTemperature > 0)
                return Math.round(DgopService.cpuTemperature) + "°";
            if (root.telemetry.cpuTemp != null)
                return root.telemetry.cpuTemp + "°";
            return "";
        }
        if (root.pillContent === "fanRpm") {
            const raw = fanFileView.text().trim();
            if (raw) {
                const rpm = parseInt(raw);
                if (!isNaN(rpm)) return rpm + " rpm";
            }
            if (root.telemetry.fanCpu != null)
                return root.telemetry.fanCpu + " rpm";
            return "";
        }
        return "";
    }

    function runCtl(args, desc, silent) {
        if (ctlProcess.running) {
            root.pendingCtlArgs = args;
            root.pendingCtlDesc = desc || "";
            root.pendingCtlSilent = !!silent;
            return;
        }
        root.ctlError = "";
        ctlProcess.actionDesc = desc || "";
        ctlProcess.isSilent = !!silent;
        ctlProcess.command = ["sudo", "-n", "/usr/local/bin/acer-ctl"].concat(args);
        ctlProcess.running = true;
    }

    function runPkexecInstall() {
        if (pkexecInstallProcess.running)
            return;
        pkexecInstallProcess.command = ["pkexec", "sh", root.pluginPath + "/helper/install.sh"];
        pkexecInstallProcess.running = true;
    }

    function copyInstallCommand() {
        const cmd = "sudo sh \"" + root.pluginPath + "/helper/install.sh\"";
        clipboardProcess.command = ["dms", "cl", "copy", cmd];
        clipboardProcess.running = true;
        ToastService.showInfo("Install command copied to clipboard!");
    }

    function copyEnvyInstallCommand() {
        const cmd = root.gpuData.envyInstallCmd || "sudo pip install envycontrol";
        clipboardProcess.command = ["dms", "cl", "copy", cmd];
        clipboardProcess.running = true;
        ToastService.showInfo("Install command copied to clipboard!");
    }

    function ppdForProfile(p) {
        // Only return a slug for exact 1:1 matches so that power-profiles-daemon
        // does not overwrite Acer's official hardware intermediate profiles
        // (such as 'quiet', 'cool', and 'balanced-performance').
        switch (p) {
        case "low-power":
            return "power-saver";
        case "balanced":
            return "balanced";
        case "performance":
            return "performance";
        }
        return "";
    }

    function setProfile(p) {
        root.platformProfile = p;
        runCtl(["profile", p], "Profile: " + p);
        const ppd = root.ppdForProfile(p);
        if (ppd && typeof PowerProfileWatcher !== "undefined" && PowerProfileWatcher.available) {
            const parsed = PowerProfileWatcher.parseProfileSlug ? PowerProfileWatcher.parseProfileSlug(ppd) : -1;
            if (parsed !== -1) {
                PowerProfileWatcher.applyProfile(parsed);
            }
        }
    }

    function setFan(preset) {
        root.customExplicitlyPicked = false;
        runCtl(["fan", preset], "Fan: " + preset);
    }

    function setFanDual(cpu, gpu) {
        const c = Math.max(20, Math.min(100, Math.round(cpu / 5) * 5));
        const g = Math.max(20, Math.min(100, Math.round(gpu / 5) * 5));
        runCtl(["fan", c + "," + g], "Fan: CPU " + c + "%, GPU " + g + "%");
    }

    function setBatteryLimit(on) {
        runCtl(["battery-limit", on ? "on" : "off"], "Battery limit: " + (on ? "80%" : "off"));
    }

    function setBatteryCalibration(start) {
        runCtl(["battery-calibration", start ? "start" : "stop"], "Battery calibration: " + (start ? "Started" : "Stopped"));
    }

    function setUsbCharging(v) {
        runCtl(["usb-charging", v], "USB charging: " + v);
    }

    function setBacklightTimeout(on) {
        runCtl(["backlight-timeout", on ? "on" : "off"], "Backlight timeout: " + (on ? "30s" : "Off"));
    }

    function setBootSound(on) {
        runCtl(["boot-sound", on ? "on" : "off"], "Boot sound: " + (on ? "On" : "Off"));
    }

    function setLcdOverride(on) {
        runCtl(["lcd-override", on ? "on" : "off"], "LCD Overdrive: " + (on ? "On" : "Off"));
    }

    function applyRgbEffect(silent) {
        const isSilent = (silent !== undefined) ? silent : true;
        const rgb = root.hexToRgb(root.rgbColorHex);
        const hex = (root.rgbColorHex || "00aec7").replace("#", "").toLowerCase();
        if (root.rgbMode === 0) {
            // Mode 0 (Static): sync state variables, acer-ctl handles both four_zone_mode and per_zone_mode safely
            root.zone1Color = hex;
            root.zone2Color = hex;
            root.zone3Color = hex;
            root.zone4Color = hex;
            root.zoneBrightness = root.rgbBrightness;
            const effectArgs = ["rgb-effect", "0", "0", String(root.rgbBrightness), "0", String(rgb.r), String(rgb.g), String(rgb.b)];
            runCtl(effectArgs, "Keyboard Static Color: #" + hex.toUpperCase(), isSilent);
            return;
        }
        const speed = Math.max(1, Math.min(9, root.rgbSpeed));
        const direction = (root.rgbMode === 3 || root.rgbMode === 4) ? root.rgbDirection : 0;
        const args = ["rgb-effect", String(root.rgbMode), String(speed), String(root.rgbBrightness), String(direction), String(rgb.r), String(rgb.g), String(rgb.b)];
        runCtl(args, "Keyboard RGB Effect: " + root.rgbModes[root.rgbMode], isSilent);
    }

    function applyRgbZones(silent) {
        const isSilent = (silent !== undefined) ? silent : true;
        const args = ["rgb-zones", root.zone1Color, root.zone2Color, root.zone3Color, root.zone4Color, String(root.zoneBrightness)];
        runCtl(args, "Keyboard 4-Zone RGB applied", isSilent);
    }

    function setZoneColor(hex) {
        const clean = hex.replace("#", "").toLowerCase();
        if (root.activeZoneIndex === 0 || root.activeZoneIndex === 1) root.zone1Color = clean;
        if (root.activeZoneIndex === 0 || root.activeZoneIndex === 2) root.zone2Color = clean;
        if (root.activeZoneIndex === 0 || root.activeZoneIndex === 3) root.zone3Color = clean;
        if (root.activeZoneIndex === 0 || root.activeZoneIndex === 4) root.zone4Color = clean;
    }

    function currentActiveZoneHex() {
        switch (root.activeZoneIndex) {
        case 1: return root.zone1Color;
        case 2: return root.zone2Color;
        case 3: return root.zone3Color;
        case 4: return root.zone4Color;
        default: return root.zone1Color;
        }
    }

    function zoneTextColor(hex) {
        const c = root.hexToRgb(hex || "000000");
        const lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
        return lum > 140 ? "#000000" : "#FFFFFF";
    }

    function zoneTextBg(hex) {
        const c = root.hexToRgb(hex || "000000");
        const lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
        return lum > 140 ? "rgba(0, 0, 0, 0.18)" : "rgba(255, 255, 255, 0.22)";
    }

    function hexToRgb(hex) {
        const clean = hex.replace("#", "");
        return {
            r: parseInt(clean.substring(0, 2), 16) || 0,
            g: parseInt(clean.substring(2, 4), 16) || 0,
            b: parseInt(clean.substring(4, 6), 16) || 0
        };
    }

    function setGpu(mode) {
        root.gpuSwitchingTo = mode;
        root.gpuPendingRebootMode = mode;
        runCtl(["gpu", mode], "GPU: " + mode + " — reboot to apply");
    }

    function refreshSysfs() {
        if (!sysfsProcess.running)
            sysfsProcess.running = true;
    }
    function refreshGpu() {
        if (!gpuProcess.running)
            gpuProcess.running = true;
    }

    Process {
        id: sysfsProcess
        command: ["sh", root.readerPath, "sysfs"]
        running: false
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (!t)
                    return;
                try {
                    const data = JSON.parse(t);
                    root.telemetry = data;
                    if (data.fanHwmonPath && root.fanHwmonPath !== data.fanHwmonPath)
                        root.fanHwmonPath = data.fanHwmonPath;

                    // Sync initial RGB state from hardware if available
                    root.rgbSyncing = true;
                    if (data.fourZoneMode && root.rgbMode === 0) {
                        const parts = data.fourZoneMode.split(",");
                        if (parts.length >= 7) {
                            root.rgbMode = parseInt(parts[0]) || 0;
                            root.rgbSpeed = parseInt(parts[1]) || 0;
                            root.rgbBrightness = parseInt(parts[2]) || 100;
                            root.rgbDirection = parseInt(parts[3]) || 2;
                        }
                    }
                    if (data.perZoneMode && root.zone1Color === "00aec7") {
                        const zparts = data.perZoneMode.split(",");
                        if (zparts.length >= 5) {
                            root.zone1Color = zparts[0];
                            root.zone2Color = zparts[1];
                            root.zone3Color = zparts[2];
                            root.zone4Color = zparts[3];
                            root.zoneBrightness = parseInt(zparts[4]) || 100;
                        }
                    }
                    root.rgbSyncing = false;

                    // Sync fan state from telemetry
                    if (data.fanSpeed) {
                        if (data.fanSpeed === "0,0") {
                            if (!root.customExplicitlyPicked && !root.popoutVisible)
                                root.activeFanMode = "auto";
                        } else if (data.fanSpeed === "100,100") {
                            if (!root.customExplicitlyPicked && !root.popoutVisible)
                                root.activeFanMode = "max";
                        } else {
                            if (!root.customExplicitlyPicked && !root.popoutVisible)
                                root.activeFanMode = "custom";
                            const fparts = data.fanSpeed.split(",");
                            if (fparts.length >= 2) {
                                const c = parseInt(fparts[0]) || 0;
                                const g = parseInt(fparts[1]) || 0;
                                // Only update custom fan values from hardware if popout is closed or uninitialized
                                if (!root.popoutVisible || !root.fanCustomInitialized) {
                                    if (c >= 20) root.customCpuFan = Math.round(c / 5) * 5;
                                    if (g >= 20) root.customGpuFan = Math.round(g / 5) * 5;
                                    root.fanCustomInitialized = true;
                                }
                            }
                        }
                    }
                } catch (e) {
                    console.warn("acerSense sysfs parse:", e);
                }
            }
        }
    }

    Timer {
        id: sysfsTimer
        interval: root.pollInterval
        running: root.popoutVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshSysfs()
    }

    Process {
        id: gpuProcess
        command: ["sh", root.readerPath, "gpu"]
        running: false
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (!t)
                    return;
                try {
                    root.gpuData = JSON.parse(t);
                } catch (e) {
                    console.warn("acerSense gpu parse:", e);
                }
            }
        }
    }

    Timer {
        id: gpuTimer
        interval: 5000
        running: root.popoutVisible && (root.activeTab === root.gpuTabIndex || root.gpuData.hardwareMux === "discrete")
        repeat: true
        triggeredOnStart: false
        onTriggered: root.refreshGpu()
    }

    Process {
        id: ctlProcess
        property string actionDesc: ""
        property bool isSilent: false
        running: false
        stderr: SplitParser {
            onRead: line => {
                if (line.trim())
                    root.ctlError = line.trim();
            }
        }
        onExited: (code, status) => {
            if (code === 0) {
                if (root.gpuSwitchingTo !== "") {
                    root.gpuRebootRequired = true;
                }
                if (!ctlProcess.isSilent && ctlProcess.actionDesc)
                    ToastService.showInfo(ctlProcess.actionDesc);
                root.refreshSysfs();
                if (root.popoutVisible)
                    root.refreshGpu();
            } else {
                root.gpuPendingRebootMode = "";
                ToastService.showError("Failed: " + ctlProcess.actionDesc, root.ctlError || ("exit " + code));
            }
            root.gpuSwitchingTo = "";

            if (root.pendingCtlArgs) {
                ctlCooldownTimer.restart();
            }
        }
    }

    Process {
        id: pkexecInstallProcess
        running: false
        onExited: (code, status) => {
            if (code === 0) {
                ToastService.showInfo("Helper installed successfully! Controls unlocked.");
                sysfsProcess.running = false;
                root.refreshSysfs();
            } else {
                ToastService.showError("Installation failed or cancelled (code: " + code + ")");
            }
        }
    }

    Process {
        id: clipboardProcess
        running: false
    }

    Process {
        id: screenPickerProcess
        command: ["dms", "color", "pick", "--hex", "-l", "--raw", "--allow-multiple"]
        running: false
        property int targetZone: -1
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (!t)
                    return;
                const clean = t.replace(/[^0-9a-fA-F]/g, "").slice(0, 6).toLowerCase();
                if (clean.length === 6) {
                    if (screenPickerProcess.targetZone === -1) {
                        root.rgbColorHex = clean;
                    } else {
                        root.setZoneColor(clean);
                    }
                    ToastService.showInfo("Eyedropper: #" + clean.toUpperCase());
                }
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                name: root.profileIcon(root.effectiveProfile)
                color: Theme.primary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.pillSecondary()
                visible: text !== ""
                color: Theme.surfaceText
                font.pixelSize: root.pillFontSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            DIcon {
                name: root.profileIcon(root.effectiveProfile)
                color: Theme.primary
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.pillSecondary()
                visible: text !== ""
                color: Theme.surfaceText
                font.pixelSize: root.pillFontSize
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    popoutContent: Component {
        Item {
            id: panel

            property var parentPopout: null
            property var closePopout: null
            property string pendingGpu: ""
            property bool confirmingCalibration: false

            implicitHeight: panelCol.implicitHeight
            width: parent ? parent.width : root.popoutWidth

            onParentPopoutChanged: {
                if (parentPopout)
                    root.popoutVisible = Qt.binding(() => parentPopout.shouldBeVisible);
            }

            Column {
                id: panelCol
                width: panel.width
                spacing: Theme.spacingM

                // Header Card
                Rectangle {
                    width: parent.width
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    implicitHeight: headerCol.implicitHeight + Theme.spacingM * 2

                    Column {
                        id: headerCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Item {
                            width: parent.width
                            height: Math.max(titleText.implicitHeight, powerBadge.implicitHeight)

                            StyledText {
                                id: titleText
                                text: "Acer Sense"
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Power Source Badge (Material Icons only)
                            Row {
                                id: powerBadge
                                spacing: Theme.spacingXS
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter

                                DIcon {
                                    name: BatteryService.isPluggedIn ? "power" : (BatteryService.isCharging ? "battery_charging_full" : "battery_std")
                                    size: Theme.iconSizeSmall
                                    color: BatteryService.isPluggedIn ? Theme.primary : Theme.secondary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: BatteryService.isPluggedIn ? "AC Power" : (Math.round(BatteryService.batteryLevel) + "%")
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Telemetry Row: CPU / GPU Temp
                        Row {
                            width: parent.width
                            spacing: Theme.spacingL

                            Row {
                                spacing: Theme.spacingXS
                                DIcon {
                                    name: "memory"
                                    size: Theme.iconSizeSmall
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "CPU " + (root.telemetry.cpuTemp != null ? root.telemetry.cpuTemp : "—") + "°C"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Row {
                                spacing: Theme.spacingXS
                                DIcon {
                                    name: "auto_awesome_mosaic"
                                    size: Theme.iconSizeSmall
                                    color: Theme.secondary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "GPU " + (root.gpuData.gpuTemp != null ? root.gpuData.gpuTemp : "—") + "°C"
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Turbo Active Badge
                            Rectangle {
                                visible: root.telemetry.hasTurbo && root.telemetry.turboState === 1
                                height: Theme.buttonHeightXS
                                radius: Theme.cornerRadiusSmall
                                color: Theme.error
                                width: turboRow.implicitWidth + Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    id: turboRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS
                                    DIcon {
                                        name: "rocket_launch"
                                        size: Theme.iconSizeSmall
                                        color: Theme.onError
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: "TURBO"
                                        font.pixelSize: Theme.fontSizeXSmall
                                        font.weight: Font.Bold
                                        color: Theme.onError
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }

                        // Fan RPMs
                        Row {
                            width: parent.width
                            spacing: Theme.spacingL

                            StyledText {
                                text: "Fan CPU: " + (root.telemetry.fanCpu != null ? root.telemetry.fanCpu + " rpm" : "—")
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            StyledText {
                                text: "Fan GPU: " + (root.telemetry.fanGpu != null ? root.telemetry.fanGpu + " rpm" : "—")
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                }

                // Notice: linuwu-sense missing
                Rectangle {
                    width: parent.width
                    visible: !root.hasNs
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    border.color: Theme.warning
                    border.width: Theme.outlineWidth
                    implicitHeight: noticeCol.implicitHeight + Theme.spacingM * 2

                    Column {
                        id: noticeCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingXS

                            DIcon {
                                name: "warning"
                                size: Theme.iconSizeSmall
                                color: Theme.warning
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                width: parent.width - Theme.iconSizeSmall - Theme.spacingXS
                                wrapMode: Text.WordWrap
                                text: "linuwu-sense kernel module not detected. Fan, battery, and RGB controls are disabled."
                                color: Theme.warning
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Install the kernel module and reload. See README for instructions (DKMS / AUR / make install)."
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                // Notice: Privileged Helper Required
                Rectangle {
                    width: parent.width
                    visible: root.hasNs && !root.hasHelper
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    border.color: Theme.warning
                    border.width: Theme.outlineWidth
                    implicitHeight: helperNoticeCol.implicitHeight + Theme.spacingM * 2

                    Column {
                        id: helperNoticeCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingXS

                            DIcon {
                                name: "shield"
                                size: Theme.iconSizeSmall
                                color: Theme.warning
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                width: parent.width - Theme.iconSizeSmall - Theme.spacingXS
                                wrapMode: Text.WordWrap
                                text: "Privileged Helper Required"
                                color: Theme.warning
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Controls are currently read-only. Acer Sense requires one-time root permission to control fans, power profiles, battery limiter, and RGB lighting without asking for passwords repeatedly."
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Rectangle {
                            width: parent.width
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHighest
                            implicitHeight: cmdBoxText.implicitHeight + Theme.spacingS * 2

                            StyledText {
                                id: cmdBoxText
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                wrapMode: Text.Wrap
                                text: "sudo sh \"" + root.pluginPath + "/helper/install.sh\""
                                font.family: Theme.monoFontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DButton {
                                width: (parent.width - Theme.spacingS) / 2
                                text: "Authenticate"
                                iconName: "key"
                                backgroundColor: Theme.primary
                                textColor: Theme.onPrimary
                                onClicked: root.runPkexecInstall()
                            }

                            DButton {
                                width: (parent.width - Theme.spacingS) / 2
                                text: "Copy Command"
                                iconName: "content_copy"
                                backgroundColor: Theme.surfaceContainerHighest
                                textColor: Theme.surfaceText
                                onClicked: root.copyInstallCommand()
                            }
                        }
                    }
                }

                // Main Tab Bar
                SegSelector {
                    width: parent.width
                    labels: {
                        var list = ["Overview", "Features"];
                        if (root.telemetry.hasRgb) list.push("Keyboard RGB");
                        list.push("GPU");
                        return list;
                    }
                    current: root.activeTab
                    onPicked: i => root.activeTab = i
                }

                // ==================== TAB 0: OVERVIEW ====================
                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.activeTab === 0

                    // Power Profile Section
                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            text: "Power Profile"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }
                        SegSelector {
                            width: parent.width
                            labels: root.profileLabels
                            current: root.profileValues.indexOf(root.effectiveProfile)
                            onPicked: i => root.setProfile(root.profileValues[i])
                        }
                    }

                    // Fans Section
                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: root.hasNs

                        StyledText {
                            text: "Fan Control"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        SegSelector {
                            width: parent.width
                            labels: ["Auto", "Max", "Custom"]
                            current: root.activeFanMode === "auto" ? 0 : (root.activeFanMode === "max" ? 1 : 2)
                            onPicked: i => {
                                if (i === 0) {
                                    root.customExplicitlyPicked = false;
                                    root.activeFanMode = "auto";
                                    root.setFan("auto");
                                } else if (i === 1) {
                                    root.customExplicitlyPicked = false;
                                    root.activeFanMode = "max";
                                    root.setFan("max");
                                } else if (i === 2) {
                                    root.customExplicitlyPicked = true;
                                    root.activeFanMode = "custom";
                                }
                            }
                        }

                        // Custom Fan Speeds Panel (Sliders & Numeric Steppers)
                        Rectangle {
                            width: parent.width
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh
                            implicitHeight: customFanCol.implicitHeight + Theme.spacingS * 2
                            visible: root.activeFanMode === "custom"

                            Column {
                                id: customFanCol
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                spacing: Theme.spacingS

                                // CPU Fan Control Row
                                Item {
                                    width: parent.width
                                    height: Math.max(cpuHeaderRow.implicitHeight, cpuInputRow.implicitHeight)

                                    Row {
                                        id: cpuHeaderRow
                                        spacing: Theme.spacingXS
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter

                                        DIcon {
                                            name: "memory"
                                            size: Theme.iconSizeSmall
                                            color: Theme.primary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: "CPU Fan: " + root.customCpuFan + "%"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Row {
                                        id: cpuInputRow
                                        spacing: Theme.spacingXS
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter

                                        DButton {
                                            text: "-5"
                                            width: Theme.buttonHeightS
                                            height: Theme.buttonHeightXS
                                            backgroundColor: Theme.surfaceContainerHighest
                                            textColor: Theme.surfaceText
                                            onClicked: root.setCpuFanStep(-5)
                                        }

                                        DTextField {
                                            width: Theme.buttonHeightM + Theme.spacingS
                                            text: String(root.customCpuFan)
                                            onEditingFinished: {
                                                var n = parseInt(text);
                                                if (!isNaN(n)) {
                                                    var snapped = Math.max(20, Math.min(100, Math.round(n / 5) * 5));
                                                    root.customCpuFan = snapped;
                                                    text = String(snapped);
                                                } else {
                                                    text = String(root.customCpuFan);
                                                }
                                            }
                                        }

                                        StyledText {
                                            text: "%"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        DButton {
                                            text: "+5"
                                            width: Theme.buttonHeightS
                                            height: Theme.buttonHeightXS
                                            backgroundColor: Theme.surfaceContainerHighest
                                            textColor: Theme.surfaceText
                                            onClicked: root.setCpuFanStep(5)
                                        }
                                    }
                                }

                                DSlider {
                                    id: cpuSlider
                                    width: parent.width
                                    minimum: 20
                                    maximum: 100
                                    step: 5
                                    value: root.customCpuFan
                                    showValue: false
                                    Binding on value {
                                        when: !cpuSlider.isDragging
                                        value: root.customCpuFan
                                    }
                                    onSliderValueChanged: v => {
                                        var snapped = Math.max(20, Math.min(100, Math.round(v / 5) * 5));
                                        if (snapped !== root.customCpuFan) {
                                            root.customCpuFan = snapped;
                                        }
                                    }
                                }

                                // GPU Fan Control Row
                                Item {
                                    width: parent.width
                                    height: Math.max(gpuHeaderRow.implicitHeight, gpuInputRow.implicitHeight)

                                    Row {
                                        id: gpuHeaderRow
                                        spacing: Theme.spacingXS
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter

                                        DIcon {
                                            name: "auto_awesome_mosaic"
                                            size: Theme.iconSizeSmall
                                            color: Theme.secondary
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        StyledText {
                                            text: "GPU Fan: " + root.customGpuFan + "%"
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Font.Medium
                                            color: Theme.surfaceText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Row {
                                        id: gpuInputRow
                                        spacing: Theme.spacingXS
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter

                                        DButton {
                                            text: "-5"
                                            width: Theme.buttonHeightS
                                            height: Theme.buttonHeightXS
                                            backgroundColor: Theme.surfaceContainerHighest
                                            textColor: Theme.surfaceText
                                            onClicked: root.setGpuFanStep(-5)
                                        }

                                        DTextField {
                                            width: Theme.buttonHeightM + Theme.spacingS
                                            text: String(root.customGpuFan)
                                            onEditingFinished: {
                                                var n = parseInt(text);
                                                if (!isNaN(n)) {
                                                    var snapped = Math.max(20, Math.min(100, Math.round(n / 5) * 5));
                                                    root.customGpuFan = snapped;
                                                    text = String(snapped);
                                                } else {
                                                    text = String(root.customGpuFan);
                                                }
                                            }
                                        }

                                        StyledText {
                                            text: "%"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        DButton {
                                            text: "+5"
                                            width: Theme.buttonHeightS
                                            height: Theme.buttonHeightXS
                                            backgroundColor: Theme.surfaceContainerHighest
                                            textColor: Theme.surfaceText
                                            onClicked: root.setGpuFanStep(5)
                                        }
                                    }
                                }

                                DSlider {
                                    id: gpuSlider
                                    width: parent.width
                                    minimum: 20
                                    maximum: 100
                                    step: 5
                                    value: root.customGpuFan
                                    showValue: false
                                    Binding on value {
                                        when: !gpuSlider.isDragging
                                        value: root.customGpuFan
                                    }
                                    onSliderValueChanged: v => {
                                        var snapped = Math.max(20, Math.min(100, Math.round(v / 5) * 5));
                                        if (snapped !== root.customGpuFan) {
                                            root.customGpuFan = snapped;
                                        }
                                    }
                                }

                                // Quick Speed Presets (sets both fans)
                                DButtonGroup {
                                    width: parent.width
                                    fillWidth: true
                                    checkEnabled: false
                                    size: "small"
                                    model: ["30%", "45%", "60%", "75%", "90%"]
                                    readonly property var presetValues: [30, 45, 60, 75, 90]
                                    currentIndex: (root.customCpuFan === root.customGpuFan) ? presetValues.indexOf(root.customCpuFan) : -1
                                    onSelectionChanged: (index, selected) => {
                                        if (selected && index >= 0 && index < presetValues.length) {
                                            const val = presetValues[index];
                                            root.setBothFans(val);
                                            root.customExplicitlyPicked = true;
                                            root.setFanDual(val, val);
                                        }
                                    }
                                }

                                // Apply Button
                                DButton {
                                    width: parent.width
                                    text: "Apply (" + root.customCpuFan + "% CPU, " + root.customGpuFan + "% GPU)"
                                    iconName: "check"
                                    backgroundColor: Theme.primary
                                    textColor: Theme.onPrimary
                                    onClicked: root.setFanDual(root.customCpuFan, root.customGpuFan)
                                }
                            }
                        }
                    }
                }

                // ==================== TAB 1: FEATURES ====================
                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.activeTab === 1

                    // Battery Health Group
                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: "Battery — " + Math.round(BatteryService.batteryLevel) + "%" + (BatteryService.isCharging ? " · Charging" : (BatteryService.isPluggedIn ? " · Plugged In" : " · Discharging"))
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        DToggle {
                            width: parent.width
                            visible: root.hasNs
                            text: "Limit charge to 80% (Preserve battery lifespan)"
                            checked: root.telemetry.battLimiter === 1
                            onToggled: on => root.setBatteryLimit(on)
                        }

                        DDropdown {
                            width: parent.width
                            visible: root.hasNs
                            text: "USB Power-Off Charging limit"
                            currentValue: (root.telemetry.usbCharging == null || root.telemetry.usbCharging === 0) ? "off" : String(root.telemetry.usbCharging)
                            options: ["off", "10", "20", "30"]
                            onValueChanged: v => root.setUsbCharging(v)
                        }

                        // Battery Calibration Card
                        Rectangle {
                            width: parent.width
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh
                            border.color: root.telemetry.batteryCalibration === 1 ? Theme.primary : "transparent"
                            border.width: Theme.outlineWidth
                            implicitHeight: calibCol.implicitHeight + Theme.spacingS * 2

                            Column {
                                id: calibCol
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                spacing: Theme.spacingXS

                                Row {
                                    width: parent.width
                                    DIcon {
                                        name: "battery_charging_full"
                                        size: Theme.iconSizeSmall
                                        color: root.telemetry.batteryCalibration === 1 ? Theme.primary : Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: "Battery Calibration" + (root.telemetry.batteryCalibration === 1 ? " (Active)" : "")
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: "Fully charges to 100%, drains to 0%, then recharges to calibrate gauge accuracy. Do not disconnect AC power during calibration."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                Row {
                                    spacing: Theme.spacingS
                                    visible: !panel.confirmingCalibration

                                    DButton {
                                        text: root.telemetry.batteryCalibration === 1 ? "Stop Calibration" : "Start Calibration"
                                        iconName: root.telemetry.batteryCalibration === 1 ? "stop" : "play_arrow"
                                        backgroundColor: root.telemetry.batteryCalibration === 1 ? Theme.error : Theme.surfaceContainerHighest
                                        textColor: Theme.surfaceText
                                        onClicked: {
                                            if (root.telemetry.batteryCalibration === 1) {
                                                root.setBatteryCalibration(false);
                                            } else {
                                                panel.confirmingCalibration = true;
                                            }
                                        }
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: Theme.spacingXS
                                    visible: panel.confirmingCalibration

                                    StyledText {
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: "Confirm: Calibration will completely drain your battery before recharging. Keep laptop plugged in!"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.warning
                                        font.weight: Font.Medium
                                    }

                                    Row {
                                        spacing: Theme.spacingS
                                        DButton {
                                            text: "Confirm Start"
                                            backgroundColor: Theme.warning
                                            textColor: Theme.onPrimary
                                            onClicked: {
                                                root.setBatteryCalibration(true);
                                                panel.confirmingCalibration = false;
                                            }
                                        }
                                        DButton {
                                            text: "Cancel"
                                            backgroundColor: Theme.surfaceContainerHighest
                                            textColor: Theme.surfaceText
                                            onClicked: panel.confirmingCalibration = false
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Display & Audio Hardware
                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: root.hasNs

                        StyledText {
                            text: "Display & System"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        DToggle {
                            width: parent.width
                            text: "LCD Overdrive (Minimize latency & ghosting)"
                            checked: root.telemetry.lcdOverride === 1
                            onToggled: on => root.setLcdOverride(on)
                        }

                        DToggle {
                            width: parent.width
                            text: "Boot Animation Sound / Chime"
                            checked: root.telemetry.bootAnimationSound === 1
                            onToggled: on => root.setBootSound(on)
                        }

                        DToggle {
                            width: parent.width
                            text: "Keyboard Backlight Timeout (30s idle)"
                            checked: root.telemetry.backlightTimeout === 1
                            onToggled: on => root.setBacklightTimeout(on)
                        }
                    }
                }

                // ==================== TAB 2: KEYBOARD RGB ====================
                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.activeTab === (root.telemetry.hasRgb ? 2 : -1)

                    SegSelector {
                        width: parent.width
                        labels: ["Lighting Effects", "4-Zone RGB"]
                        current: root.rgbSubTab
                        onPicked: i => {
                            root.rgbSubTab = i;
                            if (i === 0) {
                                root.scheduleRgbEffectApply();
                            } else {
                                root.scheduleRgbZonesApply();
                            }
                        }
                    }

                    // Sub-tab 0: Lighting Effects
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.rgbSubTab === 0

                        Item {
                            width: parent.width
                            height: Math.max(effectModeLabel.implicitHeight, effectModeDrop.implicitHeight)
                            StyledText {
                                id: effectModeLabel
                                text: "Lighting Effect Mode"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            DDropdown {
                                id: effectModeDrop
                                width: Theme.buttonHeightM * 4
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                currentValue: root.rgbModes[root.rgbMode]
                                options: root.rgbModes
                                onValueChanged: v => {
                                    root.rgbMode = root.rgbModes.indexOf(v);
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: Math.max(effectBrightLabel.implicitHeight, effectBrightDrop.implicitHeight)
                            StyledText {
                                id: effectBrightLabel
                                text: "Brightness (%)"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            DDropdown {
                                id: effectBrightDrop
                                width: Theme.buttonHeightM * 3
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                currentValue: String(root.rgbBrightness)
                                options: ["0", "25", "50", "75", "100"]
                                onValueChanged: v => {
                                    root.rgbBrightness = parseInt(v);
                                }
                            }
                        }

                        // Animation Speed: 1 to 9 according to hardware spec (hidden in Static mode)
                        Item {
                            width: parent.width
                            height: Math.max(effectSpeedLabel.implicitHeight, effectSpeedDrop.implicitHeight)
                            visible: root.rgbMode !== 0
                            StyledText {
                                id: effectSpeedLabel
                                text: "Animation Speed (1–9)"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            DDropdown {
                                id: effectSpeedDrop
                                width: Theme.buttonHeightM * 3
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                currentValue: String(Math.max(1, Math.min(9, root.rgbSpeed)))
                                options: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
                                onValueChanged: v => {
                                    root.rgbSpeed = parseInt(v);
                                }
                            }
                        }

                        // Direction: only applicable for Wave (3) and Shifting (4)
                        Item {
                            width: parent.width
                            height: Math.max(effectDirLabel.implicitHeight, effectDirSeg.implicitHeight)
                            visible: root.rgbMode === 3 || root.rgbMode === 4
                            StyledText {
                                id: effectDirLabel
                                text: "Direction"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            SegSelector {
                                id: effectDirSeg
                                width: Theme.buttonHeightM * 4.5
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                labels: ["Right to Left", "Left to Right"]
                                current: root.rgbDirection === 1 ? 0 : 1
                                onPicked: i => {
                                    root.rgbDirection = (i === 0 ? 1 : 2);
                                }
                            }
                        }

                        // Color picker section: visible for Static, Breathing, Shifting, Zoom, Meteor, Twinkling
                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS
                            visible: root.rgbMode !== 2 && root.rgbMode !== 3

                            Item {
                                width: parent.width
                                height: Math.max(Theme.buttonHeightS, hexField.height)

                                StyledText {
                                    text: "Color (#" + root.rgbColorHex.toUpperCase() + ")"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Row {
                                    id: colorPickerRow
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingS

                                    Rectangle {
                                        id: colorCircle
                                        width: Theme.iconSizeMedium
                                        height: Theme.iconSizeMedium
                                        radius: width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: "#" + root.rgbColorHex
                                        border.color: Theme.outlineVariant
                                        border.width: Theme.outlineWidth

                                        DIcon {
                                            name: "colorize"
                                            size: Theme.iconSizeSmall
                                            anchors.centerIn: parent
                                            color: root.zoneTextColor(root.rgbColorHex)
                                            opacity: colorCircleMouseArea.containsMouse ? 0.9 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                        }

                                        MouseArea {
                                            id: colorCircleMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!screenPickerProcess.running) {
                                                    screenPickerProcess.targetZone = -1;
                                                    screenPickerProcess.running = true;
                                                }
                                            }
                                        }
                                    }

                                    DTextField {
                                        id: hexField
                                        width: Theme.buttonHeightM * 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.rgbColorHex.toUpperCase()
                                        onEditingFinished: {
                                            const clean = text.replace(/[^0-9a-fA-F]/g, "").slice(0, 6);
                                            if (clean.length === 6) {
                                                root.rgbColorHex = clean.toLowerCase();
                                            } else {
                                                text = root.rgbColorHex.toUpperCase();
                                            }
                                        }
                                    }

                                    Connections {
                                        target: root
                                        function onRgbColorHexChanged() {
                                            hexField.text = root.rgbColorHex.toUpperCase();
                                        }
                                    }
                                }
                            }

                            // Rainbow Hue spectrum slider bar
                            Rectangle {
                                width: parent.width
                                height: Theme.iconSizeSmall
                                radius: Theme.cornerRadiusSmall
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.00; color: "#ff0000" }
                                    GradientStop { position: 0.17; color: "#ffff00" }
                                    GradientStop { position: 0.33; color: "#00ff00" }
                                    GradientStop { position: 0.50; color: "#00ffff" }
                                    GradientStop { position: 0.67; color: "#0000ff" }
                                    GradientStop { position: 0.83; color: "#ff00aa" }
                                    GradientStop { position: 1.00; color: "#ff0000" }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    function pick(mouse) {
                                        const pos = Math.max(0, Math.min(1, mouse.x / width));
                                        const c = Qt.hsva(pos, 1.0, 1.0, 1.0);
                                        root.rgbColorHex = c.toString().substring(1).toLowerCase();
                                    }
                                    onPressed: mouse => pick(mouse)
                                    onPositionChanged: mouse => { if (pressed) pick(mouse); }
                                }
                            }

                            // Color preset swatches
                            Row {
                                spacing: Theme.spacingXS
                                Repeater {
                                    model: root.presetColors
                                    Rectangle {
                                        width: (parent.parent.width - Theme.spacingXS * 8) / 9
                                        height: Theme.iconSizeMedium
                                        radius: Theme.cornerRadiusSmall
                                        color: "#" + modelData.hex
                                        border.color: root.rgbColorHex === modelData.hex ? Theme.primary : Theme.outlineVariant
                                        border.width: root.rgbColorHex === modelData.hex ? Theme.outlineWidthFocused : Theme.outlineWidth
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.rgbColorHex = modelData.hex;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Sub-tab 1: 4-Zone RGB
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.rgbSubTab === 1

                        StyledText {
                            text: "Select a Zone to customize color:"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        // 4 Zone Visual Representation
                        Row {
                            width: parent.width
                            spacing: Theme.spacingXS

                            Repeater {
                                model: [
                                    { label: "Zone 1", hex: root.zone1Color },
                                    { label: "Zone 2", hex: root.zone2Color },
                                    { label: "Zone 3", hex: root.zone3Color },
                                    { label: "Zone 4", hex: root.zone4Color }
                                ]

                                Rectangle {
                                    width: (parent.width - Theme.spacingXS * 3) / 4
                                    height: Theme.minimumTouchTargetSize
                                    radius: Theme.cornerRadius
                                    color: "#" + modelData.hex
                                    border.color: (root.activeZoneIndex === index + 1 || root.activeZoneIndex === 0) ? Theme.primary : Theme.outlineVariant
                                    border.width: (root.activeZoneIndex === index + 1) ? Theme.outlineWidthFocused : Theme.outlineWidth

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width - Theme.spacingS
                                        height: parent.height - Theme.spacingS
                                        radius: Theme.cornerRadiusSmall
                                        color: root.zoneTextBg(modelData.hex)

                                        Column {
                                            anchors.centerIn: parent
                                            StyledText {
                                                text: modelData.label
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.Bold
                                                color: root.zoneTextColor(modelData.hex)
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }
                                            StyledText {
                                                text: "#" + modelData.hex.toUpperCase()
                                                font.pixelSize: Theme.fontSizeXSmall
                                                font.weight: Font.Medium
                                                color: root.zoneTextColor(modelData.hex)
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activeZoneIndex = (root.activeZoneIndex === index + 1 ? 0 : index + 1)
                                    }
                                }
                            }
                        }

                        // Custom color picker row for active zone
                        Item {
                            width: parent.width
                            height: Math.max(Theme.buttonHeightS, zoneHexField.height)

                            StyledText {
                                text: (root.activeZoneIndex === 0 ? "Target: All Zones" : ("Target: Zone " + root.activeZoneIndex)) + " (#" + root.currentActiveZoneHex().toUpperCase() + ")"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Row {
                                id: zoneColorPickerRow
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

                                Rectangle {
                                    id: zoneColorCircle
                                    width: Theme.iconSizeMedium
                                    height: Theme.iconSizeMedium
                                    radius: width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "#" + root.currentActiveZoneHex()
                                    border.color: Theme.outlineVariant
                                    border.width: Theme.outlineWidth

                                    DIcon {
                                        name: "colorize"
                                        size: Theme.iconSizeSmall
                                        anchors.centerIn: parent
                                        color: root.zoneTextColor(root.currentActiveZoneHex())
                                        opacity: zoneColorCircleMouseArea.containsMouse ? 0.9 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }
                                    }

                                    MouseArea {
                                        id: zoneColorCircleMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!screenPickerProcess.running) {
                                                screenPickerProcess.targetZone = root.activeZoneIndex;
                                                screenPickerProcess.running = true;
                                            }
                                        }
                                    }
                                }

                                DTextField {
                                    id: zoneHexField
                                    width: Theme.buttonHeightM * 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.currentActiveZoneHex().toUpperCase()
                                    onEditingFinished: {
                                        const clean = text.replace(/[^0-9a-fA-F]/g, "").slice(0, 6);
                                        if (clean.length === 6) {
                                            root.setZoneColor(clean);
                                        } else {
                                            text = root.currentActiveZoneHex().toUpperCase();
                                        }
                                    }
                                }

                                Connections {
                                    target: root
                                    function onZone1ColorChanged() { zoneHexField.text = root.currentActiveZoneHex().toUpperCase(); }
                                    function onZone2ColorChanged() { zoneHexField.text = root.currentActiveZoneHex().toUpperCase(); }
                                    function onZone3ColorChanged() { zoneHexField.text = root.currentActiveZoneHex().toUpperCase(); }
                                    function onZone4ColorChanged() { zoneHexField.text = root.currentActiveZoneHex().toUpperCase(); }
                                    function onActiveZoneIndexChanged() { zoneHexField.text = root.currentActiveZoneHex().toUpperCase(); }
                                }
                            }
                        }

                        // Rainbow Hue spectrum slider bar for zones
                        Rectangle {
                            width: parent.width
                            height: Theme.iconSizeSmall
                            radius: Theme.cornerRadiusSmall
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.00; color: "#ff0000" }
                                GradientStop { position: 0.17; color: "#ffff00" }
                                GradientStop { position: 0.33; color: "#00ff00" }
                                GradientStop { position: 0.50; color: "#00ffff" }
                                GradientStop { position: 0.67; color: "#0000ff" }
                                GradientStop { position: 0.83; color: "#ff00aa" }
                                GradientStop { position: 1.00; color: "#ff0000" }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                function pick(mouse) {
                                    const pos = Math.max(0, Math.min(1, mouse.x / width));
                                    const c = Qt.hsva(pos, 1.0, 1.0, 1.0);
                                    root.setZoneColor(c.toString().substring(1).toLowerCase());
                                }
                                onPressed: mouse => pick(mouse)
                                onPositionChanged: mouse => { if (pressed) pick(mouse); }
                            }
                        }

                        // Color swatches for zones
                        Row {
                            spacing: Theme.spacingXS
                            Repeater {
                                model: root.presetColors
                                Rectangle {
                                    width: (parent.parent.width - Theme.spacingXS * 8) / 9
                                    height: Theme.iconSizeMedium
                                    radius: Theme.cornerRadiusSmall
                                    color: "#" + modelData.hex
                                    border.color: root.currentActiveZoneHex() === modelData.hex ? Theme.primary : Theme.outlineVariant
                                    border.width: root.currentActiveZoneHex() === modelData.hex ? Theme.outlineWidthFocused : Theme.outlineWidth

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setZoneColor(modelData.hex)
                                    }
                                }
                            }
                        }

                        // Quick Themes
                        StyledText {
                            text: "Quick Themes"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        Row {
                            spacing: Theme.spacingXS
                            DButton {
                                text: "Predator Cyan"
                                backgroundColor: Theme.surfaceContainerHighest
                                textColor: Theme.surfaceText
                                onClicked: {
                                    root.zone1Color = "00aec7";
                                    root.zone2Color = "00aec7";
                                    root.zone3Color = "00aec7";
                                    root.zone4Color = "00aec7";
                                }
                            }
                            DButton {
                                text: "Rainbow"
                                backgroundColor: Theme.surfaceContainerHighest
                                textColor: Theme.surfaceText
                                onClicked: {
                                    root.zone1Color = "ff3333";
                                    root.zone2Color = "ff8800";
                                    root.zone3Color = "33ff57";
                                    root.zone4Color = "aa33ff";
                                }
                            }
                            DButton {
                                text: "Cyberpunk"
                                backgroundColor: Theme.surfaceContainerHighest
                                textColor: Theme.surfaceText
                                onClicked: {
                                    root.zone1Color = "00ffff";
                                    root.zone2Color = "ff00aa";
                                    root.zone3Color = "00ffff";
                                    root.zone4Color = "ff00aa";
                                }
                            }
                        }

                        Item {
                            width: parent.width
                            height: Math.max(zoneBrightLabel.implicitHeight, zoneBrightDrop.implicitHeight)
                            StyledText {
                                id: zoneBrightLabel
                                text: "Brightness (%)"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            DDropdown {
                                id: zoneBrightDrop
                                width: Theme.buttonHeightM * 3
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                currentValue: String(root.zoneBrightness)
                                options: ["0", "25", "50", "75", "100"]
                                onValueChanged: v => {
                                    root.zoneBrightness = parseInt(v);
                                }
                            }
                        }
                    }

                    // Notice for 2025+ models with ENEK5130
                    Rectangle {
                        width: parent.width
                        visible: root.telemetry.hasEnek5130
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.color: Theme.primary
                        border.width: Theme.outlineWidth
                        implicitHeight: enekCol.implicitHeight + Theme.spacingS * 2

                        Column {
                            id: enekCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingXS

                            Row {
                                spacing: Theme.spacingXS
                                DIcon {
                                    name: "info"
                                    size: Theme.iconSizeSmall
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "ENEK5130 Controller Detected"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                }
                            }
                            StyledText {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: "2025+ Acer laptops control RGB over i2c-HID rather than WMI. If LEDs do not update, use the standalone 'kbrgb' hidraw tool."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }

                // ==================== TAB 3: GPU ====================
                Column {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.activeTab === root.gpuTabIndex

                    // GPU Telemetry Card
                    Rectangle {
                        width: parent.width
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        implicitHeight: gpuTelemetryCol.implicitHeight + Theme.spacingM * 2

                        Column {
                            id: gpuTelemetryCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            Row {
                                width: parent.width
                                spacing: Theme.spacingXS

                                DIcon {
                                    name: "memory"
                                    size: Theme.iconSizeSmall
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: "Discrete NVIDIA GPU"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: Theme.spacingM

                                Column {
                                    spacing: Theme.spacingXXS
                                    StyledText {
                                        text: "Temperature"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                    StyledText {
                                        text: root.gpuData.gpuTemp != null ? (root.gpuData.gpuTemp + "°C") : "—"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                    }
                                }

                                Column {
                                    spacing: Theme.spacingXXS
                                    StyledText {
                                        text: "Utilization"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                    StyledText {
                                        text: root.gpuData.gpuUtil != null ? (root.gpuData.gpuUtil + "%") : "—"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                    }
                                }

                                Column {
                                    spacing: Theme.spacingXXS
                                    StyledText {
                                        text: "Power Draw"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                    StyledText {
                                        text: root.gpuData.gpuPower != null ? (root.gpuData.gpuPower + " W") : "—"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                    }
                                }
                            }
                        }
                    }

                    // Hardware MUX: Discrete GPU Direct Mode (when iGPU is disabled in BIOS / PredatorSense)
                    Rectangle {
                        width: parent.width
                        visible: root.gpuData.hardwareMux === "discrete"
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.color: Theme.outlineVariant
                        border.width: Theme.outlineWidth
                        implicitHeight: muxCol.implicitHeight + Theme.spacingM * 2

                        Column {
                            id: muxCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            Row {
                                width: parent.width
                                spacing: Theme.spacingS

                                DIcon {
                                    name: "developer_board"
                                    size: Theme.iconSizeSmall
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: "Hardware MUX: Discrete GPU Only"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: "The Intel/AMD integrated GPU is disabled in your laptop's BIOS or PredatorSense (Hardware MUX Direct Connect). Your display is wired directly to your NVIDIA GPU for peak gaming performance and lowest latency.\n\nSoftware GPU switching (Hybrid / Integrated) is unavailable while the iGPU is powered off at the hardware level. To enable Hybrid or Integrated graphics, change Display Mode to \"Dynamic / Optimus\" in your BIOS settings or PredatorSense."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            Rectangle {
                                height: Theme.buttonHeightXS
                                radius: Theme.cornerRadiusSmall
                                color: Theme.primaryContainer
                                implicitWidth: activeLabel.implicitWidth + Theme.spacingM * 2

                                StyledText {
                                    id: activeLabel
                                    anchors.centerIn: parent
                                    text: "Active: Direct NVIDIA dGPU"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.onPrimaryContainer
                                }
                            }
                        }
                    }

                    // EnvyControl GPU Mode Switcher (only when dual-GPU / Optimus is active and envycontrol is installed)
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.gpuData.hardwareMux !== "discrete" && root.gpuData.hasEnvyControl === true

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: "GPU Graphics Mode (Current: " + (root.gpuData.gpuMode || "unknown") + ")"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        // Switching progress card
                        Rectangle {
                            width: parent.width
                            visible: root.gpuSwitchingTo !== ""
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHighest
                            border.color: Theme.primary
                            border.width: Theme.outlineWidth
                            implicitHeight: switchingCol.implicitHeight + Theme.spacingM * 2

                            Column {
                                id: switchingCol
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingXS

                                Row {
                                    spacing: Theme.spacingS
                                    DIcon {
                                        name: "sync"
                                        size: Theme.iconSizeSmall
                                        color: Theme.primary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: "Switching to '" + root.gpuSwitchingTo + "'..."
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                        color: Theme.surfaceText
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                StyledText {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: "EnvyControl is rebuilding kernel initramfs. Please wait (~10-15s)..."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }

                        // Reboot Required Card
                        Rectangle {
                            width: parent.width
                            visible: root.gpuRebootRequired && root.gpuSwitchingTo === ""
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh
                            border.color: Theme.warning
                            border.width: Theme.outlineWidth
                            implicitHeight: rebootCol.implicitHeight + Theme.spacingM * 2

                            Column {
                                id: rebootCol
                                anchors.fill: parent
                                anchors.margins: Theme.spacingM
                                spacing: Theme.spacingS

                                Row {
                                    spacing: Theme.spacingS
                                    DIcon {
                                        name: "restart_alt"
                                        size: Theme.iconSizeSmall
                                        color: Theme.warning
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: "Reboot Required"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Bold
                                        color: Theme.warning
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                StyledText {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: "Graphics mode switch to '" + (root.gpuPendingRebootMode || root.gpuData.gpuMode || "selected mode") + "' configured. Reboot your computer to apply the change."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                }
                                Row {
                                    spacing: Theme.spacingS
                                    DButton {
                                        text: "Reboot Now"
                                        iconName: "restart_alt"
                                        backgroundColor: Theme.error
                                        textColor: Theme.onError
                                        onClicked: SessionService.reboot()
                                    }
                                    DButton {
                                        text: "Dismiss"
                                        backgroundColor: Theme.surfaceContainerHighest
                                        textColor: Theme.surfaceText
                                        onClicked: {
                                            root.gpuRebootRequired = false;
                                            root.gpuPendingRebootMode = "";
                                        }
                                    }
                                }
                            }
                        }

                        SegSelector {
                            width: parent.width
                            visible: panel.pendingGpu === "" && root.gpuSwitchingTo === ""
                            labels: ["hybrid", "integrated", "nvidia"]
                            current: ["hybrid", "integrated", "nvidia"].indexOf(root.gpuData.gpuMode)
                            onPicked: i => {
                                const m = ["hybrid", "integrated", "nvidia"][i];
                                if (m !== root.gpuData.gpuMode)
                                    panel.pendingGpu = m;
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: Theme.spacingXS
                            visible: panel.pendingGpu !== "" && root.gpuSwitchingTo === ""

                            StyledText {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: "Switch GPU to '" + panel.pendingGpu + "'? EnvyControl will rebuild the kernel initramfs (~10s). You will need to reboot to activate the new graphics mode."
                                color: Theme.warning
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            Row {
                                spacing: Theme.spacingS
                                DButton {
                                    text: "Confirm & Switch"
                                    backgroundColor: Theme.error
                                    textColor: Theme.onError
                                    onClicked: {
                                        root.setGpu(panel.pendingGpu);
                                        panel.pendingGpu = "";
                                    }
                                }
                                DButton {
                                    text: "Cancel"
                                    backgroundColor: Theme.surfaceContainerHigh
                                    textColor: Theme.surfaceText
                                    onClicked: panel.pendingGpu = ""
                                }
                            }
                        }
                    }

                    // Notice if envycontrol is missing (only when Optimus is active)
                    Rectangle {
                        width: parent.width
                        visible: root.gpuData.hardwareMux !== "discrete" && !root.gpuData.hasEnvyControl
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.color: Theme.warning
                        border.width: Theme.outlineWidth
                        implicitHeight: envyCol.implicitHeight + Theme.spacingM * 2

                        Column {
                            id: envyCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            Row {
                                spacing: Theme.spacingXS
                                DIcon {
                                    name: "info"
                                    size: Theme.iconSizeSmall
                                    color: Theme.warning
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "GPU Mode Switching (EnvyControl)"
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                text: "To switch between Hybrid, Integrated, and Dedicated NVIDIA graphics modes, 'envycontrol' is required. Install it using your distribution's package manager:"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            Rectangle {
                                width: parent.width
                                height: Theme.buttonHeightS
                                radius: Theme.cornerRadiusSmall
                                color: Theme.surfaceContainerLowest
                                border.color: Theme.outlineVariant
                                border.width: Theme.outlineWidth

                                StyledText {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.gpuData.envyInstallCmd || "sudo pip install envycontrol"
                                    font.family: Theme.monoFontFamily
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                }
                            }

                            DButton {
                                width: parent.width
                                text: "Copy Install Command"
                                iconName: "content_copy"
                                backgroundColor: Theme.surfaceContainerHighest
                                textColor: Theme.surfaceText
                                onClicked: root.copyEnvyInstallCommand()
                            }
                        }
                    }
                }
            }
        }
    }
}
