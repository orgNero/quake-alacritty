#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true
DetectHiddenWindows true
SetWinDelay -1
SetControlDelay -1
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
global g_AppVersion         := "unknown"

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

; Helper: Resolves configuration file location and loads user preferences
LoadConfig()
{
    global g_ConfigFile, g_BorderGap, g_BorderColor, g_VisorHeightPercent, g_MultiMonitorMode, g_ShowHelpOnStart, g_FirstRun
    global g_TileLayout, g_TwoPaneLayout, g_KeyCycleLayout
    global g_KeyToggleVisor, g_KeySplit, g_KeyClose, g_KeyRetile
    global g_KeyFocusLeft, g_KeyFocusRight, g_KeyFocusUp, g_KeyFocusDown
    global g_KeySwapLeft, g_KeySwapRight, g_KeySwapUp, g_KeySwapDown
    global g_KeyRotate, g_KeyMoveVisorLeft, g_KeyMoveVisorRight, g_KeyReload

    ; 1. Resolve path (%APPDATA%\alacritty\config.ini or local repository)
    appDataPath := EnvGet("APPDATA") . "\alacritty\config.ini"
    localPath   := A_ScriptDir . "\config.ini"

    if FileExist(appDataPath)
        g_ConfigFile := appDataPath
    else if FileExist(localPath)
        g_ConfigFile := localPath
    else
        g_ConfigFile := appDataPath

    if (!FileExist(g_ConfigFile))
        return

    ; 2. [General]
    try {
        frVal := IniRead(g_ConfigFile, "General", "FirstRun", "false")
        g_FirstRun := (frVal = "true" || frVal = "1")
        modeVal := Trim(StrLower(IniRead(g_ConfigFile, "General", "MultiMonitorMode", "isolated")))
        if (modeVal == "hopping" || modeVal == "isolated")
            g_MultiMonitorMode := modeVal
        else
            g_MultiMonitorMode := "isolated"

        helpVal := Trim(StrLower(IniRead(g_ConfigFile, "General", "ShowHelpOnStart", "tip")))
        if (helpVal == "tip" || helpVal == "banner" || helpVal == "none" || helpVal == "first-run")
            g_ShowHelpOnStart := helpVal
        else if (helpVal == "always" || helpVal == "true" || helpVal == "1")
            g_ShowHelpOnStart := "tip"
        else if (helpVal == "false" || helpVal == "0")
            g_ShowHelpOnStart := "none"
        else
            g_ShowHelpOnStart := "tip"
    }

    ; 3. [Appearance]
    try {
        gapVal := Integer(IniRead(g_ConfigFile, "Appearance", "BorderGap", "2"))
        if (gapVal >= 0 && gapVal <= 10)
            g_BorderGap := gapVal

        colVal := Trim(IniRead(g_ConfigFile, "Appearance", "BorderColor", "38bdf8"))
        if (colVal != "")
            g_BorderColor := StrReplace(colVal, "#", "")

        vhVal := Integer(IniRead(g_ConfigFile, "Appearance", "VisorHeightPercent", "40"))
        if (vhVal >= 10 && vhVal <= 100)
            g_VisorHeightPercent := vhVal / 100.0

        tlVal := Trim(StrLower(IniRead(g_ConfigFile, "Appearance", "TileLayout", "bottom")))
        if (tlVal == "bottom" || tlVal == "top" || tlVal == "left" || tlVal == "right")
            g_TileLayout := tlVal

        tpVal := Trim(StrLower(IniRead(g_ConfigFile, "Appearance", "TwoPaneLayout", "side-by-side-visor")))
        if (tpVal == "side-by-side-visor" || tpVal == "side-by-side-full" || tpVal == "top-bottom" || tpVal == "horizontal-full" || tpVal == "horizontal" || tpVal == "left-stacked" || tpVal == "right-stacked")
            g_TwoPaneLayout := (tpVal == "horizontal-full" || tpVal == "horizontal") ? "top-bottom" : tpVal
    }

    ; 4. [Hotkeys]
    try {
        g_KeyToggleVisor := IniRead(g_ConfigFile, "Hotkeys", "ToggleVisor", g_KeyToggleVisor)
        g_KeySplit       := IniRead(g_ConfigFile, "Hotkeys", "SplitWindow", g_KeySplit)
        g_KeyClose       := IniRead(g_ConfigFile, "Hotkeys", "CloseWindow", g_KeyClose)
        g_KeyRetile      := IniRead(g_ConfigFile, "Hotkeys", "Retile", g_KeyRetile)
        g_KeyCycleLayout := IniRead(g_ConfigFile, "Hotkeys", "CycleLayout", g_KeyCycleLayout)
        g_KeyFocusLeft   := IniRead(g_ConfigFile, "Hotkeys", "FocusLeft", g_KeyFocusLeft)
        g_KeyFocusRight  := IniRead(g_ConfigFile, "Hotkeys", "FocusRight", g_KeyFocusRight)
        g_KeyFocusUp     := IniRead(g_ConfigFile, "Hotkeys", "FocusUp", g_KeyFocusUp)
        g_KeyFocusDown   := IniRead(g_ConfigFile, "Hotkeys", "FocusDown", g_KeyFocusDown)
        g_KeySwapLeft    := IniRead(g_ConfigFile, "Hotkeys", "SwapLeft", g_KeySwapLeft)
        g_KeySwapRight   := IniRead(g_ConfigFile, "Hotkeys", "SwapRight", g_KeySwapRight)
        g_KeySwapUp      := IniRead(g_ConfigFile, "Hotkeys", "SwapUp", g_KeySwapUp)
        g_KeySwapDown    := IniRead(g_ConfigFile, "Hotkeys", "SwapDown", g_KeySwapDown)
        g_KeyRotate         := IniRead(g_ConfigFile, "Hotkeys", "RotatePanes", g_KeyRotate)
        g_KeyMoveVisorLeft  := IniRead(g_ConfigFile, "Hotkeys", "MoveVisorLeft", g_KeyMoveVisorLeft)
        g_KeyMoveVisorRight := IniRead(g_ConfigFile, "Hotkeys", "MoveVisorRight", g_KeyMoveVisorRight)
        g_KeyReload      := IniRead(g_ConfigFile, "Hotkeys", "ReloadScript", g_KeyReload)
    }
}

; Helper: Binds dynamic hotkeys from configuration
RegisterHotkeys()
{
    ; Global visor toggle
    if (g_KeyToggleVisor != "")
    {
        try Hotkey(g_KeyToggleVisor, (*) => ToggleVisor())
        catch {
            try Hotkey("#sc029", (*) => ToggleVisor())
        }
    }

    ; Context-sensitive hotkeys inside Alacritty
    HotIfWinActive("ahk_exe alacritty.exe")

    RegisterKey(g_KeySplit,       (*) => SpawnSplit())
    RegisterKey(g_KeyClose,       (*) => CloseSplit())
    RegisterKey("!F4",            (*) => CloseSplit())
    RegisterKey(g_KeyRetile,      (*) => TileAlacritty())
    RegisterKey(g_KeyCycleLayout, (*) => CycleLayout())
    RegisterKey(g_KeyFocusLeft,   (*) => FocusDirection("left"))
    RegisterKey(g_KeyFocusRight,  (*) => FocusDirection("right"))
    RegisterKey(g_KeyFocusUp,     (*) => FocusDirection("up"))
    RegisterKey(g_KeyFocusDown,   (*) => FocusDirection("down"))
    RegisterKey(g_KeySwapLeft,    (*) => SwapDirection("left"))
    RegisterKey(g_KeySwapRight,   (*) => SwapDirection("right"))
    RegisterKey(g_KeySwapUp,      (*) => SwapDirection("up"))
    RegisterKey(g_KeySwapDown,    (*) => SwapDirection("down"))
    RegisterKey(g_KeyRotate,         (*) => RotateWindows())
    RegisterKey(g_KeyMoveVisorLeft,  (*) => MoveVisorDirection("left"))
    RegisterKey(g_KeyMoveVisorRight, (*) => MoveVisorDirection("right"))
    RegisterKey(g_KeyReload,      (*) => Reload())

    HotIfWinActive()
}

RegisterKey(keyName, callback)
{
    if (keyName != "")
    {
        hookKey := (InStr(keyName, "#") && !InStr(keyName, "$")) ? ("$" . keyName) : keyName
        try Hotkey(hookKey, callback)
        catch {
            try Hotkey(keyName, callback)
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
            try WinMove(wLeft, wTop, thisW, totalHeight, "ahk_id " hwnd)
        }
        else if (curSinglePaneSide == "right")
        {
            thisW := Floor((totalWidth - gap) / 2)
            currentX := wLeft + totalWidth - thisW
            try WinMove(currentX, wTop, thisW, totalHeight, "ahk_id " hwnd)
        }
        else
        {
            topHeight := Floor(totalHeight * g_VisorHeightPercent)
            try WinMove(wLeft, wTop, totalWidth, topHeight, "ahk_id " hwnd)
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

            try WinMove(wLeft, wTop, totalWidth, h1, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + h1, totalWidth, gap, g_BorderColor)
            try WinMove(wLeft, wTop + h1 + gap, totalWidth, h2, "ahk_id " windows[2])
        }
        else if (curTwoPaneLayout == "left-stacked")
        {
            colW := Floor((totalWidth - gap) / 2)
            availHeight := totalHeight - gap
            h1 := Floor(availHeight / 2)
            h2 := availHeight - h1

            try WinMove(wLeft, wTop, colW, h1, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + h1, colW, gap, g_BorderColor)
            try WinMove(wLeft, wTop + h1 + gap, colW, h2, "ahk_id " windows[2])
        }
        else if (curTwoPaneLayout == "right-stacked")
        {
            colW := Floor((totalWidth - gap) / 2)
            leftX := wLeft + totalWidth - colW
            availHeight := totalHeight - gap
            h1 := Floor(availHeight / 2)
            h2 := availHeight - h1

            try WinMove(leftX, wTop, colW, h1, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(targetMon, leftX, wTop + h1, colW, gap, g_BorderColor)
            try WinMove(leftX, wTop + h1 + gap, colW, h2, "ahk_id " windows[2])
        }
        else ; "side-by-side-visor" or "side-by-side-full"
        {
            paneHeight := (curTwoPaneLayout == "side-by-side-full") ? totalHeight : Floor(totalHeight * g_VisorHeightPercent)
            availWidth := totalWidth - gap
            col1W := Floor(availWidth / 2)
            col2W := availWidth - col1W

            try WinMove(wLeft, wTop, col1W, paneHeight, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(targetMon, wLeft + col1W, wTop, gap, paneHeight, g_BorderColor)
            try WinMove(wLeft + col1W + gap, wTop, col2W, paneHeight, "ahk_id " windows[2])
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
            try WinMove(wLeft, wTop, totalWidth, topHeight, "ahk_id " windows[1])

            ; Full-width horizontal divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

            ; Window 2: Bottom-Left
            try WinMove(wLeft, botY, bot1W, botHeight, "ahk_id " windows[2])

            ; Bottom vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + bot1W, botY, gap, botHeight, g_BorderColor)

            ; Window 3: Bottom-Right
            try WinMove(wLeft + bot1W + gap, botY, bot2W, botHeight, "ahk_id " windows[3])
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
            try WinMove(wLeft, wTop, masterWidth, totalHeight, "ahk_id " windows[1])

            ; Full-height vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + masterWidth, wTop, gap, totalHeight, g_BorderColor)

            ; Window 2: Top-Right
            try WinMove(rightX, wTop, rightWidth, h1, "ahk_id " windows[2])

            ; Horizontal divider in right column
            if (gap > 0)
                CreateDivider(targetMon, rightX, wTop + h1, rightWidth, gap, g_BorderColor)

            ; Window 3: Bottom-Right
            try WinMove(rightX, wTop + h1 + gap, rightWidth, h2, "ahk_id " windows[3])
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
            try WinMove(wLeft, wTop, leftWidth, h1, "ahk_id " windows[1])

            ; Horizontal divider in left column
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + h1, leftWidth, gap, g_BorderColor)

            ; Window 3: Bottom-Left
            try WinMove(wLeft, wTop + h1 + gap, leftWidth, h2, "ahk_id " windows[3])

            ; Full-height vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + leftWidth, wTop, gap, totalHeight, g_BorderColor)

            ; Window 2: Right Master (100% height)
            try WinMove(rightX, wTop, masterWidth, totalHeight, "ahk_id " windows[2])
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
            try WinMove(wLeft, wTop, top1W, topHeight, "ahk_id " windows[1])

            ; Top vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + top1W, wTop, gap, topHeight, g_BorderColor)

            ; Window 2: Top-Right
            try WinMove(wLeft + top1W + gap, wTop, top2W, topHeight, "ahk_id " windows[2])

            ; Full-width horizontal divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

            ; Window 3: Bottom Master (100% width)
            try WinMove(wLeft, botY, totalWidth, botHeight, "ahk_id " windows[3])
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
        try WinMove(currentX, wTop, thisW, topHeight, "ahk_id " hwnd)
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
            try WinMove(currentX, botY, thisW, botHeight, "ahk_id " hwnd)
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

; Helper: Resolves the configured shell executable from alacritty.toml
GetConfiguredShell()
{
    appDataToml := EnvGet("APPDATA") . "\alacritty\alacritty.toml"
    localToml   := A_ScriptDir . "\alacritty.toml"
    tomlPath := FileExist(appDataToml) ? appDataToml : (FileExist(localToml) ? localToml : "")

    if (tomlPath != "")
    {
        try {
            content := FileRead(tomlPath)
            if RegExMatch(content, 'i)program\s*=\s*"([^"]+)"', &m)
            {
                return m[1]
            }
        }
    }
    return "powershell.exe"
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

; Helper: Launches an Alacritty process, injecting welcome cheat sheet if configured and shell is PowerShell
LaunchTerminalProcess()
{
    global g_ShowHelpOnStart, g_FirstRun, g_ConfigFile
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
                argFlag := (g_ShowHelpOnStart == "tip") ? " -TipOnly" : ""
                Run(Format('alacritty.exe -e {1} -NoLogo -NoExit -ExecutionPolicy Bypass -File "{2}"{3}', configuredShell, welcomeScript, argFlag))

                if (g_ShowHelpOnStart == "first-run" && g_FirstRun)
                {
                    g_FirstRun := false
                    if (g_ConfigFile != "" && FileExist(g_ConfigFile))
                        try IniWrite("false", g_ConfigFile, "General", "FirstRun")
                }
                return
            }
        }
    }

    ; Clean first-run flag if first-run was triggered on a non-PowerShell shell
    if (g_FirstRun)
    {
        g_FirstRun := false
        if (g_ConfigFile != "" && FileExist(g_ConfigFile))
            try IniWrite("false", g_ConfigFile, "General", "FirstRun")
    }

    Run("alacritty.exe")
}

; Helper: Spawns the initial terminal window on target monitor (handling welcome banner if configured)
LaunchNewTerminal(targetMon)
{
    global g_MultiMonitorMode, g_MonitorWindows
    oldWindows := GetAlacrittyWindows()

    LaunchTerminalProcess()

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

; Toggles the terminal visor on the display containing the mouse cursor
ToggleVisor()
{
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder, g_LayoutLock
    DetectHiddenWindows true

    ; Detect monitor containing mouse cursor
    targetMon := GetMouseMonitor()

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
            ; Hide all terminals on this display
            for hwnd in monWindows
                try WinHide("ahk_id " hwnd)
            ClearDividers(targetMon)
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
            TileAlacritty(targetMon)
            if (windows.Length > 0 && WinExist("ahk_id " windows[1]))
                try WinActivate("ahk_id " windows[1])
            return
        }

        ; If already showing on the mouse monitor -> hide all
        for hwnd in windows
            try WinHide("ahk_id " hwnd)
        ClearDividers(0)
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
    LaunchTerminalProcess()

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
                        if (aliveList.Length > 0 && WinExist("ahk_id " aliveList[aliveList.Length]))
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
                        if (aliveList.Length > 0 && WinExist("ahk_id " aliveList[aliveList.Length]))
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
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Quake Alacritty v" . g_AppVersion, (*) => Run("https://github.com/orgNero/quake-alacritty"))
    tray.Disable("Quake Alacritty v" . g_AppVersion)
    tray.Add()
    tray.Add("Report Bug / Request Feature", (*) => Run("https://github.com/orgNero/quake-alacritty/issues/new/choose"))
    tray.Add("Documentation & Shortcuts", (*) => Run("https://github.com/orgNero/quake-alacritty#readme"))
    tray.Add()
    tray.Add("Reload Quake Alacritty", (*) => Reload())
    tray.Add("Exit", (*) => ExitApp())
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
LoadConfig()
ReadAppVersion()
RegisterHotkeys()
OnMessage(0x007E, OnDisplayChange)
OnMessage(0x0010, OnCloseMessage)
OnExit(CleanupOnExit)
A_IconTip := "Quake Alacritty v" . g_AppVersion
SetupTrayMenu()

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
