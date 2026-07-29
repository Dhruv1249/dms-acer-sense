import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "translations.js" as Tr

PluginComponent {
    id: root

    property var telemetry: ({})
    property var gpuData: ({})
    property bool popoutVisible: false
    property string ctlError: ""

    readonly property string lang: pluginData.language || "en"
    readonly property string pillContent: pluginData.pillContent || "cpuTemp"
    readonly property int pollInterval: (pluginData.pollInterval || 4) * 1000
    readonly property int fanQuiet: pluginData.fanQuiet || 40
    // false only once a read confirms the sysfs node is absent (stays optimistic before first read)
    readonly property bool hasNs: root.telemetry.hasNs !== false

    // Ask the service where we were installed instead of assuming the folder is named after the
    // plugin id — a differently-named directory (a dev symlink, a manual clone) used to break every
    // read with no hint as to why. getPluginPath exists since DMS 1.4.0; the old path is the
    // fallback for the window before the manifest is registered.
    readonly property string pluginPath: PluginService.getPluginPath(root.pluginId) || (PluginService.pluginDirectory + "/acerSense")
    readonly property string readerPath: root.pluginPath + "/acer-read"

    // Bar pill text must follow the bar's own sizing rules (thickness, font scale and the
    // "Maximize Widget Text" toggle) so it matches the built-in widgets. On DMS < 1.5 the
    // third argument is simply ignored, which is the pre-toggle behaviour.
    readonly property int pillFontSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)

    // Fallback shown before the first read (or if the kernel doesn't expose the choices file).
    readonly property var profileFallback: ["low-power", "quiet", "balanced", "balanced-performance"]
    // Built from /sys/firmware/acpi/platform_profile_choices so only kernel-valid levels ever show.
    readonly property var profileValues: root.parseProfileChoices(root.telemetry.profileChoices)
    readonly property var profileLabels: root.profileValues.map(p => root.profileLabel(p))

    popoutWidth: 400

    component SegSelector: Row {
        id: seg

        property var labels: []
        property int current: -1
        signal picked(int index)

        spacing: Theme.spacingXS

        Repeater {
            model: seg.labels
            Rectangle {
                width: (seg.width - seg.spacing * (seg.labels.length - 1)) / Math.max(1, seg.labels.length)
                height: 36
                radius: Theme.cornerRadius
                color: index === seg.current ? Theme.primary : (cellArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingXS * 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    text: modelData
                    color: index === seg.current ? Theme.onPrimary : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }

                MouseArea {
                    id: cellArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.picked(index)
                }
            }
        }
    }

    function tr(k) {
        return Tr.tr(k, root.lang);
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
            return tr("Power Saver");
        case "cool":
            return tr("Cool");
        case "quiet":
            return tr("Quiet");
        case "balanced":
            return tr("Balanced");
        case "balanced-performance":
            return tr("Performance");
        case "performance":
            return tr("Turbo");
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
            return "rocket_launch";
        }
        return "tune";
    }

    function fanPresetIndex(s) {
        if (!s)
            return -1;
        if (s === "0,0")
            return 0;
        if (s === "100,100")
            return 2;
        return 1;
    }

    function pillSecondary() {
        if (root.pillContent === "cpuTemp")
            return (root.telemetry.cpuTemp != null) ? (root.telemetry.cpuTemp + "°") : "";
        if (root.pillContent === "fanRpm")
            return (root.telemetry.fanCpu != null) ? (root.telemetry.fanCpu + " rpm") : "";
        return "";
    }

    function runCtl(args, desc) {
        if (ctlProcess.running)
            return;
        root.ctlError = "";
        ctlProcess.actionDesc = desc;
        ctlProcess.command = ["sudo", "-n", "/usr/local/bin/acer-ctl"].concat(args);
        ctlProcess.running = true;
    }
    // platform_profile (Acer firmware) and power-profiles-daemon (CPU EPP) are two independent
    // knobs. The widget is the single control: picking a level drives BOTH so they never diverge.
    function ppdForProfile(p) {
        switch (p) {
        case "low-power":
        case "quiet":
            return "power-saver";
        case "cool":
        case "balanced":
            return "balanced";
        case "balanced-performance":
        case "performance":
            return "performance";
        }
        return "";
    }
    function setProfile(p) {
        runCtl(["profile", p], "Profile: " + p);
        const ppd = root.ppdForProfile(p);
        if (ppd && !ppdProcess.running) {
            ppdProcess.command = ["/usr/bin/powerprofilesctl", "set", ppd];
            ppdProcess.running = true;
        }
    }
    function setFan(preset) {
        if (preset === "quiet") {
            runCtl(["fan", String(root.fanQuiet)], "Fan: quiet " + root.fanQuiet + "%");
            return;
        }
        runCtl(["fan", preset], "Fan: " + preset);
    }
    function setBatteryLimit(on) {
        runCtl(["battery-limit", on ? "on" : "off"], "Battery limit: " + (on ? "80%" : "off"));
    }
    function setUsbCharging(v) {
        runCtl(["usb-charging", v], "USB charging: " + v);
    }
    function setGpu(mode) {
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
                    root.telemetry = JSON.parse(t);
                } catch (e) {
                    console.warn("acerSense sysfs parse:", e);
                }
            }
        }
    }

    Timer {
        interval: root.pollInterval
        running: true
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
        interval: 2000
        running: root.popoutVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshGpu()
    }

    Process {
        id: ctlProcess
        property string actionDesc: ""
        running: false
        stderr: SplitParser {
            onRead: line => {
                if (line.trim())
                    root.ctlError = line.trim();
            }
        }
        onExited: (code, status) => {
            if (code === 0) {
                ToastService.showInfo(ctlProcess.actionDesc);
                root.refreshSysfs();
                if (root.popoutVisible)
                    root.refreshGpu();
            } else {
                ToastService.showError("Failed: " + ctlProcess.actionDesc, root.ctlError || ("exit " + code));
            }
        }
    }

    // Mirrors the chosen profile onto power-profiles-daemon (CPU EPP). set-profile is permitted
    // for the active session, so no sudo is needed here.
    Process {
        id: ppdProcess
        running: false
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.profileIcon(root.telemetry.profile)
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
            spacing: 1

            DankIcon {
                name: root.profileIcon(root.telemetry.profile)
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

                        StyledText {
                            text: "Acer Nitro / Predator"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingL

                            Row {
                                spacing: Theme.spacingXS
                                DankIcon {
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
                                DankIcon {
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
                        }

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

                Rectangle {
                    width: parent.width
                    visible: !root.hasNs
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    border.color: Theme.warning
                    border.width: 1
                    implicitHeight: noticeCol.implicitHeight + Theme.spacingM * 2

                    Column {
                        id: noticeCol
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Row {
                            width: parent.width
                            spacing: Theme.spacingXS

                            DankIcon {
                                name: "warning"
                                size: Theme.iconSizeSmall
                                color: Theme.warning
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                width: parent.width - Theme.iconSizeSmall - Theme.spacingXS
                                wrapMode: Text.WordWrap
                                text: root.tr("linuwu-sense not detected — fan and battery controls are disabled.")
                                color: Theme.warning
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: root.tr("Install the kernel module and restart DMS. On Arch / CachyOS:")
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Rectangle {
                            width: parent.width
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHighest
                            implicitHeight: cmdText.implicitHeight + Theme.spacingS * 2

                            StyledText {
                                id: cmdText
                                anchors.fill: parent
                                anchors.margins: Theme.spacingS
                                wrapMode: Text.WrapAnywhere
                                text: "yay -S linuwu-sense-dkms-git"
                                font.family: "monospace"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }
                        }

                        StyledText {
                            width: parent.width
                            wrapMode: Text.WrapAnywhere
                            text: root.tr("Other distros:") + " github.com/0x7375646F/Linuwu-Sense"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: root.tr("Power profile")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    SegSelector {
                        width: parent.width
                        labels: root.profileLabels
                        current: root.profileValues.indexOf(root.telemetry.profile)
                        onPicked: i => root.setProfile(root.profileValues[i])
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.hasNs

                    StyledText {
                        text: root.tr("Fans")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    SegSelector {
                        width: parent.width
                        labels: ["Auto", root.tr("Quiet") + " " + root.fanQuiet + "%", "Max"]
                        current: root.fanPresetIndex(root.telemetry.fanSpeed)
                        onPicked: i => {
                            if (i === 0)
                                root.setFan("auto");
                            else if (i === 1)
                                root.setFan("quiet");
                            else
                                root.setFan("max");
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.tr("Battery") + " — " + (root.telemetry.battPct != null ? root.telemetry.battPct + "%" : "—") + (root.telemetry.battStatus ? " · " + root.tr(root.telemetry.battStatus) : "") + (root.telemetry.battCycles != null ? " · " + root.telemetry.battCycles + " " + root.tr("cycles") : "")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }
                    DankToggle {
                        width: parent.width
                        visible: root.hasNs
                        text: root.tr("Limit charge to 80%")
                        checked: root.telemetry.battLimiter === 1
                        onToggled: on => root.setBatteryLimit(on)
                    }
                    DankDropdown {
                        width: parent.width
                        visible: root.hasNs
                        text: root.tr("USB charging")
                        currentValue: (root.telemetry.usbCharging == null || root.telemetry.usbCharging === 0) ? "off" : String(root.telemetry.usbCharging)
                        options: ["off", "10", "20", "30"]
                        onValueChanged: v => root.setUsbCharging(v)
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.gpuData.gpuMode != null

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: "GPU — " + root.tr("mode") + " " + (root.gpuData.gpuMode || "—") + (root.gpuData.gpuUtil != null ? " · " + root.gpuData.gpuUtil + "% " + root.tr("usage") : "")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    SegSelector {
                        width: parent.width
                        visible: panel.pendingGpu === ""
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
                        visible: panel.pendingGpu !== ""

                        StyledText {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: root.tr("Switch GPU to") + " '" + panel.pendingGpu + "' — " + root.tr("Save your work — this ends the graphics session and requires a reboot.")
                            color: Theme.warning
                            font.pixelSize: Theme.fontSizeSmall
                        }
                        Row {
                            spacing: Theme.spacingS
                            DankButton {
                                text: root.tr("Confirm")
                                backgroundColor: Theme.error
                                textColor: "#FFFFFF"
                                onClicked: {
                                    root.setGpu(panel.pendingGpu);
                                    panel.pendingGpu = "";
                                }
                            }
                            DankButton {
                                text: root.tr("Cancel")
                                backgroundColor: Theme.surfaceContainerHigh
                                textColor: Theme.surfaceText
                                onClicked: panel.pendingGpu = ""
                            }
                        }
                    }
                }
            }
        }
    }
}
