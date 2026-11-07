#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true
DetectHiddenWindows true
SetWinDelay -1
SetControlDelay -1
; Keep the keyboard hook: the `$`-prefixed and HotIfWinActive context-sensitive
; bindings below rely on it, and the config reload path can swap bindings at
; runtime. Removing it is a behaviour change, not an optimisation.
InstallKeybdHook true, true
A_MenuMaskKey := "vkE8"

; -------------------------------------------------------------
; Global Configuration & State
; -------------------------------------------------------------
global g_ConfigFile         := ""
global g_BorderGap          := 2
global g_BorderColor        := "38bdf8"
global g_VisorHeightPercent := 0.40
global g_MultiMonitorMode   := "isolated"
global g_ShowHelpOnStart    := "tip"
global g_FirstRun           := false
global g_StartingDirectory  := "~"
global g_AppVersion         := "unknown"
global g_SelfTest           := false
global g_SelfTestConfig     := ""

; Terminal executable resolution (never launch a bare "alacritty.exe")
global g_AlacrittyExe            := ""   ; resolved executable (session cache)
global g_AlacrittyConfiguredPath := ""   ; optional [General] AlacrittyPath

; Layout settings
global g_TileLayout         := "bottom"
global g_TwoPaneLayout      := "side-by-side-visor"
global g_SinglePaneSide     := ""

; Hotkey mappings (defaults if config is absent or partial)
global g_KeyToggleVisor     := "#sc029"
global g_KeySplit           := "!Enter"
global g_KeyClose           := "!w"
global g_KeyRetile          := "!r"
global g_KeyCycleLayout     := "!l"
global g_KeyFocusLeft       := "!Left"
global g_KeyFocusRight      := "!Right"
global g_KeyFocusUp         := "!Up"
global g_KeyFocusDown       := "!Down"
global g_KeySwapLeft        := "!+Left"
global g_KeySwapRight       := "!+Right"
global g_KeySwapUp          := "!+Up"
global g_KeySwapDown        := "!+Down"
global g_KeyRotate          := "!+Space"
global g_KeyMoveVisorLeft   := "!^Left"
global g_KeyMoveVisorRight  := "!^Right"
global g_KeyReload          := "!^r"

; Window & Divider trackers
; Hopping mode legacy single-pool tracker
global g_AlacrittyOrder     := []
global g_Dividers           := []

; Isolated per-monitor trackers
global g_MonitorWindows        := Map()  ; monId (int) -> Array of HWNDs
global g_MonitorDividers       := Map()  ; monId (int) -> Array of Gui objects
global g_MonitorTileLayout     := Map()  ; monId (int) -> string ("bottom", "top", "left", "right")
global g_MonitorTwoPaneLayout  := Map()  ; monId (int) -> string ("side-by-side-visor", ...)
global g_MonitorSinglePaneSide := Map()  ; monId (int) -> string ("", "left", "right")

; Reentrancy lock preventing watchdog from firing during active layout transitions
global g_LayoutLock            := 0

; Last non-visor foreground window; focus returns here when the visor is hidden
global g_VisorReturnHwnd       := 0

; In-memory debounce for the background update check (not a session-wide lock)
global g_LastUpdateCheckSpawn  := 0

; Config values that were rejected on read. Reported once at startup, written to
; quake.log and kept for the tray diagnostics instead of being silently replaced.
global g_ConfigWarnings        := []

; Hotkey bindings that failed or needed the toggle fallback. Same treatment as
; g_ConfigWarnings: startup dialog, log, tray diagnostics.
global g_BindingFailures       := []

; Diagnostics log (%APPDATA%\alacritty\quake.log). Append-only, capped, one
; rotation. The log is the source of truth for "why did that not work?" because
; TrayTip is dropped whenever Windows notifications are off.
global g_LogPath               := ""
global g_LogMaxBytes           := 262144

; -------------------------------------------------------------
; Diagnostics Log
; -------------------------------------------------------------
; Everything that used to disappear into a bare `try` or a silent default goes
; here: rejected config values, failed hotkey bindings, failed window moves,
; monitor migrations and shell-resolution failures. Logging must never take the
; visor down, so every write is wrapped.
InitLog()
{
    global g_LogPath
    appData := EnvGet("APPDATA")
    logDir := (appData != "") ? appData . "\alacritty" : A_ScriptDir
    if (!DirExist(logDir))
        logDir := A_ScriptDir
    g_LogPath := logDir . "\quake.log"
}

LogWrite(level, message)
{
    global g_LogPath
    if (g_LogPath == "")
        return
    try {
        RotateLogIfNeeded()
        stamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        FileAppend(stamp . " [" . level . "] " . message . "`r`n", g_LogPath, "UTF-8-RAW")
    } catch {
        ; A failed log write is not worth a dialog; the visor keeps running.
    }
}

; One rotation at 256 KB keeps the pair under ~512 KB without a rotation chain.
RotateLogIfNeeded()
{
    global g_LogPath, g_LogMaxBytes
    if (!FileExist(g_LogPath))
        return
    try {
        if (FileGetSize(g_LogPath) < g_LogMaxBytes)
            return
        rotated := g_LogPath . ".1"
        if FileExist(rotated)
            FileDelete(rotated)
        FileMove(g_LogPath, rotated)
    } catch {
    }
}

; Writes every collected config/binding problem. Called once after startup so the
; list is complete, and the same strings feed the tray dialog.
LogConfigProblems()
{
    global g_ConfigWarnings, g_BindingFailures
    for warning in g_ConfigWarnings
        LogWrite("WARN", "config: " . warning)
    for failure in g_BindingFailures
        LogWrite("WARN", "binding: " . failure)
}

; Minimal join for log messages; AHK v2 has no built-in Array.join.
JoinArray(items, separator)
{
    text := ""
    for item in items
        text .= (text == "" ? "" : separator) . item
    return text
}

; Helper: Resolves configuration file location and loads user preferences
LoadConfig()
{
    global g_ConfigFile, g_BorderGap, g_BorderColor, g_VisorHeightPercent, g_MultiMonitorMode, g_ShowHelpOnStart, g_FirstRun, g_StartingDirectory
    global g_AlacrittyConfiguredPath
    global g_ConfigWarnings
    global g_TileLayout, g_TwoPaneLayout, g_KeyCycleLayout
    global g_KeyToggleVisor, g_KeySplit, g_KeyClose, g_KeyRetile
    global g_KeyFocusLeft, g_KeyFocusRight, g_KeyFocusUp, g_KeyFocusDown
    global g_KeySwapLeft, g_KeySwapRight, g_KeySwapUp, g_KeySwapDown
    global g_KeyRotate, g_KeyMoveVisorLeft, g_KeyMoveVisorRight, g_KeyReload
    global g_SelfTestConfig

    ; 1. Resolve path (%APPDATA%\alacritty\config.ini or local repository)
    if (g_SelfTestConfig != "")
    {
        g_ConfigFile := g_SelfTestConfig
    }
    else
    {
        appDataPath := EnvGet("APPDATA") . "\alacritty\config.ini"
        localPath   := A_ScriptDir . "\config.ini"

        if FileExist(appDataPath)
            g_ConfigFile := appDataPath
        else if FileExist(localPath)
            g_ConfigFile := localPath
        else
            g_ConfigFile := appDataPath
    }

    if (!FileExist(g_ConfigFile))
    {
        LogWrite("INFO", "config: no config.ini at " . g_ConfigFile . "; using defaults")
        return
    }
    LogWrite("INFO", "config: reading " . g_ConfigFile)

    ; Win32 GetPrivateProfileString (IniRead) does not support UNC paths (such
    ; as \\wsl.localhost\...). Stage to a temp file on C: so IniRead succeeds,
    ; then restore g_ConfigFile so diagnostics report the real location.
    realConfigFile := g_ConfigFile
    tempConfigFile := ""
    if (SubStr(g_ConfigFile, 1, 2) == "\\")
    {
        tempConfigFile := A_Temp . "\quake_ini_" . DllCall("GetCurrentProcessId") . ".ini"
        try {
            FileCopy(g_ConfigFile, tempConfigFile, true)
            g_ConfigFile := tempConfigFile
        }
    }

    ; 2. [General]
    try {
        frVal := IniRead(g_ConfigFile, "General", "FirstRun", "false")
        ; FirstRun is consumed once per install. The AHK cannot clear the key in
        ; config.ini: IniWrite would rewrite the UTF-8 file in the ANSI code page
        ; (see README), so consumption is tracked by a marker file instead.
        g_FirstRun := (frVal = "true" || frVal = "1") && !FileExist(FirstRunMarkerPath())
        modeVal := Trim(StrLower(IniRead(g_ConfigFile, "General", "MultiMonitorMode", "isolated")))
        if (modeVal == "hopping" || modeVal == "isolated")
            g_MultiMonitorMode := modeVal
        else
        {
            if (modeVal != "")
                AddConfigWarning("MultiMonitorMode=" . modeVal . " is not isolated|hopping; using isolated.")
            g_MultiMonitorMode := "isolated"
        }

        helpVal := Trim(StrLower(IniRead(g_ConfigFile, "General", "ShowHelpOnStart", "tip")))
        if (helpVal == "tip" || helpVal == "banner" || helpVal == "none" || helpVal == "first-run")
            g_ShowHelpOnStart := helpVal
        else if (helpVal == "always" || helpVal == "true" || helpVal == "1")
            g_ShowHelpOnStart := "tip"
        else if (helpVal == "false" || helpVal == "0")
            g_ShowHelpOnStart := "none"
        else
        {
            AddConfigWarning("ShowHelpOnStart=" . helpVal . " is not tip|banner|none|first-run; using tip.")
            g_ShowHelpOnStart := "tip"
        }

        startDirVal := Trim(IniRead(g_ConfigFile, "General", "StartingDirectory", "~"))
        g_StartingDirectory := (startDirVal != "") ? startDirVal : "~"

        ; Optional escape hatch for portable/custom Alacritty installs. It is
        ; never written to config.ini by the installer, so the template stays
        ; unchanged; an absent or invalid value simply falls back to PATH.
        g_AlacrittyConfiguredPath := Trim(IniRead(g_ConfigFile, "General", "AlacrittyPath", ""))
    }

    ; 3. [Appearance]
    try {
        ; IsInteger first: Integer("abc") would throw and abort the rest of this
        ; section, silently dropping BorderColor, the visor height and the layouts.
        gapRaw := Trim(IniRead(g_ConfigFile, "Appearance", "BorderGap", "2"))
        gapVal := IsInteger(gapRaw) ? Integer(gapRaw) : -1
        if (gapVal >= 0 && gapVal <= 10)
            g_BorderGap := gapVal
        else
            AddConfigWarning("BorderGap=" . gapRaw . " is not an integer in 0-10; using " . g_BorderGap . ".")

        colVal := Trim(IniRead(g_ConfigFile, "Appearance", "BorderColor", "38bdf8"))
        if (colVal != "")
            g_BorderColor := StrReplace(colVal, "#", "")

        vhRaw := Trim(IniRead(g_ConfigFile, "Appearance", "VisorHeightPercent", "40"))
        vhVal := IsInteger(vhRaw) ? Integer(vhRaw) : -1
        if (vhVal >= 10 && vhVal <= 100)
            g_VisorHeightPercent := vhVal / 100.0
        else
            AddConfigWarning("VisorHeightPercent=" . vhRaw . " is not an integer in 10-100; using " . Round(g_VisorHeightPercent * 100) . ".")

        tlVal := Trim(StrLower(IniRead(g_ConfigFile, "Appearance", "TileLayout", "bottom")))
        if (tlVal == "bottom" || tlVal == "top" || tlVal == "left" || tlVal == "right")
            g_TileLayout := tlVal

        tpVal := Trim(StrLower(IniRead(g_ConfigFile, "Appearance", "TwoPaneLayout", "side-by-side-visor")))
        if (tpVal == "side-by-side-visor" || tpVal == "side-by-side-full" || tpVal == "top-bottom" || tpVal == "horizontal-full" || tpVal == "horizontal" || tpVal == "left-stacked" || tpVal == "right-stacked")
            g_TwoPaneLayout := (tpVal == "horizontal-full" || tpVal == "horizontal") ? "top-bottom" : tpVal
    }

    ; 4. [Hotkeys]
    try {
        g_KeyToggleVisor := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "ToggleVisor", g_KeyToggleVisor))
        g_KeySplit       := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "SplitWindow", g_KeySplit))
        g_KeyClose       := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "CloseWindow", g_KeyClose))
        g_KeyRetile      := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "Retile", g_KeyRetile))
        g_KeyCycleLayout := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "CycleLayout", g_KeyCycleLayout))
        g_KeyFocusLeft   := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "FocusLeft", g_KeyFocusLeft))
        g_KeyFocusRight  := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "FocusRight", g_KeyFocusRight))
        g_KeyFocusUp     := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "FocusUp", g_KeyFocusUp))
        g_KeyFocusDown   := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "FocusDown", g_KeyFocusDown))
        g_KeySwapLeft    := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "SwapLeft", g_KeySwapLeft))
        g_KeySwapRight   := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "SwapRight", g_KeySwapRight))
        g_KeySwapUp      := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "SwapUp", g_KeySwapUp))
        g_KeySwapDown    := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "SwapDown", g_KeySwapDown))
        g_KeyRotate         := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "RotatePanes", g_KeyRotate))
        g_KeyMoveVisorLeft  := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "MoveVisorLeft", g_KeyMoveVisorLeft))
        g_KeyMoveVisorRight := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "MoveVisorRight", g_KeyMoveVisorRight))
        g_KeyReload      := NormalizeHotkey(IniRead(g_ConfigFile, "Hotkeys", "ReloadScript", g_KeyReload))
    }
    if (tempConfigFile != "")
    {
        try FileDelete(tempConfigFile)
        g_ConfigFile := realConfigFile
    }
}

; Helper: cleans a configured hotkey before it reaches Hotkey(). IniRead uses
; GetPrivateProfileString, which keeps inline "; comments", and an AHK hotkey
; string can never contain ';' - so cutting at the first one is safe. Whitespace
; is trimmed so "!w " and " !w" bind like "!w".
NormalizeHotkey(value)
{
    text := Trim(value)
    commentAt := InStr(text, ";")
    if (commentAt)
        text := Trim(SubStr(text, 1, commentAt - 1))
    return text
}

; Helper: records a rejected config value instead of silently substituting a
; default. Kept as data so the log and tray diagnostics write the same list.
AddConfigWarning(message)
{
    global g_ConfigWarnings
    g_ConfigWarnings.Push(message)
}

; Helper: records a hotkey binding that failed or needed a fallback.
AddBindingFailure(label, value, reason)
{
    global g_BindingFailures
    g_BindingFailures.Push(label . "=" . value . " (" . reason . ")")
}

; First-run consumption marker. Lives next to the deployed config so the
; installer can clear it when it restores FirstRun=true.
FirstRunMarkerPath()
{
    appData := EnvGet("APPDATA")
    if (appData != "")
        return appData . "\alacritty\.first-run-consumed"
    return A_ScriptDir . "\.first-run-consumed"
}

MarkFirstRunConsumed()
{
    global g_FirstRun
    g_FirstRun := false
    markerPath := FirstRunMarkerPath()
    try {
        if FileExist(markerPath)
            FileDelete(markerPath)
        FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"), markerPath, "UTF-8-RAW")
        LogWrite("INFO", "first-run: flag consumed; marker written")
    } catch as err {
        LogWrite("WARN", "first-run: could not write marker: " . err.Message)
    }
}

; Shows every collected config problem, including failed hotkey bindings.
; TrayTip is not a reliable surface (Windows notifications can be off), so this
; dialog and the log are the primary reports and the tray entry keeps them
; reachable afterwards.
ShowConfigWarnings()
{
    global g_ConfigWarnings, g_BindingFailures
    if (!g_ConfigWarnings.Length && !g_BindingFailures.Length)
        return

    total := g_ConfigWarnings.Length + g_BindingFailures.Length
    text := "Quake Alacritty found " . total . " problem(s) at startup:`n`n"
    for warning in g_ConfigWarnings
        text .= "- " . warning . "`n"
    for failure in g_BindingFailures
        text .= "- Hotkey " . failure . "`n"
    text .= "`nFix the values, then use Tray -> Reload (or restart)."
    MsgBox(text, "Quake Alacritty config", "Icon!")
}

; Helper: Binds dynamic hotkeys from configuration. Every failure is collected
; instead of swallowed, so a typo in config.ini is visible at startup, in the
; tray and in quake.log.
RegisterHotkeys()
{
    global g_KeyToggleVisor

    ; Global visor toggle. The last-resort #sc029 fallback is kept so the visor
    ; stays reachable, but a fallback is a config problem and is reported as one.
    if (g_KeyToggleVisor != "")
    {
        try Hotkey(g_KeyToggleVisor, (*) => ToggleVisor())
        catch {
            try {
                Hotkey("#sc029", (*) => ToggleVisor())
                AddBindingFailure("Hotkeys.ToggleVisor", g_KeyToggleVisor, "invalid; fell back to #sc029")
            } catch as err {
                AddBindingFailure("Hotkeys.ToggleVisor", g_KeyToggleVisor, "invalid and the #sc029 fallback failed: " . err.Message)
            }
        }
    }
    else
        LogWrite("INFO", "binding: Hotkeys.ToggleVisor is empty; toggle disabled")

    ; Context-sensitive hotkeys inside Alacritty
    HotIfWinActive("ahk_exe alacritty.exe")

    RegisterKey(g_KeySplit,       (*) => SpawnSplit(),            "Hotkeys.SplitWindow")
    RegisterKey(g_KeyClose,       (*) => CloseSplit(),            "Hotkeys.CloseWindow")
    RegisterKey("!F4",            (*) => CloseSplit(),            "built-in Alt+F4")
    RegisterKey(g_KeyRetile,      (*) => TileAlacritty(),         "Hotkeys.Retile")
    RegisterKey(g_KeyCycleLayout, (*) => CycleLayout(),           "Hotkeys.CycleLayout")
    RegisterKey(g_KeyFocusLeft,   (*) => FocusDirection("left"),  "Hotkeys.FocusLeft")
    RegisterKey(g_KeyFocusRight,  (*) => FocusDirection("right"), "Hotkeys.FocusRight")
    RegisterKey(g_KeyFocusUp,     (*) => FocusDirection("up"),    "Hotkeys.FocusUp")
    RegisterKey(g_KeyFocusDown,   (*) => FocusDirection("down"),  "Hotkeys.FocusDown")
    RegisterKey(g_KeySwapLeft,    (*) => SwapDirection("left"),   "Hotkeys.SwapLeft")
    RegisterKey(g_KeySwapRight,   (*) => SwapDirection("right"),  "Hotkeys.SwapRight")
    RegisterKey(g_KeySwapUp,      (*) => SwapDirection("up"),     "Hotkeys.SwapUp")
    RegisterKey(g_KeySwapDown,    (*) => SwapDirection("down"),   "Hotkeys.SwapDown")
    RegisterKey(g_KeyRotate,         (*) => RotateWindows(),          "Hotkeys.RotatePanes")
    RegisterKey(g_KeyMoveVisorLeft,  (*) => MoveVisorDirection("left"),  "Hotkeys.MoveVisorLeft")
    RegisterKey(g_KeyMoveVisorRight, (*) => MoveVisorDirection("right"), "Hotkeys.MoveVisorRight")
    RegisterKey(g_KeyReload,      (*) => Reload(),                "Hotkeys.ReloadScript")

    HotIfWinActive()
}

RegisterKey(keyName, callback, label := "")
{
    if (keyName == "")
    {
        LogWrite("INFO", "binding: " . label . " is empty; disabled")
        return
    }
    hookKey := (InStr(keyName, "#") && !InStr(keyName, "$")) ? ("$" . keyName) : keyName
    try {
        Hotkey(hookKey, callback)
        return
    } catch {
        ; Some keys (e.g. with a forced hook prefix) only bind without it.
        try {
            Hotkey(keyName, callback)
            return
        } catch as plainErr {
            AddBindingFailure(label, keyName, plainErr.Message)
        }
    }
}

; -------------------------------------------------------------
; Layout Getters & Setters per Monitor
; -------------------------------------------------------------
GetMonTileLayout(mon)
{
    global g_TileLayout, g_MonitorTileLayout
    if (g_MonitorTileLayout.Has(mon))
        return g_MonitorTileLayout[mon]
    return g_TileLayout
}

SetMonTileLayout(mon, val)
{
    global g_MonitorTileLayout, g_TileLayout
    g_MonitorTileLayout[mon] := val
    g_TileLayout := val
}

GetMonTwoPaneLayout(mon)
{
    global g_TwoPaneLayout, g_MonitorTwoPaneLayout
    if (g_MonitorTwoPaneLayout.Has(mon))
        return g_MonitorTwoPaneLayout[mon]
    return g_TwoPaneLayout
}

SetMonTwoPaneLayout(mon, val)
{
    global g_MonitorTwoPaneLayout, g_TwoPaneLayout
    g_MonitorTwoPaneLayout[mon] := val
    g_TwoPaneLayout := val
}

GetMonSinglePaneSide(mon)
{
    global g_SinglePaneSide, g_MonitorSinglePaneSide
    if (g_MonitorSinglePaneSide.Has(mon))
        return g_MonitorSinglePaneSide[mon]
    return g_SinglePaneSide
}

SetMonSinglePaneSide(mon, val)
{
    global g_MonitorSinglePaneSide, g_SinglePaneSide
    g_MonitorSinglePaneSide[mon] := val
    g_SinglePaneSide := val
}

; -------------------------------------------------------------
; Dividers Management
; -------------------------------------------------------------

; Helper: Clears and destroys active divider lines (for specific monitor or all monitors)
ClearDividers(mon := 0)
{
    global g_MonitorDividers, g_Dividers
    if (mon != 0)
    {
        if (g_MonitorDividers.Has(mon))
        {
            for div in g_MonitorDividers[mon]
            {
                try div.Destroy()
            }
            g_MonitorDividers[mon] := []
        }
    }
    else
    {
        for mId, divList in g_MonitorDividers
        {
            for div in divList
            {
                try div.Destroy()
            }
        }
        g_MonitorDividers := Map()

        for div in g_Dividers
        {
            try div.Destroy()
        }
        g_Dividers := []
    }
}

; Helper: Creates a click-through divider line tracked per monitor
CreateDivider(arg1, arg2, arg3, arg4, arg5, arg6 := "")
{
    global g_MonitorDividers, g_Dividers
    if (arg6 != "")
    {
        mon   := arg1
        x     := arg2
        y     := arg3
        w     := arg4
        h     := arg5
        color := arg6
    }
    else
    {
        mon   := 0
        x     := arg1
        y     := arg2
        w     := arg3
        h     := arg4
        color := arg5
    }

    ; +AlwaysOnTop, -Caption, +ToolWindow, +E0x20 (click-through WS_EX_TRANSPARENT), -DPIScale (pixel-accurate)
    div := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
    div.BackColor := color
    div.Show(Format("x{1} y{2} w{3} h{4} NoActivate", x, y, w, h))

    if (!g_MonitorDividers.Has(mon))
        g_MonitorDividers[mon] := []
    g_MonitorDividers[mon].Push(div)
}

; -------------------------------------------------------------
; Window Discovery & Synchronization
; -------------------------------------------------------------

; Helper: Filters out ghost/helper windows and only keeps true terminal windows
GetAlacrittyWindows()
{
    DetectHiddenWindows true
    realList := []
    for hwnd in WinGetList("ahk_exe alacritty.exe")
    {
        cls      := WinGetClass("ahk_id " hwnd)
        exStyle  := WinGetExStyle("ahk_id " hwnd)
        hasOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr") ; GW_OWNER = 4

        ; Strict filter:
        ; 1. The genuine Alacritty terminal window on Windows has class "Window Class"
        ; 2. Excludes Nvidia OpenGL buffers ("NVOpenGLPbuffer"), event targets ("Winit Thread Event Target"),
        ;    tool windows, and owned child windows
        if (cls != "Window Class" || (exStyle & 0x80) || hasOwner)
            continue

        realList.Push(hwnd)
    }
    return realList
}

; Helper: Maintains a stable window ordering in hopping mode so splits don't jump around
SyncWindowOrder(realWindows)
{
    global g_AlacrittyOrder

    ; 1. Keep currently tracked windows that are still alive
    newOrder := []
    for hwnd in g_AlacrittyOrder
    {
        for realHwnd in realWindows
        {
            if (hwnd == realHwnd)
            {
                newOrder.Push(hwnd)
                break
            }
        }
    }

    ; 2. Identify any newly spawned windows
    addedWindows := []
    for realHwnd in realWindows
    {
        alreadyTracked := false
        for hwnd in newOrder
        {
            if (hwnd == realHwnd)
            {
                alreadyTracked := true
                break
            }
        }
        if (!alreadyTracked)
            addedWindows.Push(realHwnd)
    }

    ; If cold start with multiple existing windows, sort by Y (top-to-bottom) then X (left-to-right)
    if (newOrder.Length == 0 && addedWindows.Length > 1)
    {
        n := addedWindows.Length
        Loop n {
            i := A_Index
            Loop n - i {
                j := A_Index
                try {
                    WinGetPos(&x1, &y1,,, "ahk_id " addedWindows[j])
                    WinGetPos(&x2, &y2,,, "ahk_id " addedWindows[j+1])
                    if (y1 > y2 + 60 || (Abs(y1 - y2) <= 60 && x1 > x2)) {
                        temp := addedWindows[j]
                        addedWindows[j] := addedWindows[j+1]
                        addedWindows[j+1] := temp
                    }
                }
            }
        }
    }

    ; 3. Append added windows
    for hwnd in addedWindows
        newOrder.Push(hwnd)

    g_AlacrittyOrder := newOrder
    return g_AlacrittyOrder
}

; Helper: Maintains per-monitor window partitioning for isolated workspaces
SyncMonitorWindows(targetMon := 0)
{
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder, g_LayoutLock
    DetectHiddenWindows true
    realWindows := GetAlacrittyWindows()

    if (g_MultiMonitorMode == "hopping")
    {
        SyncWindowOrder(realWindows)
        return
    }

    monCount := MonitorGetCount()
    Loop monCount {
        if (!g_MonitorWindows.Has(A_Index))
            g_MonitorWindows[A_Index] := []
    }

    ; 1. Prune dead windows and detect visible windows moved by user across monitors
    movedWindows := []
    for monId, winList in g_MonitorWindows
    {
        prunedList := []
        for hwnd in winList
        {
            isAlive := false
            for realHwnd in realWindows
            {
                if (hwnd == realHwnd)
                {
                    isAlive := true
                    break
                }
            }
            if (!isAlive)
                continue

            ; If window is visible, check if user dragged it to another monitor
            if (DllCall("IsWindowVisible", "Ptr", hwnd))
            {
                actualMon := GetWindowMonitor(hwnd)
                if (actualMon != 0 && actualMon != monId && actualMon <= monCount)
                {
                    movedWindows.Push({ hwnd: hwnd, toMon: actualMon })
                    continue
                }
            }

            prunedList.Push(hwnd)
        }
        g_MonitorWindows[monId] := prunedList
        if (prunedList.Length == 0 && g_MonitorDividers.Has(monId) && g_MonitorDividers[monId].Length > 0)
            ClearDividers(monId)
    }

    ; Re-assign moved windows
    for item in movedWindows
    {
        if (!g_MonitorWindows.Has(item.toMon))
            g_MonitorWindows[item.toMon] := []
        g_MonitorWindows[item.toMon].Push(item.hwnd)
    }

    ; 2. Identify untracked windows
    untracked := []
    for realHwnd in realWindows
    {
        isTracked := false
        for monId, winList in g_MonitorWindows
        {
            for hwnd in winList
            {
                if (hwnd == realHwnd)
                {
                    isTracked := true
                    break 2
                }
            }
        }
        if (!isTracked)
            untracked.Push(realHwnd)
    }

    ; 3. Assign untracked windows
    for hwnd in untracked
    {
        destMon := 0
        if (targetMon != 0 && targetMon <= monCount)
        {
            destMon := targetMon
        }
        else
        {
            destMon := GetWindowMonitor(hwnd)
            if (destMon == 0 || destMon > monCount)
                destMon := GetMouseMonitor()
        }

        if (destMon == 0 || destMon > monCount)
            destMon := MonitorGetPrimary()

        if (!g_MonitorWindows.Has(destMon))
            g_MonitorWindows[destMon] := []

        g_MonitorWindows[destMon].Push(hwnd)
    }

    ; 4. If a monitor had 0 windows and was assigned multiple untracked windows at once, sort spatially
    for monId, winList in g_MonitorWindows
    {
        if (winList.Length > 1)
        {
            allUntracked := true
            for hwnd in winList
            {
                wasInUntracked := false
                for uHwnd in untracked
                {
                    if (hwnd == uHwnd)
                    {
                        wasInUntracked := true
                        break
                    }
                }
                if (!wasInUntracked)
                {
                    allUntracked := false
                    break
                }
            }

            if (allUntracked)
            {
                n := winList.Length
                Loop n {
                    i := A_Index
                    Loop n - i {
                        j := A_Index
                        try {
                            WinGetPos(&x1, &y1,,, "ahk_id " winList[j])
                            WinGetPos(&x2, &y2,,, "ahk_id " winList[j+1])
                            if (y1 > y2 + 60 || (Abs(y1 - y2) <= 60 && x1 > x2)) {
                                temp := winList[j]
                                winList[j] := winList[j+1]
                                winList[j+1] := temp
                            }
                        }
                    }
                }
                g_MonitorWindows[monId] := winList
            }
        }
    }
}

; Helper: Checks if any window belonging to a monitor is currently visible
IsMonitorVisible(mon)
{
    global g_MonitorWindows
    if (!g_MonitorWindows.Has(mon))
        return false
    for hwnd in g_MonitorWindows[mon]
    {
        if (WinExist("ahk_id " hwnd) && DllCall("IsWindowVisible", "Ptr", hwnd))
            return true
    }
    return false
}

; Helper: Determines which monitor contains a given window
GetWindowMonitor(hwnd)
{
    try {
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        cx := wx + (ww / 2)
        cy := wy + (wh / 2)
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &mL, &mT, &mR, &mB)
            if (cx >= mL && cx < mR && cy >= mT && cy < mB)
                return A_Index
        }
    }
    return 0
}

; Helper: Determines which monitor contains the mouse cursor (or active window as fallback)
GetMouseMonitor()
{
    CoordMode "Mouse", "Screen"
    MouseGetPos(&mx, &my)
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        if (mx >= mL && mx < mR && my >= mT && my < mB)
            return A_Index
    }

    ; Fallback: Monitor containing the active window
    activeHwnd := WinActive("A")
    if (activeHwnd)
    {
        mon := GetWindowMonitor(activeHwnd)
        if (mon)
            return mon
    }

    return MonitorGetPrimary()
}

; -------------------------------------------------------------
; Window Tiling Engine
; -------------------------------------------------------------

; Moves one pane and records why a move failed. A closed window and an invalid
; rectangle are different bugs - the first is a race with the user or a dying
; process, the second is ours - and both used to vanish into `try WinMove`.
; Returns true only when the move was actually issued.
MovePane(hwnd, x, y, w, h)
{
    if (!WinExist("ahk_id " hwnd))
    {
        LogWrite("INFO", "tile: pane " . hwnd . " is gone before move (" . x . "," . y . " " . w . "x" . h . ")")
        return false
    }
    if (w <= 0 || h <= 0)
    {
        LogWrite("ERROR", "tile: invalid rectangle for pane " . hwnd . ": " . x . "," . y . " " . w . "x" . h)
        return false
    }
    try {
        WinMove(x, y, w, h, "ahk_id " hwnd)
        return true
    } catch as err {
        LogWrite("ERROR", "tile: WinMove failed for pane " . hwnd . " (" . x . "," . y . " " . w . "x" . h . "): " . err.Message)
        return false
    }
}

; Helper: Tiles Alacritty windows dynamically:
; 1 window:  Top 100% width, 40% height (or 50% width full-height if positioned left/right)
; 2 windows: Configurable 2-pane mode (side-by-side visor/full, left-stacked, right-stacked)
; 3 windows: 4-cardinal master orientations (bottom, top, left, right)
; 4 windows: Top 50% / 50% width, Bottom 50% / 50% width (2x2 Quad, cyan cross seams)
TileAlacritty(targetMon := 0, syncWindows := true)
{
    global g_BorderGap, g_BorderColor, g_VisorHeightPercent
    global g_TileLayout, g_TwoPaneLayout, g_SinglePaneSide
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder, g_LayoutLock
    DetectHiddenWindows true

    if (g_MultiMonitorMode == "isolated")
    {
        if (targetMon == 0)
        {
            activeHwnd := WinActive("A")
            if (activeHwnd)
                targetMon := GetWindowMonitor(activeHwnd)
            if (targetMon == 0)
                targetMon := GetMouseMonitor()
        }

        if (syncWindows)
            SyncMonitorWindows(targetMon)

        if (!g_MonitorWindows.Has(targetMon))
            g_MonitorWindows[targetMon] := []

        windows := g_MonitorWindows[targetMon]
        count := windows.Length
        if (count == 0)
        {
            ClearDividers(targetMon)
            return
        }

        ClearDividers(targetMon)

        curTileLayout     := GetMonTileLayout(targetMon)
        curTwoPaneLayout  := GetMonTwoPaneLayout(targetMon)
        curSinglePaneSide := GetMonSinglePaneSide(targetMon)
    }
    else ; "hopping" mode
    {
        realWindows := GetAlacrittyWindows()
        count := realWindows.Length
        if (count == 0)
        {
            ClearDividers(0)
            return
        }

        ClearDividers(0)
        windows := (syncWindows || g_AlacrittyOrder.Length == 0) ? SyncWindowOrder(realWindows) : g_AlacrittyOrder

        if (targetMon == 0)
        {
            for hwnd in windows
            {
                if DllCall("IsWindowVisible", "Ptr", hwnd)
                {
                    mon := GetWindowMonitor(hwnd)
                    if (mon)
                    {
                        targetMon := mon
                        break
                    }
                }
            }
            if (targetMon == 0)
                targetMon := GetMouseMonitor()
        }

        curTileLayout     := g_TileLayout
        curTwoPaneLayout  := g_TwoPaneLayout
        curSinglePaneSide := g_SinglePaneSide
    }

    ; 1. Show all windows and set on top
    for hwnd in windows
    {
        try {
            WinShow("ahk_id " hwnd)
            WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        }
    }

    ; 2. Work area dimensions (avoids taskbar)
    MonitorGetWorkArea(targetMon, &wLeft, &wTop, &wRight, &wBottom)
    totalWidth  := wRight - wLeft
    totalHeight := wBottom - wTop
    gap         := (count > 1) ? g_BorderGap : 0

    ; -------------------------------------------------------------
    ; Case 1: Exactly 1 window
    ; -------------------------------------------------------------
    if (count == 1)
    {
        hwnd := windows[1]
        if (curSinglePaneSide == "left")
        {
            thisW := Floor((totalWidth - gap) / 2)
            MovePane(hwnd, wLeft, wTop, thisW, totalHeight)
        }
        else if (curSinglePaneSide == "right")
        {
            thisW := Floor((totalWidth - gap) / 2)
            currentX := wLeft + totalWidth - thisW
            MovePane(hwnd, currentX, wTop, thisW, totalHeight)
        }
        else
        {
            topHeight := Floor(totalHeight * g_VisorHeightPercent)
            MovePane(hwnd, wLeft, wTop, totalWidth, topHeight)
        }
        return
    }

    ; -------------------------------------------------------------
    ; Case 2: Exactly 2 windows
    ; -------------------------------------------------------------
    if (count == 2)
    {
        if (curTwoPaneLayout == "top-bottom" || curTwoPaneLayout == "horizontal-full" || curTwoPaneLayout == "horizontal")
        {
            availHeight := totalHeight - gap
            h1 := Floor(availHeight / 2)
            h2 := availHeight - h1

            MovePane(windows[1], wLeft, wTop, totalWidth, h1)
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + h1, totalWidth, gap, g_BorderColor)
            MovePane(windows[2], wLeft, wTop + h1 + gap, totalWidth, h2)
        }
        else if (curTwoPaneLayout == "left-stacked")
        {
            colW := Floor((totalWidth - gap) / 2)
            availHeight := totalHeight - gap
            h1 := Floor(availHeight / 2)
            h2 := availHeight - h1

            MovePane(windows[1], wLeft, wTop, colW, h1)
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + h1, colW, gap, g_BorderColor)
            MovePane(windows[2], wLeft, wTop + h1 + gap, colW, h2)
        }
        else if (curTwoPaneLayout == "right-stacked")
        {
            colW := Floor((totalWidth - gap) / 2)
            leftX := wLeft + totalWidth - colW
            availHeight := totalHeight - gap
            h1 := Floor(availHeight / 2)
            h2 := availHeight - h1

            MovePane(windows[1], leftX, wTop, colW, h1)
            if (gap > 0)
                CreateDivider(targetMon, leftX, wTop + h1, colW, gap, g_BorderColor)
            MovePane(windows[2], leftX, wTop + h1 + gap, colW, h2)
        }
        else ; "side-by-side-visor" or "side-by-side-full"
        {
            paneHeight := (curTwoPaneLayout == "side-by-side-full") ? totalHeight : Floor(totalHeight * g_VisorHeightPercent)
            availWidth := totalWidth - gap
            col1W := Floor(availWidth / 2)
            col2W := availWidth - col1W

            MovePane(windows[1], wLeft, wTop, col1W, paneHeight)
            if (gap > 0)
                CreateDivider(targetMon, wLeft + col1W, wTop, gap, paneHeight, g_BorderColor)
            MovePane(windows[2], wLeft + col1W + gap, wTop, col2W, paneHeight)
        }
        return
    }

    ; -------------------------------------------------------------
    ; Case 3: Exactly 3 windows (4 Cardinal Master Orientations)
    ; -------------------------------------------------------------
    if (count == 3)
    {
        if (curTileLayout == "top")
        {
            ; Top-Master: 1 top pane (100% width), 2 bottom panes (50%/50% width)
            availHeight := totalHeight - gap
            topHeight   := Floor(availHeight / 2)
            botHeight   := availHeight - topHeight
            botY        := wTop + topHeight + gap

            availWidth  := totalWidth - gap
            bot1W       := Floor(availWidth / 2)
            bot2W       := availWidth - bot1W

            ; Window 1: Top Master
            MovePane(windows[1], wLeft, wTop, totalWidth, topHeight)

            ; Full-width horizontal divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

            ; Window 2: Bottom-Left
            MovePane(windows[2], wLeft, botY, bot1W, botHeight)

            ; Bottom vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + bot1W, botY, gap, botHeight, g_BorderColor)

            ; Window 3: Bottom-Right
            MovePane(windows[3], wLeft + bot1W + gap, botY, bot2W, botHeight)
        }
        else if (curTileLayout == "left")
        {
            ; Left-Master: Left pane 100% height, Right column 2 stacked panes
            availWidth  := totalWidth - gap
            masterWidth := Floor(availWidth / 2)
            rightWidth  := availWidth - masterWidth
            rightX      := wLeft + masterWidth + gap

            availHeight := totalHeight - gap
            h1          := Floor(availHeight / 2)
            h2          := availHeight - h1

            ; Window 1: Left Master (100% height)
            MovePane(windows[1], wLeft, wTop, masterWidth, totalHeight)

            ; Full-height vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + masterWidth, wTop, gap, totalHeight, g_BorderColor)

            ; Window 2: Top-Right
            MovePane(windows[2], rightX, wTop, rightWidth, h1)

            ; Horizontal divider in right column
            if (gap > 0)
                CreateDivider(targetMon, rightX, wTop + h1, rightWidth, gap, g_BorderColor)

            ; Window 3: Bottom-Right
            MovePane(windows[3], rightX, wTop + h1 + gap, rightWidth, h2)
        }
        else if (curTileLayout == "right")
        {
            ; Right-Master: Right pane 100% height, Left column 2 stacked panes
            ; Reading order: [1: Top-Left, 2: Right-Master, 3: Bottom-Left]
            availWidth  := totalWidth - gap
            leftWidth   := Floor(availWidth / 2)
            masterWidth := availWidth - leftWidth
            rightX      := wLeft + leftWidth + gap

            availHeight := totalHeight - gap
            h1          := Floor(availHeight / 2)
            h2          := availHeight - h1

            ; Window 1: Top-Left
            MovePane(windows[1], wLeft, wTop, leftWidth, h1)

            ; Horizontal divider in left column
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + h1, leftWidth, gap, g_BorderColor)

            ; Window 3: Bottom-Left
            MovePane(windows[3], wLeft, wTop + h1 + gap, leftWidth, h2)

            ; Full-height vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + leftWidth, wTop, gap, totalHeight, g_BorderColor)

            ; Window 2: Right Master (100% height)
            MovePane(windows[2], rightX, wTop, masterWidth, totalHeight)
        }
        else ; "bottom" (default)
        {
            ; Bottom-Master: 2 top panes (50%/50% width), 1 bottom master pane (100% width)
            availHeight := totalHeight - gap
            topHeight   := Floor(availHeight / 2)
            botHeight   := availHeight - topHeight
            botY        := wTop + topHeight + gap

            availWidth  := totalWidth - gap
            top1W       := Floor(availWidth / 2)
            top2W       := availWidth - top1W

            ; Window 1: Top-Left
            MovePane(windows[1], wLeft, wTop, top1W, topHeight)

            ; Top vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + top1W, wTop, gap, topHeight, g_BorderColor)

            ; Window 2: Top-Right
            MovePane(windows[2], wLeft + top1W + gap, wTop, top2W, topHeight)

            ; Full-width horizontal divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

            ; Window 3: Bottom Master (100% width)
            MovePane(windows[3], wLeft, botY, totalWidth, botHeight)
        }
        return
    }

    ; -------------------------------------------------------------
    ; Case 4: 4 windows (2x2 Quad Grid) or general N-window distribution
    ; -------------------------------------------------------------
    topCount := Ceil(count / 2)
    botCount := count - topCount

    availHeight := totalHeight - gap
    topHeight   := Floor(availHeight / 2)
    botHeight   := availHeight - topHeight
    botY        := wTop + topHeight + gap

    ; 3. Tile Top Row (with vertical dividers between adjacent windows)
    topAvailWidth   := totalWidth - ((topCount - 1) * gap)
    baseTopColWidth := Floor(topAvailWidth / topCount)
    currentX := wLeft
    Loop topCount {
        idx := A_Index
        hwnd := windows[idx]
        thisW := (idx == topCount) ? (wLeft + totalWidth - currentX) : baseTopColWidth
        MovePane(hwnd, currentX, wTop, thisW, topHeight)
        currentX += thisW

        if (idx < topCount && gap > 0)
        {
            CreateDivider(targetMon, currentX, wTop, gap, topHeight, g_BorderColor)
            currentX += gap
        }
    }

    ; 4. Tile Bottom Row (if any, with horizontal divider and vertical dividers)
    if (botCount > 0)
    {
        ; Horizontal divider between top and bottom rows
        if (gap > 0)
            CreateDivider(targetMon, wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

        botAvailWidth   := totalWidth - ((botCount - 1) * gap)
        baseBotColWidth := Floor(botAvailWidth / botCount)
        currentX := wLeft
        Loop botCount {
            idx := A_Index
            hwnd := windows[topCount + idx]
            thisW := (idx == botCount) ? (wLeft + totalWidth - currentX) : baseBotColWidth
            MovePane(hwnd, currentX, botY, thisW, botHeight)
            currentX += thisW

            if (idx < botCount && gap > 0)
            {
                CreateDivider(targetMon, currentX, botY, gap, botHeight, g_BorderColor)
                currentX += gap
            }
        }
    }
}

; -------------------------------------------------------------
; Keyboard Navigation & Swapping
; -------------------------------------------------------------

; Helper: Switch keyboard typing focus between splits using directional keys
FocusDirection(dir)
{
    global g_MultiMonitorMode, g_MonitorWindows
    activeHwnd := WinActive("A")
    if (!activeHwnd)
        return

    targetMon := GetWindowMonitor(activeHwnd)
    if (targetMon == 0)
        targetMon := GetMouseMonitor()

    candidateWindows := []
    if (g_MultiMonitorMode == "isolated")
    {
        if (g_MonitorWindows.Has(targetMon))
            candidateWindows := g_MonitorWindows[targetMon]
    }
    else
    {
        candidateWindows := GetAlacrittyWindows()
    }

    if (candidateWindows.Length <= 1)
        return

    WinGetPos(&ax, &ay, &aw, &ah, "ahk_id " activeHwnd)
    acx := ax + (aw / 2)
    acy := ay + (ah / 2)

    bestHwnd := 0
    bestDist := 99999999
    bestTcx  := 0
    bestTcy  := 0

    for hwnd in candidateWindows
    {
        if (hwnd == activeHwnd || !WinExist("ahk_id " hwnd))
            continue

        WinGetPos(&tx, &ty, &tw, &th, "ahk_id " hwnd)
        tcx := tx + (tw / 2)
        tcy := ty + (th / 2)

        valid := false
        if (dir == "left"  && tcx < acx - 50)
            valid := true
        else if (dir == "right" && tcx > acx + 50)
            valid := true
        else if (dir == "up"    && tcy < acy - 50)
            valid := true
        else if (dir == "down"  && tcy > acy + 50)
            valid := true

        if (valid)
        {
            dist := (tcx - acx)**2 + (tcy - acy)**2
            ; Tie-breaking for equidistant targets:
            ; For horizontal navigation (left/right), prefer higher up (smaller tcy).
            ; For vertical navigation (up/down), prefer further left (smaller tcx).
            isBetter := false
            if (dist < bestDist - 100)
                isBetter := true
            else if (Abs(dist - bestDist) <= 100)
            {
                if (dir == "left" || dir == "right")
                    isBetter := (tcy < bestTcy)
                else
                    isBetter := (tcx < bestTcx)
            }

            if (isBetter)
            {
                bestDist := dist
                bestHwnd := hwnd
                bestTcx  := tcx
                bestTcy  := tcy
            }
        }
    }

    if (bestHwnd)
        WinActivate("ahk_id " bestHwnd)
}

; Helper: Swap position of active terminal with adjacent terminal in given direction
SwapDirection(dir)
{
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder, g_LayoutLock
    activeHwnd := WinActive("A")
    if (!activeHwnd)
        return

    targetMon := GetWindowMonitor(activeHwnd)
    if (targetMon == 0)
        targetMon := GetMouseMonitor()

    candidateWindows := []
    if (g_MultiMonitorMode == "isolated")
    {
        SyncMonitorWindows(targetMon)
        if (g_MonitorWindows.Has(targetMon))
            candidateWindows := g_MonitorWindows[targetMon]
    }
    else
    {
        candidateWindows := GetAlacrittyWindows()
        SyncWindowOrder(candidateWindows)
    }

    if (candidateWindows.Length <= 1)
        return

    WinGetPos(&ax, &ay, &aw, &ah, "ahk_id " activeHwnd)
    acx := ax + (aw / 2)
    acy := ay + (ah / 2)

    bestHwnd := 0
    bestDist := 99999999
    bestTcx  := 0
    bestTcy  := 0

    for hwnd in candidateWindows
    {
        if (hwnd == activeHwnd || !WinExist("ahk_id " hwnd))
            continue

        WinGetPos(&tx, &ty, &tw, &th, "ahk_id " hwnd)
        tcx := tx + (tw / 2)
        tcy := ty + (th / 2)

        valid := false
        if (dir == "left"  && tcx < acx - 50)
            valid := true
        else if (dir == "right" && tcx > acx + 50)
            valid := true
        else if (dir == "up"    && tcy < acy - 50)
            valid := true
        else if (dir == "down"  && tcy > acy + 50)
            valid := true

        if (valid)
        {
            dist := (tcx - acx)**2 + (tcy - acy)**2
            isBetter := false
            if (dist < bestDist - 100)
                isBetter := true
            else if (Abs(dist - bestDist) <= 100)
            {
                if (dir == "left" || dir == "right")
                    isBetter := (tcy < bestTcy)
                else
                    isBetter := (tcx < bestTcx)
            }

            if (isBetter)
            {
                bestDist := dist
                bestHwnd := hwnd
                bestTcx  := tcx
                bestTcy  := tcy
            }
        }
    }

    if (!bestHwnd)
        return

    if (g_MultiMonitorMode == "isolated")
    {
        orderList := g_MonitorWindows[targetMon]
        idxActive := 0
        idxTarget := 0
        for idx, hwnd in orderList
        {
            if (hwnd == activeHwnd)
                idxActive := idx
            else if (hwnd == bestHwnd)
                idxTarget := idx
        }

        if (idxActive && idxTarget)
        {
            orderList[idxActive] := bestHwnd
            orderList[idxTarget] := activeHwnd
            g_MonitorWindows[targetMon] := orderList

            TileAlacritty(targetMon)
            WinActivate("ahk_id " activeHwnd)
        }
    }
    else
    {
        idxActive := 0
        idxTarget := 0
        for idx, hwnd in g_AlacrittyOrder
        {
            if (hwnd == activeHwnd)
                idxActive := idx
            else if (hwnd == bestHwnd)
                idxTarget := idx
        }

        if (idxActive && idxTarget)
        {
            g_AlacrittyOrder[idxActive] := bestHwnd
            g_AlacrittyOrder[idxTarget] := activeHwnd

            TileAlacritty(targetMon)
            WinActivate("ahk_id " activeHwnd)
        }
    }
}

; Helper: Rotate all terminal pane positions cyclically
RotateWindows(clockwise := true)
{
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder, g_LayoutLock
    activeHwnd := WinActive("A")
    if (!activeHwnd)
        return

    targetMon := GetWindowMonitor(activeHwnd)
    if (targetMon == 0)
        targetMon := GetMouseMonitor()

    if (g_MultiMonitorMode == "isolated")
    {
        SyncMonitorWindows(targetMon)
        if (!g_MonitorWindows.Has(targetMon) || g_MonitorWindows[targetMon].Length <= 1)
            return

        orderList := g_MonitorWindows[targetMon]
        if (clockwise)
        {
            lastItem := orderList.Pop()
            orderList.InsertAt(1, lastItem)
        }
        else
        {
            firstItem := orderList.RemoveAt(1)
            orderList.Push(firstItem)
        }
        g_MonitorWindows[targetMon] := orderList

        TileAlacritty(targetMon)
        if (activeHwnd && WinExist("ahk_id " activeHwnd))
            WinActivate("ahk_id " activeHwnd)
    }
    else
    {
        realWindows := GetAlacrittyWindows()
        if (realWindows.Length <= 1)
            return

        SyncWindowOrder(realWindows)
        if (g_AlacrittyOrder.Length <= 1)
            return

        if (clockwise)
        {
            lastItem := g_AlacrittyOrder.Pop()
            g_AlacrittyOrder.InsertAt(1, lastItem)
        }
        else
        {
            firstItem := g_AlacrittyOrder.RemoveAt(1)
            g_AlacrittyOrder.Push(firstItem)
        }

        TileAlacritty(targetMon)
        if (activeHwnd && WinExist("ahk_id " activeHwnd))
            WinActivate("ahk_id " activeHwnd)
    }
}

; Helper: Moves or swaps the active terminal visor to the adjacent physical monitor
MoveVisorDirection(dir)
{
    global g_MultiMonitorMode, g_MonitorWindows
    global g_MonitorTileLayout, g_MonitorTwoPaneLayout, g_MonitorSinglePaneSide
    DetectHiddenWindows true

    activeHwnd := WinActive("A")
    if (!activeHwnd)
        return

    srcMon := GetWindowMonitor(activeHwnd)
    if (srcMon == 0)
        srcMon := GetMouseMonitor()

    monCount := MonitorGetCount()
    if (monCount < 2)
        return

    ; 1. Resolve physical horizontal ordering of displays (X-offset)
    monList := []
    Loop monCount {
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        monList.Push({ id: A_Index, left: mL })
    }

    ; Sort by left coordinate ascending (physical left-to-right)
    n := monList.Length
    Loop n - 1 {
        i := A_Index
        Loop n - i {
            j := A_Index
            if (monList[j].left > monList[j + 1].left)
            {
                temp := monList[j]
                monList[j] := monList[j + 1]
                monList[j + 1] := temp
            }
        }
    }

    ; 2. Locate current monitor index in physically sorted list
    curIndex := 0
    Loop monList.Length {
        if (monList[A_Index].id == srcMon)
        {
            curIndex := A_Index
            break
        }
    }
    if (curIndex == 0)
        return

    ; 3. Determine target monitor with boundary clamping (no-op at edges)
    targetIndex := (dir == "left") ? (curIndex - 1) : (curIndex + 1)
    if (targetIndex < 1 || targetIndex > monList.Length)
        return

    dstMon := monList[targetIndex].id

    ; 4. Hopping mode: single roaming pool moves directly to dstMon
    if (g_MultiMonitorMode == "hopping")
    {
        TileAlacritty(dstMon, false)
        if (WinExist("ahk_id " activeHwnd))
            WinActivate("ahk_id " activeHwnd)
        return
    }

    ; 5. Isolated mode: swap/relocate window workspaces between srcMon and dstMon
    SyncMonitorWindows()


    if (!g_MonitorWindows.Has(srcMon))
        g_MonitorWindows[srcMon] := []
    if (!g_MonitorWindows.Has(dstMon))
        g_MonitorWindows[dstMon] := []

    srcWindows := g_MonitorWindows[srcMon]
    dstWindows := g_MonitorWindows[dstMon]

    if (srcWindows.Length == 0)
        return

    dstWasVisible := IsMonitorVisible(dstMon)

    ; Swap window arrays
    g_MonitorWindows[dstMon] := srcWindows
    g_MonitorWindows[srcMon] := dstWindows

    ; Swap layout configurations between monitors
    srcTile := GetMonTileLayout(srcMon)
    srcTwo  := GetMonTwoPaneLayout(srcMon)
    srcSide := GetMonSinglePaneSide(srcMon)

    dstTile := GetMonTileLayout(dstMon)
    dstTwo  := GetMonTwoPaneLayout(dstMon)
    dstSide := GetMonSinglePaneSide(dstMon)

    g_MonitorTileLayout[dstMon]     := srcTile
    g_MonitorTwoPaneLayout[dstMon]  := srcTwo
    g_MonitorSinglePaneSide[dstMon] := srcSide

    g_MonitorTileLayout[srcMon]     := dstTile
    g_MonitorTwoPaneLayout[srcMon]  := dstTwo
    g_MonitorSinglePaneSide[srcMon] := dstSide

    ; Re-tile destination monitor with relocated visor
    TileAlacritty(dstMon, false)

    ; Re-tile or clear source monitor
    if (dstWindows.Length > 0)
    {
        if (dstWasVisible)
        {
            TileAlacritty(srcMon, false)
        }
        else
        {
            for hwnd in dstWindows
                WinHide("ahk_id " hwnd)
            ClearDividers(srcMon)
        }
    }
    else
    {
        ClearDividers(srcMon)
    }

    ; Restore typing focus to the active window on destination display
    if (WinExist("ahk_id " activeHwnd))
        WinActivate("ahk_id " activeHwnd)
}

; Helper: Cycles multi-pane terminal layouts live without editing config.ini
CycleLayout()
{
    global g_TileLayout, g_TwoPaneLayout, g_SinglePaneSide
    global g_MultiMonitorMode, g_MonitorWindows

    activeHwnd := WinActive("A")
    targetMon := activeHwnd ? GetWindowMonitor(activeHwnd) : 0
    if (targetMon == 0)
        targetMon := GetMouseMonitor()

    if (g_MultiMonitorMode == "isolated")
    {
        SyncMonitorWindows(targetMon)
        windows := g_MonitorWindows.Has(targetMon) ? g_MonitorWindows[targetMon] : []
        count := windows.Length

        curTL := GetMonTileLayout(targetMon)
        curTP := GetMonTwoPaneLayout(targetMon)
        curSP := GetMonSinglePaneSide(targetMon)

        if (count == 1)
        {
            if (curSP == "")
                SetMonSinglePaneSide(targetMon, "left")
            else if (curSP == "left")
                SetMonSinglePaneSide(targetMon, "right")
            else
                SetMonSinglePaneSide(targetMon, "")
        }
        else if (count == 2)
        {
            if (curTP == "side-by-side-visor")
                curTP := "side-by-side-full"
            else if (curTP == "side-by-side-full")
                curTP := "top-bottom"
            else if (curTP == "top-bottom")
                curTP := "left-stacked"
            else if (curTP == "left-stacked")
                curTP := "right-stacked"
            else
                curTP := "side-by-side-visor"

            SetMonTwoPaneLayout(targetMon, curTP)
            newSP := (curTP == "left-stacked") ? "left" : ((curTP == "right-stacked") ? "right" : "")
            SetMonSinglePaneSide(targetMon, newSP)
        }
        else if (count == 3)
        {
            if (curTL == "bottom")
                curTL := "top"
            else if (curTL == "top")
                curTL := "left"
            else if (curTL == "left")
                curTL := "right"
            else
                curTL := "bottom"

            SetMonTileLayout(targetMon, curTL)
        }

        TileAlacritty(targetMon)
        if (activeHwnd && WinExist("ahk_id " activeHwnd))
            WinActivate("ahk_id " activeHwnd)
    }
    else
    {
        realWindows := GetAlacrittyWindows()
        count := realWindows.Length

        if (count == 1)
        {
            if (g_SinglePaneSide == "")
                g_SinglePaneSide := "left"
            else if (g_SinglePaneSide == "left")
                g_SinglePaneSide := "right"
            else
                g_SinglePaneSide := ""
        }
        else if (count == 2)
        {
            if (g_TwoPaneLayout == "side-by-side-visor")
                g_TwoPaneLayout := "side-by-side-full"
            else if (g_TwoPaneLayout == "side-by-side-full")
                g_TwoPaneLayout := "top-bottom"
            else if (g_TwoPaneLayout == "top-bottom")
                g_TwoPaneLayout := "left-stacked"
            else if (g_TwoPaneLayout == "left-stacked")
                g_TwoPaneLayout := "right-stacked"
            else
                g_TwoPaneLayout := "side-by-side-visor"

            g_SinglePaneSide := (g_TwoPaneLayout == "left-stacked") ? "left" : ((g_TwoPaneLayout == "right-stacked") ? "right" : "")
        }
        else if (count == 3)
        {
            if (g_TileLayout == "bottom")
                g_TileLayout := "top"
            else if (g_TileLayout == "top")
                g_TileLayout := "left"
            else if (g_TileLayout == "left")
                g_TileLayout := "right"
            else
                g_TileLayout := "bottom"
        }

        TileAlacritty(targetMon)
        if (activeHwnd && WinExist("ahk_id " activeHwnd))
            WinActivate("ahk_id " activeHwnd)
    }
}

; -------------------------------------------------------------
; Window Management Actions
; -------------------------------------------------------------

; Helper: Resolves the configured shell executable from alacritty.toml.
; Only the [terminal.shell] table counts: the previous version took the first
; `program = "..."` anywhere in the file, so a commented-out shell or an
; unrelated table (e.g. a keybinding action) could win. Comments are ignored and
; the current table header is tracked line by line.
GetConfiguredShellInfo(tomlPath := "")
{
    if (tomlPath == "")
    {
        appDataToml := EnvGet("APPDATA") . "\alacritty\alacritty.toml"
        localToml   := A_ScriptDir . "\alacritty.toml"
        tomlPath := FileExist(appDataToml) ? appDataToml : (FileExist(localToml) ? localToml : "")
    }

    if (tomlPath == "")
        return { program: "powershell.exe", source: "default (alacritty.toml not found)" }

    try {
        content := FileRead(tomlPath, "UTF-8")
    } catch as err {
        return { program: "powershell.exe", source: "default (alacritty.toml unreadable: " . err.Message . ")" }
    }

    section := ""
    for line in StrSplit(content, "`n", "`r")
    {
        trimmed := Trim(line)
        if (trimmed == "" || SubStr(trimmed, 1, 1) == "#")
            continue
        if (RegExMatch(trimmed, "^\[\[?([^\]]+)\]\]?$", &header))
        {
            section := Trim(header[1])
            continue
        }
        if (section != "terminal.shell")
            continue
        if (RegExMatch(trimmed, "^program\s*=\s*(?:`"([^`"]*)`"|'([^']*)')", &m))
        {
            ; Basic strings (double quotes) escape backslashes, so a Windows path
            ; arrives as C:\\Users\\...; literal strings (single quotes) do not.
            ; Unescape before launching or reporting, otherwise every path in the
            ; log and diagnostics carries doubled separators.
            program := (m[1] != "") ? UnescapeTomlBasicString(m[1]) : m[2]
            if (program != "")
                return { program: program, source: "alacritty.toml [terminal.shell]" }
            return { program: "powershell.exe", source: "default ([terminal.shell] program is empty)" }
        }
    }
    return { program: "powershell.exe", source: "default (no [terminal.shell] program in alacritty.toml)" }
}

GetConfiguredShell()
{
    return GetConfiguredShellInfo().program
}

; Undoes the escapes that matter for a shell path in a TOML basic string:
; `\\` (every Windows separator) and `\"`. Other escapes cannot appear in a
; valid executable path, so they are left untouched rather than guessed at.
UnescapeTomlBasicString(value)
{
    value := StrReplace(value, "\\", "\")
    return StrReplace(value, "\`"", "`"")
}

; Helper: Pure merge of QUAKE_SHOW_HELP/u into WSLENV, preserving an existing value.
; If existing is empty, returns QUAKE_SHOW_HELP/u.
; If QUAKE_SHOW_HELP or QUAKE_SHOW_HELP/ is already present, returns existing unchanged.
; Otherwise appends :QUAKE_SHOW_HELP/u (omitting the extra colon if existing already ends with :).
BuildWslEnv(existing)
{
    if (existing == "")
        return "QUAKE_SHOW_HELP/u"

    for part in StrSplit(existing, ":")
    {
        lowerPart := StrLower(part)
        if (lowerPart == "quake_show_help" || InStr(lowerPart, "quake_show_help/") == 1)
            return existing
    }

    if (SubStr(existing, -1) == ":")
        return existing . "QUAKE_SHOW_HELP/u"
    return existing . ":" . "QUAKE_SHOW_HELP/u"
}

; Backward-compatible alias
GetDefaultShell()
{
    return GetConfiguredShell()
}

; Helper: Checks if the configured shell executable is PowerShell (pwsh or powershell)
IsPowerShell(shellProg)
{
    return (InStr(shellProg, "pwsh") || InStr(shellProg, "powershell"))
}

; Helper: Resolves the starting working directory for terminal windows
GetStartingDirectory()
{
    global g_StartingDirectory
    targetDir := Trim(g_StartingDirectory)

    ; Empty, "~", or default maps to user home
    if (targetDir == "" || targetDir == "~")
    {
        userHome := EnvGet("USERPROFILE")
        return (userHome != "" && DirExist(userHome)) ? userHome : A_WorkingDir
    }

    ; Expand environment variables (e.g. %USERPROFILE%\repos)
    if InStr(targetDir, "%")
    {
        size := DllCall("ExpandEnvironmentStrings", "Str", targetDir, "Ptr", 0, "UInt", 0)
        if (size > 0)
        {
            buf := Buffer(size * 2)
            DllCall("ExpandEnvironmentStrings", "Str", targetDir, "Ptr", buf, "UInt", size)
            targetDir := StrGet(buf)
        }
    }

    ; Expand leading ~ to %USERPROFILE% (e.g. ~/repos or ~\repos)
    if (SubStr(targetDir, 1, 2) == "~\" || SubStr(targetDir, 1, 2) == "~/")
    {
        userHome := EnvGet("USERPROFILE")
        if (userHome != "")
            targetDir := userHome . SubStr(targetDir, 2)
    }

    if (DirExist(targetDir))
        return targetDir

    ; Fallback to user home if custom directory doesn't exist
    userHome := EnvGet("USERPROFILE")
    return (userHome != "" && DirExist(userHome)) ? userHome : A_WorkingDir
}

; -------------------------------------------------------------
; Terminal Executable Resolution
; -------------------------------------------------------------
; The installer can be started before Alacritty exists, so this process may
; inherit a PATH that does not contain the newly installed directory yet. Never
; launch a bare "alacritty.exe": resolve the real file once (optional config.ini
; override -> PATH -> standard install locations), cache it for the session, and
; re-resolve only after a launch actually fails.
ResolveAlacrittyExecutable(force := false)
{
    global g_AlacrittyExe, g_AlacrittyConfiguredPath

    if (!force && g_AlacrittyExe != "" && FileExist(g_AlacrittyExe))
        return g_AlacrittyExe

    ; 1. Explicit override: [General] AlacrittyPath in config.ini
    candidate := ResolveAlacrittyFile(ExpandEnvVariables(g_AlacrittyConfiguredPath))
    if (candidate != "")
    {
        g_AlacrittyExe := candidate
        return candidate
    }

    ; 2. PATH inherited from this process (Explorer, Startup shortcut, terminal)
    pathValue := EnvGet("PATH")
    if (pathValue != "")
    {
        for dir in StrSplit(pathValue, ";")
        {
            dir := Trim(dir)
            if (dir == "")
                continue
            if (SubStr(dir, 1, 1) == '"' && SubStr(dir, -1) == '"')
                dir := SubStr(dir, 2, -1)
            candidate := ResolveAlacrittyFile(dir . "\alacritty.exe")
            if (candidate != "")
            {
                g_AlacrittyExe := candidate
                return candidate
            }
        }
    }

    ; 3. Standard install locations (winget MSI and per-user installs)
    standardDirs := []
    localAppData := EnvGet("LOCALAPPDATA")
    if (localAppData != "")
        standardDirs.Push(localAppData . "\Programs\Alacritty")
    programFiles := EnvGet("ProgramFiles")
    if (programFiles != "")
        standardDirs.Push(programFiles . "\Alacritty")
    for dir in standardDirs
    {
        candidate := ResolveAlacrittyFile(dir . "\alacritty.exe")
        if (candidate != "")
        {
            g_AlacrittyExe := candidate
            return candidate
        }
    }

    g_AlacrittyExe := ""
    return ""
}

; Returns the path only for an existing file: directories, broken links and
; empty values are rejected so a bad override cannot shadow a valid PATH hit.
ResolveAlacrittyFile(candidate)
{
    if (candidate == "")
        return ""
    attr := FileExist(candidate)
    if (attr == "" || InStr(attr, "D"))
        return ""
    return candidate
}

; Expands %VAR% references in a configured path.
ExpandEnvVariables(value)
{
    if (value == "" || !InStr(value, "%"))
        return value
    size := DllCall("ExpandEnvironmentStrings", "Str", value, "Ptr", 0, "UInt", 0)
    if (size <= 0)
        return value
    buf := Buffer(size * 2)
    DllCall("ExpandEnvironmentStrings", "Str", value, "Ptr", buf, "UInt", size)
    return StrGet(buf)
}

; Launches Alacritty with an optional argument suffix. Returns false after a
; single re-resolve attempt and one clear dialog, instead of letting AutoHotkey
; raise its generic "Failed attempt to launch program or document" error.
LaunchAlacritty(args := "", workingDir := "")
{
    exePath := ResolveAlacrittyExecutable()
    if (exePath != "" && TryRunAlacritty(exePath, args, workingDir))
        return true

    ; The cached path may be stale (removed, moved or reinstalled elsewhere).
    exePath := ResolveAlacrittyExecutable(true)
    if (exePath != "" && TryRunAlacritty(exePath, args, workingDir))
        return true

    ShowAlacrittyNotFoundMessage()
    return false
}

TryRunAlacritty(exePath, args, workingDir)
{
    commandLine := '"' . exePath . '"'
    if (args != "")
        commandLine .= " " . args
    try {
        if (workingDir != "")
            Run(commandLine, workingDir)
        else
            Run(commandLine)
        return true
    } catch {
        return false
    }
}

; Actionable replacement for the AHK crash dialog. One message covers the
; first-run case (PATH not yet visible to this process), a missing install and
; a moved portable install.
ShowAlacrittyNotFoundMessage()
{
    global g_ConfigFile
    configHint := (g_ConfigFile != "") ? g_ConfigFile : "%APPDATA%\alacritty\config.ini"
    message := "Quake Alacritty could not find alacritty.exe.`n`n"
    message .= "If Alacritty was installed moments ago, log out or restart Windows once so the updated PATH reaches AutoHotkey. After signing in, start Quake Alacritty again (the Startup shortcut does this automatically) and press the toggle hotkey. You do not need to re-run the installer.`n`n"
    message .= "Otherwise install it with:`n    winget install -e --id Alacritty.Alacritty`n`n"
    message .= "If Alacritty is installed in a custom folder, add this line to " . configHint . ":`n    AlacrittyPath=C:\full\path\to\alacritty.exe`nand reload the script."
    MsgBox(message, "Quake Alacritty", "Icon!")
}

; Helper: Launches an Alacritty process, injecting welcome cheat sheet if configured and shell is PowerShell
LaunchTerminalProcess()
{
    global g_ShowHelpOnStart, g_FirstRun
    startDir := GetStartingDirectory()
    shouldShowHelp := (g_ShowHelpOnStart == "tip" || g_ShowHelpOnStart == "banner") || (g_ShowHelpOnStart == "first-run" && g_FirstRun)

    if (shouldShowHelp)
    {
        configuredShell := GetConfiguredShell()
        if (IsPowerShell(configuredShell))
        {
            welcomeScript := ""
            if FileExist(A_ScriptDir . "\welcome.ps1")
                welcomeScript := A_ScriptDir . "\welcome.ps1"
            else if FileExist(EnvGet("APPDATA") . "\alacritty\welcome.ps1")
                welcomeScript := EnvGet("APPDATA") . "\alacritty\welcome.ps1"

            if (welcomeScript != "")
            {
                argFlag := (g_ShowHelpOnStart == "tip") ? " -TipOnly -Startup" : " -Startup"
                ; Quote the shell: a custom install such as
                ; "C:\Program Files\PowerShell\7\pwsh.exe" used to split at the
                ; first space and fail.
                launchArgs := Format('-e "{1}" -NoLogo -NoExit -ExecutionPolicy Bypass -File "{2}"{3}', configuredShell, welcomeScript, argFlag)
                if (!LaunchAlacritty(launchArgs, startDir))
                    return false

                ; FirstRun is a first-*launch* flag, not a first-use-of-the-mode
                ; flag: the first successful launch consumes it whatever
                ; ShowHelpOnStart is, which is what the docs have always said.
                if (g_FirstRun)
                    MarkFirstRunConsumed()
                return true
            }
        }
    }

    ; For non-PowerShell shells (Git Bash, WSL), pass help mode via environment variable
    helpMode := shouldShowHelp ? ((g_ShowHelpOnStart == "first-run") ? "tip" : g_ShowHelpOnStart) : "none"
    EnvSet("QUAKE_SHOW_HELP", helpMode)

    shellForEnv := GetConfiguredShellInfo().program
    if (InStr(StrLower(shellForEnv), "wsl"))
        EnvSet("WSLENV", BuildWslEnv(EnvGet("WSLENV")))

    if (!LaunchAlacritty("", startDir))
        return false

    ; Clean first-run flag only after the terminal actually started. The flag is
    ; consumed via a marker file: IniWrite would rewrite the UTF-8 config in the
    ; ANSI code page and mangle non-ASCII comments.
    if (g_FirstRun)
        MarkFirstRunConsumed()

    return true
}

; Helper: Spawns the initial terminal window on target monitor (handling welcome banner if configured)
LaunchNewTerminal(targetMon)
{
    global g_MultiMonitorMode, g_MonitorWindows
    oldWindows := GetAlacrittyWindows()

    if (!LaunchTerminalProcess())
        return

    firstHwnd := 0
    ; Adaptive polling: tile immediately once window appears (up to 1.5s cold start)
    Loop 75 {
        Sleep 20
        currentWindows := GetAlacrittyWindows()
        if (currentWindows.Length > oldWindows.Length)
        {
            for hwnd in currentWindows
            {
                isOld := false
                for oldH in oldWindows
                {
                    if (hwnd == oldH)
                    {
                        isOld := true
                        break
                    }
                }
                if (!isOld)
                {
                    firstHwnd := hwnd
                    break
                }
            }
            if (firstHwnd)
                break
        }
    }

    if (g_MultiMonitorMode == "isolated" && firstHwnd && WinExist("ahk_id " firstHwnd))
    {
        if (!g_MonitorWindows.Has(targetMon))
            g_MonitorWindows[targetMon] := []
        g_MonitorWindows[targetMon].Push(firstHwnd)
    }

    if (firstHwnd && WinExist("ahk_id " firstHwnd))
    {
        TileAlacritty(targetMon)
        try WinActivate("ahk_id " firstHwnd)
    }
    else
    {
        TileAlacritty(targetMon)
    }
}

; -------------------------------------------------------------
; Focus Handoff on Visor Hide
; -------------------------------------------------------------

; Helper: True when the given HWND belongs to a terminal pane
IsAlacrittyWindow(hwnd)
{
    if (!hwnd || !WinExist("ahk_id " hwnd))
        return false
    try {
        return (WinGetProcessName("ahk_id " hwnd) = "alacritty.exe")
    } catch {
        return false
    }
}

; Helper: True for desktop/shell surfaces and cloaked UWP windows
IsShellOrCloakedWindow(hwnd)
{
    cls := ""
    try {
        cls := WinGetClass("ahk_id " hwnd)
    } catch {
        cls := ""
    }
    if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd")
        return true

    cloaked := 0
    try {
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "UInt*", &cloaked, "UInt", 4)
    } catch {
        cloaked := 0
    }
    return cloaked != 0
}

; Helper: Remembers the last non-visor foreground window as the hide target
CaptureVisorReturnWindow()
{
    global g_VisorReturnHwnd

    fg := WinActive("A")
    if (!fg || IsAlacrittyWindow(fg) || IsShellOrCloakedWindow(fg))
        return
    g_VisorReturnHwnd := fg
}

; Helper: Membership test that works on HWND arrays
ContainsHwnd(hwndList, hwnd)
{
    if (!hwnd)
        return false
    for item in hwndList
    {
        if (item == hwnd)
            return true
    }
    return false
}

; Helper: Filters candidate windows for the Z-order fallback beneath the visor
IsReturnCandidate(hwnd, excluded)
{
    if (!hwnd || IsAlacrittyWindow(hwnd))
        return false
    if (ContainsHwnd(excluded, hwnd))
        return false

    try {
        if (!DllCall("IsWindowVisible", "Ptr", hwnd))
            return false
        if (WinGetMinMax("ahk_id " hwnd) == -1)             ; minimized
            return false
        if (WinGetExStyle("ahk_id " hwnd) & 0x80)           ; WS_EX_TOOLWINDOW
            return false
        if (WinGetExStyle("ahk_id " hwnd) & 0x08000000)     ; WS_EX_NOACTIVATE
            return false
        if (DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")) ; GW_OWNER
            return false
        if (IsShellOrCloakedWindow(hwnd))
            return false
    } catch {
        return false
    }

    return true
}

; Helper: First usable window in Z-order (visually beneath the visor)
FindReturnWindowUnderVisor(excluded)
{
    for hwnd in WinGetList()
    {
        if (IsReturnCandidate(hwnd, excluded))
            return hwnd
    }
    return 0
}

; Helper: Resolves where focus should go when the visor is hidden
ResolveVisorReturnWindow(excluded)
{
    global g_VisorReturnHwnd

    if (g_VisorReturnHwnd && IsReturnCandidate(g_VisorReturnHwnd, excluded))
        return g_VisorReturnHwnd
    return FindReturnWindowUnderVisor(excluded)
}

; Helper: Forces a window to the foreground, with an undocumented fallback
ActivateReturnWindow(hwnd)
{
    if (!hwnd || !WinExist("ahk_id " hwnd))
        return false

    try WinActivate("ahk_id " hwnd)
    if (WinActive("A") == hwnd)
        return true

    ; SetForegroundWindow can be refused; SwitchToThisWindow bypasses the lock
    try DllCall("SwitchToThisWindow", "Ptr", hwnd, "Int", 1)
    return (WinActive("A") == hwnd)
}

; Helper: Hides every visor pane and releases keyboard focus from the visor
HideVisorAndReturnFocus(visorWindows, mon)
{
    global g_VisorReturnHwnd

    ; Only reclaim focus when one of the panes being hidden owns it. If the user
    ; switched to another app while the visor was open, leave their focus alone.
    reclaimFocus := ContainsHwnd(visorWindows, WinActive("A"))

    target := reclaimFocus ? ResolveVisorReturnWindow(visorWindows) : 0

    ; Leave the visor before hiding it: ShowWindow(SW_HIDE) does not send
    ; WM_ACTIVATE, so a hidden foreground window keeps receiving keystrokes.
    if (target)
        try WinActivate("ahk_id " target)

    for hwnd in visorWindows
        try WinHide("ahk_id " hwnd)
    ClearDividers(mon)

    if (!reclaimFocus)
        return

    if (target && ActivateReturnWindow(target))
    {
        g_VisorReturnHwnd := 0
        return
    }

    ; Target is stale (closed/minimized while open) or activation was refused
    if (ContainsHwnd(visorWindows, WinActive("A")))
        ActivateReturnWindow(FindReturnWindowUnderVisor(visorWindows))
    g_VisorReturnHwnd := 0
}

; Toggles the terminal visor on the display containing the mouse cursor
ToggleVisor()
{
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder, g_LayoutLock
    DetectHiddenWindows true

    ; Advisory background check: reads a local cache only and never waits.
    MaybeCheckForUpdates()

    ; Detect monitor containing mouse cursor
    targetMon := GetMouseMonitor()

    ; Remember where focus must return when this visor is hidden
    CaptureVisorReturnWindow()

    if (g_MultiMonitorMode == "isolated")
    {
        SyncMonitorWindows(targetMon)

        if (!g_MonitorWindows.Has(targetMon))
            g_MonitorWindows[targetMon] := []

        monWindows := g_MonitorWindows[targetMon]

        ; Case A: No terminals on target display -> spawn initial terminal
        if (monWindows.Length == 0)
        {
            LaunchNewTerminal(targetMon)
            return
        }

        ; Case B: Terminals exist on target display -> check visibility
        anyVisible := false
        for hwnd in monWindows
        {
            if DllCall("IsWindowVisible", "Ptr", hwnd)
            {
                anyVisible := true
                break
            }
        }

        if (anyVisible)
        {
            ; Hide all terminals on this display and hand focus back
            HideVisorAndReturnFocus(monWindows, targetMon)
        }
        else
        {
            ; Show and tile terminals on this display
            TileAlacritty(targetMon)
            if (monWindows.Length > 0 && WinExist("ahk_id " monWindows[1]))
                try WinActivate("ahk_id " monWindows[1])
        }
        return
    }

    ; --- Hopping mode legacy behavior ---
    windows := GetAlacrittyWindows()

    ; If none are running, launch initial terminal
    if (windows.Length == 0)
    {
        LaunchNewTerminal(targetMon)
        return
    }

    ; Check if ANY Alacritty window is currently visible on screen
    anyVisible := false
    for hwnd in windows
    {
        if DllCall("IsWindowVisible", "Ptr", hwnd)
        {
            anyVisible := true
            break
        }
    }

    if (anyVisible)
    {
        ; If visible on a different monitor than the mouse, move it to mouse monitor
        currentMon := GetWindowMonitor(windows[1])
        if (currentMon != 0 && currentMon != targetMon)
        {
            CaptureVisorReturnWindow()
            TileAlacritty(targetMon)
            if (windows.Length > 0 && WinExist("ahk_id " windows[1]))
                try WinActivate("ahk_id " windows[1])
            return
        }

        ; If already showing on the mouse monitor -> hide all and return focus
        HideVisorAndReturnFocus(windows, 0)
    }
    else
    {
        ; If tucked away -> show, tile on mouse screen, and focus
        TileAlacritty(targetMon)
        if (windows.Length > 0 && WinExist("ahk_id " windows[1]))
            try WinActivate("ahk_id " windows[1])
    }
}

; Spawns a new split terminal, dynamically re-tiles into grid, and shifts focus to the new split
SpawnSplit()
{
    global g_AlacrittyOrder, g_TwoPaneLayout, g_TileLayout, g_SinglePaneSide
    global g_MultiMonitorMode, g_MonitorWindows

    activeHwnd := WinActive("A")
    targetMon := activeHwnd ? GetWindowMonitor(activeHwnd) : 0
    if (targetMon == 0)
        targetMon := GetMouseMonitor()

    if (g_MultiMonitorMode == "isolated")
    {
        SyncMonitorWindows(targetMon)
        if (!g_MonitorWindows.Has(targetMon))
            g_MonitorWindows[targetMon] := []

        monWindows := g_MonitorWindows[targetMon]
        oldCount := monWindows.Length
    }
    else
    {
        oldWindows := GetAlacrittyWindows()
        oldCount := oldWindows.Length
    }

    allBefore := GetAlacrittyWindows()
    if (!LaunchTerminalProcess())
        return

    newHwnd := 0
    ; Adaptive polling: tile immediately once new window appears (up to 750ms max)
    Loop 50 {
        Sleep 15
        allNow := GetAlacrittyWindows()
        if (allNow.Length > allBefore.Length)
        {
            for hwnd in allNow
            {
                isOld := false
                for oldH in allBefore
                {
                    if (hwnd == oldH)
                    {
                        isOld := true
                        break
                    }
                }
                if (!isOld)
                {
                    newHwnd := hwnd
                    break
                }
            }
            if (newHwnd)
                break
        }
    }

    if (g_MultiMonitorMode == "isolated")
    {
        if (newHwnd && WinExist("ahk_id " newHwnd))
            g_MonitorWindows[targetMon].Push(newHwnd)

        ; Handle dynamic transitions for target display
        curTP := GetMonTwoPaneLayout(targetMon)
        curTL := GetMonTileLayout(targetMon)
        curSP := GetMonSinglePaneSide(targetMon)

        if (oldCount == 1 && newHwnd)
        {
            ; 1 -> 2 panes:
            if (curSP == "left")
            {
                SetMonTwoPaneLayout(targetMon, "left-stacked")
                SetMonSinglePaneSide(targetMon, "")
            }
            else if (curSP == "right")
            {
                SetMonTwoPaneLayout(targetMon, "right-stacked")
                SetMonSinglePaneSide(targetMon, "")
            }
        }
        else if (oldCount == 2 && newHwnd)
        {
            ; 2 -> 3 panes:
            if (curTP == "left-stacked")
            {
                SetMonTileLayout(targetMon, "right")
                if (monWindows.Length >= 2)
                    g_MonitorWindows[targetMon] := [monWindows[1], newHwnd, monWindows[2]]
            }
            else if (curTP == "right-stacked")
            {
                SetMonTileLayout(targetMon, "left")
                if (monWindows.Length >= 2)
                    g_MonitorWindows[targetMon] := [newHwnd, monWindows[1], monWindows[2]]
            }
            else if (curTP == "top-bottom")
            {
                SetMonTileLayout(targetMon, "top")
                if (monWindows.Length >= 2)
                    g_MonitorWindows[targetMon] := [monWindows[1], monWindows[2], newHwnd]
            }
        }

        TileAlacritty(targetMon)

        if (newHwnd && WinExist("ahk_id " newHwnd))
        {
            try WinActivate("ahk_id " newHwnd)
        }
        else if (g_MonitorWindows[targetMon].Length > oldCount && WinExist("ahk_id " g_MonitorWindows[targetMon][g_MonitorWindows[targetMon].Length]))
        {
            try WinActivate("ahk_id " g_MonitorWindows[targetMon][g_MonitorWindows[targetMon].Length])
        }
    }
    else
    {
        ; Hopping mode transitions
        if (oldCount == 1 && newHwnd)
        {
            if (g_SinglePaneSide == "left")
            {
                g_TwoPaneLayout := "left-stacked"
                g_SinglePaneSide := ""
            }
            else if (g_SinglePaneSide == "right")
            {
                g_TwoPaneLayout := "right-stacked"
                g_SinglePaneSide := ""
            }
        }
        else if (oldCount == 2 && newHwnd)
        {
            if (g_TwoPaneLayout == "left-stacked")
            {
                g_TileLayout := "right"
                if (allBefore.Length >= 2)
                    g_AlacrittyOrder := [allBefore[1], newHwnd, allBefore[2]]
            }
            else if (g_TwoPaneLayout == "right-stacked")
            {
                g_TileLayout := "left"
                if (allBefore.Length >= 2)
                    g_AlacrittyOrder := [newHwnd, allBefore[1], allBefore[2]]
            }
            else if (g_TwoPaneLayout == "top-bottom")
            {
                g_TileLayout := "top"
                if (allBefore.Length >= 2)
                    g_AlacrittyOrder := [allBefore[1], allBefore[2], newHwnd]
            }
        }

        TileAlacritty(targetMon)

        if (newHwnd && WinExist("ahk_id " newHwnd))
        {
            try WinActivate("ahk_id " newHwnd)
        }
        else if (g_AlacrittyOrder.Length > oldCount && WinExist("ahk_id " g_AlacrittyOrder[g_AlacrittyOrder.Length]))
        {
            try WinActivate("ahk_id " g_AlacrittyOrder[g_AlacrittyOrder.Length])
        }
    }
}

; Closes focused window and auto-rebalances remaining windows
CloseSplit()
{
    global g_TwoPaneLayout, g_TileLayout, g_SinglePaneSide
    global g_MultiMonitorMode, g_MonitorWindows, g_LayoutLock

    g_LayoutLock++
    try
    {
        activeHwnd := WinActive("A")
        if (!activeHwnd)
            return

        targetMon := GetWindowMonitor(activeHwnd)
        if (targetMon == 0)
            targetMon := GetMouseMonitor()

        if (g_MultiMonitorMode == "isolated")
        {
            SyncMonitorWindows(targetMon)
            if (!g_MonitorWindows.Has(targetMon))
                g_MonitorWindows[targetMon] := []

            monWindows := g_MonitorWindows[targetMon]
            oldCount := monWindows.Length

            try WinClose("ahk_id " activeHwnd)
            ; Adaptive polling: re-tile immediately once window closes (up to 200ms max)
            Loop 20 {
                Sleep 10
                if (!WinExist("ahk_id " activeHwnd))
                    break
            }

            ; Remove activeHwnd from g_MonitorWindows[targetMon]
            newList := []
            for hwnd in g_MonitorWindows[targetMon]
            {
                if (hwnd != activeHwnd && WinExist("ahk_id " hwnd))
                    newList.Push(hwnd)
            }
            g_MonitorWindows[targetMon] := newList

            curTP := GetMonTwoPaneLayout(targetMon)
            curTL := GetMonTileLayout(targetMon)

            ; Handle dynamic transitions when closing panes:
            if (oldCount == 2)
            {
                if (curTP == "left-stacked")
                    SetMonSinglePaneSide(targetMon, "left")
                else if (curTP == "right-stacked")
                    SetMonSinglePaneSide(targetMon, "right")
                else
                    SetMonSinglePaneSide(targetMon, "")
            }
            else if (oldCount == 3)
            {
                if (curTL == "right")
                    SetMonTwoPaneLayout(targetMon, "left-stacked")
                else if (curTL == "left")
                    SetMonTwoPaneLayout(targetMon, "right-stacked")
                else if (curTL == "top" || curTL == "bottom")
                    SetMonTwoPaneLayout(targetMon, "top-bottom")
            }

            if (g_MonitorWindows[targetMon].Length > 0)
            {
                TileAlacritty(targetMon)
                if (WinExist("ahk_id " g_MonitorWindows[targetMon][g_MonitorWindows[targetMon].Length]))
                    try WinActivate("ahk_id " g_MonitorWindows[targetMon][g_MonitorWindows[targetMon].Length])
            }
            else
            {
                ClearDividers(targetMon)
            }
        }
        else
        {
            oldWindows := GetAlacrittyWindows()
            oldCount := oldWindows.Length

            try WinClose("ahk_id " activeHwnd)
            Loop 20 {
                Sleep 10
                if (!WinExist("ahk_id " activeHwnd))
                    break
            }

            if (oldCount == 2)
            {
                if (g_TwoPaneLayout == "left-stacked")
                    g_SinglePaneSide := "left"
                else if (g_TwoPaneLayout == "right-stacked")
                    g_SinglePaneSide := "right"
                else
                    g_SinglePaneSide := ""
            }
            else if (oldCount == 3)
            {
                if (g_TileLayout == "right")
                    g_TwoPaneLayout := "left-stacked"
                else if (g_TileLayout == "left")
                    g_TwoPaneLayout := "right-stacked"
                else if (g_TileLayout == "top" || g_TileLayout == "bottom")
                    g_TwoPaneLayout := "top-bottom"
            }

            newWindows := GetAlacrittyWindows()
            if (newWindows.Length > 0)
            {
                TileAlacritty()
                if (WinExist("ahk_id " newWindows[newWindows.Length]))
                    try WinActivate("ahk_id " newWindows[newWindows.Length])
            }
            else
            {
                ClearDividers(0)
            }
        }
    }
    finally
    {
        g_LayoutLock--
    }
}

; -------------------------------------------------------------
; Topology Safety: Display Changes & Disconnect Migration
; -------------------------------------------------------------

; Handler for WM_DISPLAYCHANGE (0x007E)
OnDisplayChange(wParam, lParam, msg, hwnd)
{
    ; Debounce by 500ms to allow Windows display subsystem to fully stabilize
    SetTimer(HandleDisplayChange, -500)
}

; Safely migrates orphaned terminal windows from disconnected monitors to primary display
HandleDisplayChange()
{
    global g_MultiMonitorMode, g_MonitorWindows, g_MonitorDividers
    if (g_MultiMonitorMode != "isolated")
        return

    monCount := MonitorGetCount()
    primaryMon := MonitorGetPrimary()

    ; 1. Sync live windows to purge any closed ones
    SyncMonitorWindows()

    ; 2. Identify any windows belonging to monitor IDs that no longer exist
    migratedWindows := []
    invalidMons := []

    for monId, winList in g_MonitorWindows
    {
        if (monId > monCount || monId < 1)
        {
            for hwnd in winList
            {
                if (WinExist("ahk_id " hwnd))
                    migratedWindows.Push(hwnd)
            }
            invalidMons.Push(monId)
        }
    }

    ; Clear invalid monitors and their dividers
    for monId in invalidMons
    {
        ClearDividers(monId)
        g_MonitorWindows.Delete(monId)
        if (g_MonitorDividers.Has(monId))
            g_MonitorDividers.Delete(monId)
    }

    ; A disconnect is worth a log line even when it orphaned no live pane.
    if (invalidMons.Length > 0)
        LogWrite("WARN", "display: monitor(s) " . JoinArray(invalidMons, ",") . " disappeared; migrating " . migratedWindows.Length . " pane(s) to monitor " . primaryMon)

    ; 3. If windows need migration to primary monitor
    if (migratedWindows.Length > 0)
    {
        if (!g_MonitorWindows.Has(primaryMon))
            g_MonitorWindows[primaryMon] := []

        anyMigratedVisible := false
        for hwnd in migratedWindows
        {
            if DllCall("IsWindowVisible", "Ptr", hwnd)
                anyMigratedVisible := true
            g_MonitorWindows[primaryMon].Push(hwnd)
        }

        if (anyMigratedVisible || IsMonitorVisible(primaryMon))
        {
            TileAlacritty(primaryMon)
        }
    }

    ; 4. Check if existing valid monitors' work areas shifted and retile any visible monitors
    Loop monCount {
        monId := A_Index
        if (IsMonitorVisible(monId))
        {
            TileAlacritty(monId)
        }
    }
}

; -------------------------------------------------------------
; Watchdog: Spontaneous Window Closure & Orphan Outline Cleanup
; -------------------------------------------------------------

; Background watchdog: Periodically cleans up orphan outline dividers and
; rebalances layouts when terminal windows close externally (Alt + F4, exit, crash).
WatchdogCheck()
{
    global g_LayoutLock, g_MultiMonitorMode, g_MonitorWindows, g_MonitorDividers, g_Dividers, g_AlacrittyOrder
    DetectHiddenWindows true

    if (g_LayoutLock > 0)
        return

    ; Fast check: are any windows or dividers currently tracked?
    hasTrackedOrDividers := false
    if (g_MultiMonitorMode == "isolated")
    {
        for monId, winList in g_MonitorWindows
        {
            if (winList.Length > 0)
            {
                hasTrackedOrDividers := true
                break
            }
        }
        if (!hasTrackedOrDividers)
        {
            for monId, divList in g_MonitorDividers
            {
                if (divList.Length > 0)
                {
                    hasTrackedOrDividers := true
                    break
                }
            }
        }
    }
    else
    {
        hasTrackedOrDividers := (g_AlacrittyOrder.Length > 0 || g_Dividers.Length > 0)
    }

    if (!hasTrackedOrDividers)
        return

    ; 1. Global safety: If no real Alacritty windows exist anywhere on the system,
    ;    purge all dividers immediately and reset tracking arrays.
    allWindows := GetAlacrittyWindows()
    if (allWindows.Length == 0)
    {
        ClearDividers(0)
        if (g_MultiMonitorMode == "isolated")
        {
            for monId, winList in g_MonitorWindows
                g_MonitorWindows[monId] := []
        }
        else
        {
            g_AlacrittyOrder := []
        }
        return
    }

    ; 2. Isolated mode: verify each monitor's tracked windows
    if (g_MultiMonitorMode == "isolated")
    {
        ; Clear dividers on any monitor that has zero tracked windows
        orphanMons := []
        for monId, divList in g_MonitorDividers
        {
            if (divList.Length > 0 && (!g_MonitorWindows.Has(monId) || g_MonitorWindows[monId].Length == 0))
                orphanMons.Push(monId)
        }
        for monId in orphanMons
            ClearDividers(monId)

        for monId, winList in g_MonitorWindows
        {
            if (winList.Length == 0)
                continue

            aliveList := []
            for hwnd in winList
            {
                if (WinExist("ahk_id " hwnd))
                    aliveList.Push(hwnd)
            }

            ; Detect if one or more windows closed spontaneously
            if (aliveList.Length < winList.Length)
            {
                ; Focus guard: reclaim focus only when this monitor's visor already
                ; owned it (the same rule HideVisorAndReturnFocus applies). A pane
                ; exiting in a background visor must not pull the user out of
                ; whatever app they switched to. Tested against the pre-close list
                ; because the dying hwnd is usually gone by the time this runs, and
                ; Windows may already have handed focus to a surviving pane.
                visorHadFocus := ContainsHwnd(winList, WinActive("A"))

                oldCount := winList.Length
                g_MonitorWindows[monId] := aliveList

                if (aliveList.Length == 0)
                {
                    ClearDividers(monId)
                }
                else
                {
                    ; If any remaining window is currently visible, rebalance the layout
                    anyVisible := false
                    for hwnd in aliveList
                    {
                        if DllCall("IsWindowVisible", "Ptr", hwnd)
                        {
                            anyVisible := true
                            break
                        }
                    }

                    if (anyVisible)
                    {
                        curTP := GetMonTwoPaneLayout(monId)
                        curTL := GetMonTileLayout(monId)

                        if (oldCount == 2)
                        {
                            if (curTP == "left-stacked")
                                SetMonSinglePaneSide(monId, "left")
                            else if (curTP == "right-stacked")
                                SetMonSinglePaneSide(monId, "right")
                            else
                                SetMonSinglePaneSide(monId, "")
                        }
                        else if (oldCount == 3)
                        {
                            if (curTL == "right")
                                SetMonTwoPaneLayout(monId, "left-stacked")
                            else if (curTL == "left")
                                SetMonTwoPaneLayout(monId, "right-stacked")
                            else if (curTL == "top" || curTL == "bottom")
                                SetMonTwoPaneLayout(monId, "top-bottom")
                        }

                        TileAlacritty(monId)
                        if (visorHadFocus && aliveList.Length > 0 && WinExist("ahk_id " aliveList[aliveList.Length]))
                            WinActivate("ahk_id " aliveList[aliveList.Length])
                    }
                    else
                    {
                        ClearDividers(monId)
                    }
                }
            }
        }
    }
    else ; 3. Hopping mode verification
    {
        if (g_Dividers.Length > 0 && g_AlacrittyOrder.Length == 0)
            ClearDividers(0)

        if (g_AlacrittyOrder.Length > 0)
        {
            aliveList := []
            for hwnd in g_AlacrittyOrder
            {
                if (WinExist("ahk_id " hwnd))
                    aliveList.Push(hwnd)
            }

            if (aliveList.Length < g_AlacrittyOrder.Length)
            {
                ; Focus guard: see the isolated-mode branch above. Hopping mode
                ; only ever has one visor, so the pool itself is the ownership test.
                visorHadFocus := ContainsHwnd(g_AlacrittyOrder, WinActive("A"))

                oldCount := g_AlacrittyOrder.Length
                g_AlacrittyOrder := aliveList

                if (aliveList.Length == 0)
                {
                    ClearDividers(0)
                }
                else
                {
                    anyVisible := false
                    for hwnd in aliveList
                    {
                        if DllCall("IsWindowVisible", "Ptr", hwnd)
                        {
                            anyVisible := true
                            break
                        }
                    }

                    if (anyVisible)
                    {
                        if (oldCount == 2)
                        {
                            if (g_TwoPaneLayout == "left-stacked")
                                g_SinglePaneSide := "left"
                            else if (g_TwoPaneLayout == "right-stacked")
                                g_SinglePaneSide := "right"
                            else
                                g_SinglePaneSide := ""
                        }
                        else if (oldCount == 3)
                        {
                            if (g_TileLayout == "right")
                                g_TwoPaneLayout := "left-stacked"
                            else if (g_TileLayout == "left")
                                g_TwoPaneLayout := "right-stacked"
                            else if (g_TileLayout == "top" || g_TileLayout == "bottom")
                                g_TwoPaneLayout := "top-bottom"
                        }

                        TileAlacritty()
                        if (visorHadFocus && aliveList.Length > 0 && WinExist("ahk_id " aliveList[aliveList.Length]))
                            WinActivate("ahk_id " aliveList[aliveList.Length])
                    }
                    else
                    {
                        ClearDividers(0)
                    }
                }
            }
        }
    }
}

; Configures the system notification area (tray) context menu
SetupTrayMenu()
{
    global g_ConfigWarnings, g_BindingFailures
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Quake Alacritty v" . g_AppVersion, (*) => Run("https://github.com/orgNero/quake-alacritty"))
    tray.Disable("Quake Alacritty v" . g_AppVersion)
    tray.Add()
    tray.Add("Report Bug / Request Feature", (*) => Run("https://github.com/orgNero/quake-alacritty/issues/new/choose"))
    tray.Add("Documentation & Shortcuts", (*) => Run("https://github.com/orgNero/quake-alacritty#readme"))
    tray.Add()
    tray.Add("Open log", (*) => OpenLogFile())
    tray.Add("Copy diagnostics", (*) => CopyDiagnostics())
    problemCount := g_ConfigWarnings.Length + g_BindingFailures.Length
    if (problemCount)
    {
        tray.Add()
        tray.Add("Config warnings (" . problemCount . ")", (*) => ShowConfigWarnings())
    }
    tray.Add()
    tray.Add("Reload Quake Alacritty", (*) => Reload())
    tray.Add("Exit", (*) => ExitApp())
}

; Opens quake.log in Notepad. The default handler for .log is not guaranteed, and
; the log must always be reachable when something goes wrong.
OpenLogFile()
{
    global g_LogPath
    if (g_LogPath == "" || !FileExist(g_LogPath))
    {
        MsgBox("No log file yet.`n`nThe log is written to " . g_LogPath . " as soon as the visor starts.", "Quake Alacritty", "Iconi")
        return
    }
    try Run('notepad.exe "' . g_LogPath . '"')
    catch as err
        MsgBox("Could not open " . g_LogPath . ":`n`n" . err.Message, "Quake Alacritty", "Icon!")
}

; Copies a support report to the clipboard. Personal paths are replaced with
; %APPDATA% / %USERPROFILE% so the text can be pasted into a public issue.
CopyDiagnostics()
{
    ; Building the report reads the log and enumerates windows; a diagnostics
    ; command must never raise its own error dialog.
    try {
        text := BuildDiagnosticsText()
        A_Clipboard := text
        TrayTip("Diagnostics copied to the clipboard. Personal paths were shortened.", "Quake Alacritty", "Iconi Mute")
    } catch as err {
        MsgBox("Could not copy diagnostics:`n`n" . err.Message, "Quake Alacritty", "Icon!")
    }
}

BuildDiagnosticsText()
{
    global g_AppVersion, g_ConfigFile, g_LogPath, g_ConfigWarnings, g_BindingFailures
    global g_MultiMonitorMode, g_ShowHelpOnStart, g_FirstRun

    lines := []
    lines.Push("Quake Alacritty v" . g_AppVersion)
    lines.Push("AutoHotkey " . A_AhkVersion . (A_Is64bitOS ? " (64-bit OS)" : " (32-bit OS)"))
    lines.Push("Windows " . A_OSVersion)
    lines.Push("Mode: " . g_MultiMonitorMode . "; ShowHelpOnStart=" . g_ShowHelpOnStart . "; FirstRun pending=" . (g_FirstRun ? "yes" : "no"))
    lines.Push("Shell: " . GetConfiguredShell())
    lines.Push("Panes: " . GetAlacrittyWindows().Length . " window(s)")
    lines.Push("Monitors: " . MonitorGetCount())
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        suffix := (A_Index == MonitorGetPrimary()) ? " (primary)" : ""
        lines.Push("  #" . A_Index . ": " . (r - l) . "x" . (b - t) . " at " . l . "," . t . suffix)
    }
    lines.Push("Config: " . ScrubDiagnosticPath(g_ConfigFile))
    lines.Push("Log: " . ScrubDiagnosticPath(g_LogPath))

    if (g_ConfigWarnings.Length || g_BindingFailures.Length)
    {
        lines.Push("")
        lines.Push("Config problems:")
        for warning in g_ConfigWarnings
            lines.Push("  - " . warning)
        for failure in g_BindingFailures
            lines.Push("  - Hotkey " . failure)
    }

    tail := ReadLogTail(40)
    if (tail.Length)
    {
        lines.Push("")
        lines.Push("Last " . tail.Length . " log line(s):")
        for line in tail
            lines.Push("  " . ScrubDiagnosticPath(line))
    }

    return JoinArray(lines, "`r`n")
}

; Shortens personal paths for public issue text. Tokens, not deletions, so the
; report still says where a file lives.
ScrubDiagnosticPath(text)
{
    if (text == "")
        return text
    for envName in ["APPDATA", "USERPROFILE", "LOCALAPPDATA"]
    {
        value := EnvGet(envName)
        if (value != "")
            text := StrReplace(text, value, "%" . envName . "%")
    }
    return text
}

ReadLogTail(maxLines)
{
    global g_LogPath
    if (g_LogPath == "" || !FileExist(g_LogPath))
        return []
    try {
        text := FileRead(g_LogPath, "UTF-8")
    } catch {
        return []
    }
    lines := StrSplit(text, "`n", "`r")
    while (lines.Length && Trim(lines[lines.Length]) == "")
        lines.Pop()
    if (lines.Length > maxLines)
        lines.RemoveAt(1, lines.Length - maxLines)
    return lines
}

; Reads the deployed VERSION marker (repo or %APPDATA%\alacritty) so the version
; is never duplicated as a hardcoded constant in this script.
ReadAppVersion()
{
    global g_AppVersion
    versionPath := A_ScriptDir . "\VERSION"
    if (!FileExist(versionPath))
        return
    try {
        raw := Trim(FileRead(versionPath, "UTF-8"))
        if RegExMatch(raw, "^\d+\.\d+\.\d+", &m)
            g_AppVersion := m[0]
    }
}

; Parses CLI arguments for development/diagnostic self-test mode.
ParseSelfTestArgs()
{
    global g_SelfTest, g_SelfTestConfig
    expectConfig := false
    for arg in A_Args
    {
        if (expectConfig)
        {
            if (SubStr(arg, 1, 10) == "--selftest")
            {
                FileAppend("selftest.error=missing value for --selftest-config`n", "*")
                ExitApp(2)
            }
            g_SelfTestConfig := arg
            expectConfig := false
            continue
        }
        if (arg == "--selftest")
        {
            g_SelfTest := true
        }
        else if (arg == "--selftest-config")
        {
            expectConfig := true
        }
        else if (SubStr(arg, 1, 10) == "--selftest")
        {
            FileAppend("selftest.error=unknown flag: " . arg . "`n", "*")
            ExitApp(2)
        }
    }
    if (expectConfig)
    {
        FileAppend("selftest.error=missing value for --selftest-config`n", "*")
        ExitApp(2)
    }
}

; Helper: Emits a single key-value diagnostic line for the self-test runner.
EmitSelfTest(key, value)
{
    cleanValue := StrReplace(StrReplace(String(value), "`r", ""), "`n", "")
    FileAppend("selftest." . key . "=" . cleanValue . "`n", "*")
}

; Development/diagnostic self-test runner. Verifies configuration parsing,
; hotkey bindings, shell resolution and window discovery without side effects.
RunSelfTest()
{
    global g_AppVersion, g_ConfigFile, g_BindingFailures, g_ConfigWarnings, g_TileLayout, g_TwoPaneLayout

    LoadConfig()
    ReadAppVersion()
    RegisterHotkeys()

    EmitSelfTest("version", g_AppVersion)
    EmitSelfTest("ahk", A_AhkVersion)
    EmitSelfTest("config", g_ConfigFile)
    EmitSelfTest("monitors", MonitorGetCount())
    EmitSelfTest("windows", GetAlacrittyWindows().Length)
    EmitSelfTest("shell", GetConfiguredShellInfo().program)
    EmitSelfTest("wslenvMerged", BuildWslEnv(EnvGet("WSLENV")))
    EmitSelfTest("bindings_total", 17)
    EmitSelfTest("bindingFailures", g_BindingFailures.Length)
    EmitSelfTest("configWarnings", g_ConfigWarnings.Length)
    EmitSelfTest("tileLayout", g_TileLayout)
    EmitSelfTest("twoPaneLayout", g_TwoPaneLayout)

    ok := (g_BindingFailures.Length == 0 && g_ConfigWarnings.Length == 0) ? 1 : 0
    EmitSelfTest("ok", ok)

    ExitApp(ok == 1 ? 0 : 1)
}

; Spawns the throttled background update check. Local file reads only: the
; PowerShell child owns the network call, so startup and the visor stay
; non-blocking. Advisory only - it never applies an update.
MaybeCheckForUpdates()
{
    global g_LastUpdateCheckSpawn
    if (g_LastUpdateCheckSpawn && (A_TickCount - g_LastUpdateCheckSpawn < 300000))
        return

    checker := ""
    if FileExist(A_ScriptDir . "\update-check.ps1")
        checker := A_ScriptDir . "\update-check.ps1"
    else if FileExist(EnvGet("APPDATA") . "\alacritty\update-check.ps1")
        checker := EnvGet("APPDATA") . "\alacritty\update-check.ps1"
    if (checker == "")
    {
        LogWrite("WARN", "update-check: update-check.ps1 not found; skipping")
        return
    }

    ; Only nextCheckAtUtc is needed: fixed-width UTC digits compare correctly.
    nextCheck := ""
    cachePath := EnvGet("APPDATA") . "\alacritty\.update-check.json"
    if FileExist(cachePath)
    {
        try {
            raw := FileRead(cachePath, "UTF-8")
            if RegExMatch(raw, '"nextCheckAtUtc"\s*:\s*"(\d{14})"', &m)
                nextCheck := m[1]
        }
    }
    if (nextCheck != "" && nextCheck > A_NowUTC)
        return

    psExe := EnvGet("SystemRoot") . "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(psExe)
        psExe := "powershell.exe"

    try {
        Run('"' . psExe . '" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' . checker . '"', , "Hide")
        g_LastUpdateCheckSpawn := A_TickCount
        LogWrite("INFO", "update-check: spawned background check")
    } catch as err {
        LogWrite("WARN", "update-check: could not spawn checker: " . err.Message)
    }
}

; -------------------------------------------------------------
; Graceful Shutdown
; -------------------------------------------------------------
; Destroys seam overlays so a graceful exit (tray menu, installer upgrade,
; logoff) never leaves orphan click-through windows behind.
CleanupOnExit(ExitReason, ExitCode)
{
    try ClearDividers(0)
}

; WM_CLOSE to the script's main window (used by install.ps1 / uninstall.ps1 for a
; graceful quit handshake before the force-kill fallback) exits through OnExit.
OnCloseMessage(wParam, lParam, msg, hwnd)
{
    ExitApp()
}

; -------------------------------------------------------------
; Script Initialization
; -------------------------------------------------------------
ParseSelfTestArgs()
if (g_SelfTest)
    RunSelfTest()          ; never returns

InitLog()
LogWrite("INFO", "---- Quake Alacritty starting ----")
LoadConfig()
ReadAppVersion()
LogWrite("INFO", "start: v" . g_AppVersion . "; AutoHotkey " . A_AhkVersion . "; Windows " . A_OSVersion . "; mode=" . g_MultiMonitorMode)
shellInfo := GetConfiguredShellInfo()
shellLevel := InStr(shellInfo.source, "unreadable") ? "WARN" : "INFO"
LogWrite(shellLevel, "shell: " . shellInfo.program . " (" . shellInfo.source . ")")
RegisterHotkeys()
LogConfigProblems()
MaybeCheckForUpdates()
OnMessage(0x007E, OnDisplayChange)
OnMessage(0x0010, OnCloseMessage)
OnExit(CleanupOnExit)
A_IconTip := "Quake Alacritty v" . g_AppVersion
SetupTrayMenu()

; Report rejected config values once per start. Silence on a valid config; the
; tray keeps a "Config warnings" entry so the list stays reachable afterwards.
; Binding failures get the non-blocking report specified for them (a toast) and
; are folded into the same tray entry and log; a bad hotkey must not block
; startup behind a modal dialog.
if (g_ConfigWarnings.Length)
    ShowConfigWarnings()
if (g_BindingFailures.Length)
    TrayTip(g_BindingFailures.Length . " hotkey binding(s) failed. Tray -> Config warnings for details; the list is also in quake.log.", "Quake Alacritty", "Icon!")

; Sync any existing windows and restore layout if already visible on startup/reload
SyncMonitorWindows()
if (g_MultiMonitorMode == "isolated")
{
    Loop MonitorGetCount() {
        monId := A_Index
        if (IsMonitorVisible(monId))
            TileAlacritty(monId)
    }
}
else
{
    realWins := GetAlacrittyWindows()
    anyVis := false
    for hwnd in realWins
    {
        if DllCall("IsWindowVisible", "Ptr", hwnd)
        {
            anyVis := true
            break
        }
    }
    if (anyVis)
        TileAlacritty()
}

; Start background watchdog timer (every 250ms) to clean up orphan outlines
; and rebalance layouts when terminal windows close externally (Alt + F4, exit, crash)
SetTimer(WatchdogCheck, 250)
