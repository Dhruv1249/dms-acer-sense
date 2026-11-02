import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

FocusScope {
    id: root

    property var pluginService: null

    readonly property var pillKeys: ["none", "cpuTemp", "fanRpm"]
    property string pillContent: "cpuTemp"
    property int pollInterval: 4
    property bool helperInstalled: false

    readonly property string pluginPath: PluginService.getPluginPath("acerSense") || (PluginService.pluginDirectory + "/acerSense")

    implicitHeight: col.implicitHeight + Theme.spacingM * 2
    height: implicitHeight

    function load(key, def) {
        return pluginService ? pluginService.loadPluginData("acerSense", key, def) : def;
    }
    function save(key, val) {
        if (pluginService)
            pluginService.savePluginData("acerSense", key, val);
    }

    function checkHelper() {
        helperCheckProcess.running = true;
    }

    function copyInstallCommand() {
        const cmd = "sudo sh \"" + root.pluginPath + "/helper/install.sh\"";
        clipboardProcess.command = ["sh", "-c", "printf '%s' \"$1\" | (wl-copy 2>/dev/null || dms clipboard copy 2>/dev/null || xclip -selection clipboard 2>/dev/null)", "--", cmd];
        clipboardProcess.running = true;
        ToastService.showInfo("Install command copied to clipboard!");
    }

    function runPkexecInstall() {
        if (pkexecProcess.running)
            return;
        pkexecProcess.command = ["pkexec", "sh", root.pluginPath + "/helper/install.sh"];
        pkexecProcess.running = true;
    }

    Process {
        id: helperCheckProcess
        command: ["sudo", "-n", "/usr/local/bin/acer-ctl", "ping"]
        running: false
        onExited: (code, status) => {
            root.helperInstalled = (code === 0);
        }
    }

    Process {
        id: pkexecProcess
        running: false
        onExited: (code, status) => {
            if (code === 0) {
                ToastService.showInfo("Helper installed successfully! Privileges configured.");
                root.checkHelper();
            } else {
                ToastService.showError("Installation failed or cancelled (code: " + code + ")");
            }
        }
    }

    Process {
        id: clipboardProcess
        running: false
    }

    Component.onCompleted: {
        pillContent = load("pillContent", "cpuTemp");
        pollInterval = load("pollInterval", 4);
        checkHelper();
    }

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingM

        StyledText {
            text: "Acer Sense Settings"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        // Helper Status & Setup Card
        Rectangle {
            width: parent.width
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.color: root.helperInstalled ? Theme.primary : Theme.warning
            border.width: 1
            implicitHeight: helperCardCol.implicitHeight + Theme.spacingM * 2

            Column {
                id: helperCardCol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                Row {
                    width: parent.width
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: root.helperInstalled ? "check_circle" : "warning"
                        size: Theme.iconSizeSmall
                        color: root.helperInstalled ? Theme.primary : Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.helperInstalled ? "Privileged Helper Active" : "Privileged Helper Required"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                StyledText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.helperInstalled
                        ? "The helper (/usr/local/bin/acer-ctl) is properly installed with sudo permissions. Fan, battery, and RGB controls are active."
                        : "Acer Sense needs elevated permissions to control fans, power profiles, battery limiter, and RGB lighting without password prompts."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
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
                        font.family: "monospace"
                        font.pixelSize: 11
                        color: Theme.surfaceText
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DankButton {
                        width: (parent.width - Theme.spacingS) / 2
                        text: "Authenticate"
                        iconName: "key"
                        backgroundColor: Theme.primary
                        textColor: Theme.onPrimary
                        onClicked: root.runPkexecInstall()
                    }

                    DankButton {
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

        // Pill content configuration
        Column {
            width: parent.width
            spacing: Theme.spacingXS

            StyledText {
                text: "Pill content (next to the icon)"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }
            DankButtonGroup {
                width: parent.width
                model: ["Nothing", "CPU temp", "Fan RPM"]
                currentIndex: root.pillKeys.indexOf(root.pillContent)
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    root.pillContent = root.pillKeys[index];
                    root.save("pillContent", root.pillContent);
                }
            }
            StyledText {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "GPU temperature is intentionally omitted from the bar pill to prevent waking the discrete GPU continuously."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }


        // Poll Interval
        Column {
            width: parent.width
            spacing: Theme.spacingXS

            StyledText {
                text: "Telemetry Refresh Interval (seconds)"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }
            DankDropdown {
                width: parent.width
                currentValue: String(root.pollInterval)
                options: ["2", "4", "6", "10"]
                onValueChanged: v => {
                    root.pollInterval = parseInt(v);
                    root.save("pollInterval", root.pollInterval);
                }
            }
        }

        // Credits & Version
        Column {
            width: parent.width
            spacing: 2

            StyledText {
                text: "Acer Sense v2.0.0 — Fork by Dhruv1249"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
            }
            StyledText {
                text: "Original plugin by raphamzn · Hardware controls powered by Linuwu-Sense by 0x7375646F"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
