.pragma library

// English keys are the default. Add overrides per language code (pt, es).
// tr() returns the English key when no translation exists.
var strings = {
    // Widget — sections & labels
    "Power profile":
        { pt: "Perfil de energia", es: "Perfil de energía" },
    "Power Saver":
        { pt: "Economia", es: "Ahorro" },
    "Quiet":
        { pt: "Silencioso", es: "Silencioso" },
    "Balanced":
        { pt: "Balanceado", es: "Balanceado" },
    "Performance":
        { pt: "Desempenho", es: "Rendimiento" },
    "Cool":
        { pt: "Fresco", es: "Fresco" },
    "Turbo":
        { pt: "Turbo", es: "Turbo" },
    "Fans":
        { pt: "Ventoinhas", es: "Ventiladores" },
    "Battery":
        { pt: "Bateria", es: "Batería" },
    "cycles":
        { pt: "ciclos", es: "ciclos" },
    "Limit charge to 80%":
        { pt: "Limitar carga a 80%", es: "Limitar carga al 80%" },
    "USB charging":
        { pt: "Carregar USB", es: "Carga USB" },
    "mode":
        { pt: "modo", es: "modo" },
    "usage":
        { pt: "uso", es: "uso" },
    "Confirm":
        { pt: "Confirmar", es: "Confirmar" },
    "Cancel":
        { pt: "Cancelar", es: "Cancelar" },
    "Switch GPU to":
        { pt: "Trocar GPU para", es: "Cambiar GPU a" },
    "Save your work — this ends the graphics session and requires a reboot.":
        { pt: "Salve seu trabalho — isso encerra a sessão gráfica e exige reiniciar.",
          es: "Guarde su trabajo — esto cierra la sesión gráfica y requiere reiniciar." },
    // linuwu-sense missing notice
    "linuwu-sense not detected — fan and battery controls are disabled.":
        { pt: "linuwu-sense não detectado — controles de ventoinha e bateria desativados.",
          es: "linuwu-sense no detectado — controles de ventilador y batería desactivados." },
    "Install the kernel module and restart DMS. On Arch / CachyOS:":
        { pt: "Instale o módulo de kernel e reinicie o DMS. No Arch / CachyOS:",
          es: "Instala el módulo de kernel y reinicia DMS. En Arch / CachyOS:" },
    "Other distros:":
        { pt: "Outras distros:", es: "Otras distros:" },
    // Battery status (from sysfs, in English)
    "Charging":
        { pt: "Carregando", es: "Cargando" },
    "Not charging":
        { pt: "Não carregando", es: "No cargando" },
    "Discharging":
        { pt: "Descarregando", es: "Descargando" },
    "Full":
        { pt: "Cheia", es: "Completa" },
    // Settings
    "Language":
        { pt: "Idioma", es: "Idioma" },
    "Pill content (next to the icon)":
        { pt: "Conteúdo da pill (ao lado do ícone)", es: "Contenido junto al icono" },
    "Nothing":
        { pt: "Nada", es: "Nada" },
    "CPU temp":
        { pt: "Temp CPU", es: "Temp CPU" },
    "GPU temp is intentionally left off the pill: it would query the dGPU continuously and wake it from sleep.":
        { pt: "A temp da GPU fica fora da pill de propósito: leria a dGPU continuamente e a acordaria do sono.",
          es: "La temp de la GPU se omite a propósito: consultaría la dGPU continuamente y la despertaría." },
    "Refresh interval (s)":
        { pt: "Intervalo de atualização (s)", es: "Intervalo de actualización (s)" },
}

function tr(key, lang) {
    if (!lang || lang === "en" || !strings[key] || !strings[key][lang])
        return key;
    return strings[key][lang];
}
