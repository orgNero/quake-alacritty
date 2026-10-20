#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true
DetectHiddenWindows true
SetWinDelay -1
SetControlDelay -1


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

; Helper: Resolves configuration file location and loads user preferences
LoadConfig()
{
    global g_ConfigFile, g_BorderGap, g_BorderColor, g_VisorHeightPercent, g_MultiMonitorMode, g_ShowHelpOnStart, g_FirstRun
    global g_TileLayout, g_TwoPaneLayout, g_KeyCycleLayout
    global g_KeyToggleVisor, g_KeySplit, g_KeyClose, g_KeyRetile
    global g_KeyFocusLeft, g_KeyFocusRight, g_KeyFocusUp, g_KeyFocusDown
    global g_KeySwapLeft, g_KeySwapRight, g_KeySwapUp, g_KeySwapDown
    global g_KeyRotate, g_KeyReload

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
        if (tpVal == "side-by-side-visor" || tpVal == "side-by-side-full" || tpVal == "left-stacked" || tpVal == "right-stacked")
            g_TwoPaneLayout := tpVal
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
        g_KeyRotate      := IniRead(g_ConfigFile, "Hotkeys", "RotatePanes", g_KeyRotate)
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
    RegisterKey(g_KeyRotate,      (*) => RotateWindows())
    RegisterKey(g_KeyReload,      (*) => Reload())

    HotIfWinActive()
}

RegisterKey(keyName, callback)
{
    if (keyName != "")
    {
        try Hotkey(keyName, callback)
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
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder
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
TileAlacritty(targetMon := 0)
{
    global g_BorderGap, g_BorderColor, g_VisorHeightPercent
    global g_TileLayout, g_TwoPaneLayout, g_SinglePaneSide
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder
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
        windows := SyncWindowOrder(realWindows)

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
        WinShow("ahk_id " hwnd)
        WinSetAlwaysOnTop(1, "ahk_id " hwnd)
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
            WinMove(wLeft, wTop, thisW, totalHeight, "ahk_id " hwnd)
        }
        else if (curSinglePaneSide == "right")
        {
            thisW := Floor((totalWidth - gap) / 2)
            currentX := wLeft + totalWidth - thisW
            WinMove(currentX, wTop, thisW, totalHeight, "ahk_id " hwnd)
        }
        else
        {
            topHeight := Floor(totalHeight * g_VisorHeightPercent)
            WinMove(wLeft, wTop, totalWidth, topHeight, "ahk_id " hwnd)
        }
        return
    }

    ; -------------------------------------------------------------
    ; Case 2: Exactly 2 windows
    ; -------------------------------------------------------------
    if (count == 2)
    {
        if (curTwoPaneLayout == "left-stacked")
        {
            colW := Floor((totalWidth - gap) / 2)
            availHeight := totalHeight - gap
            h1 := Floor(availHeight / 2)
            h2 := availHeight - h1

            WinMove(wLeft, wTop, colW, h1, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + h1, colW, gap, g_BorderColor)
            WinMove(wLeft, wTop + h1 + gap, colW, h2, "ahk_id " windows[2])
        }
        else if (curTwoPaneLayout == "right-stacked")
        {
            colW := Floor((totalWidth - gap) / 2)
            leftX := wLeft + totalWidth - colW
            availHeight := totalHeight - gap
            h1 := Floor(availHeight / 2)
            h2 := availHeight - h1

            WinMove(leftX, wTop, colW, h1, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(targetMon, leftX, wTop + h1, colW, gap, g_BorderColor)
            WinMove(leftX, wTop + h1 + gap, colW, h2, "ahk_id " windows[2])
        }
        else ; "side-by-side-visor" or "side-by-side-full"
        {
            paneHeight := (curTwoPaneLayout == "side-by-side-full") ? totalHeight : Floor(totalHeight * g_VisorHeightPercent)
            availWidth := totalWidth - gap
            col1W := Floor(availWidth / 2)
            col2W := availWidth - col1W

            WinMove(wLeft, wTop, col1W, paneHeight, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(targetMon, wLeft + col1W, wTop, gap, paneHeight, g_BorderColor)
            WinMove(wLeft + col1W + gap, wTop, col2W, paneHeight, "ahk_id " windows[2])
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
            WinMove(wLeft, wTop, totalWidth, topHeight, "ahk_id " windows[1])

            ; Full-width horizontal divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

            ; Window 2: Bottom-Left
            WinMove(wLeft, botY, bot1W, botHeight, "ahk_id " windows[2])

            ; Bottom vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + bot1W, botY, gap, botHeight, g_BorderColor)

            ; Window 3: Bottom-Right
            WinMove(wLeft + bot1W + gap, botY, bot2W, botHeight, "ahk_id " windows[3])
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
            WinMove(wLeft, wTop, masterWidth, totalHeight, "ahk_id " windows[1])

            ; Full-height vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + masterWidth, wTop, gap, totalHeight, g_BorderColor)

            ; Window 2: Top-Right
            WinMove(rightX, wTop, rightWidth, h1, "ahk_id " windows[2])

            ; Horizontal divider in right column
            if (gap > 0)
                CreateDivider(targetMon, rightX, wTop + h1, rightWidth, gap, g_BorderColor)

            ; Window 3: Bottom-Right
            WinMove(rightX, wTop + h1 + gap, rightWidth, h2, "ahk_id " windows[3])
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
            WinMove(wLeft, wTop, leftWidth, h1, "ahk_id " windows[1])

            ; Horizontal divider in left column
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + h1, leftWidth, gap, g_BorderColor)

            ; Window 3: Bottom-Left
            WinMove(wLeft, wTop + h1 + gap, leftWidth, h2, "ahk_id " windows[3])

            ; Full-height vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + leftWidth, wTop, gap, totalHeight, g_BorderColor)

            ; Window 2: Right Master (100% height)
            WinMove(rightX, wTop, masterWidth, totalHeight, "ahk_id " windows[2])
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
            WinMove(wLeft, wTop, top1W, topHeight, "ahk_id " windows[1])

            ; Top vertical divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft + top1W, wTop, gap, topHeight, g_BorderColor)

            ; Window 2: Top-Right
            WinMove(wLeft + top1W + gap, wTop, top2W, topHeight, "ahk_id " windows[2])

            ; Full-width horizontal divider
            if (gap > 0)
                CreateDivider(targetMon, wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

            ; Window 3: Bottom Master (100% width)
            WinMove(wLeft, botY, totalWidth, botHeight, "ahk_id " windows[3])
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
        WinMove(currentX, wTop, thisW, topHeight, "ahk_id " hwnd)
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
            WinMove(currentX, botY, thisW, botHeight, "ahk_id " hwnd)
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
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder
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
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder
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

; Helper: Resolves the default shell executable configured in alacritty.toml
GetDefaultShell()
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
                prog := m[1]
                if (InStr(prog, "pwsh") || InStr(prog, "powershell"))
                    return prog
            }
        }
    }
    return "powershell.exe"
}

; Helper: Launches an Alacritty process, injecting welcome cheat sheet if configured
LaunchTerminalProcess()
{
    global g_ShowHelpOnStart, g_FirstRun, g_ConfigFile
    shouldShowHelp := (g_ShowHelpOnStart == "tip" || g_ShowHelpOnStart == "banner") || (g_ShowHelpOnStart == "first-run" && g_FirstRun)

    if (shouldShowHelp)
    {
        welcomeScript := ""
        if FileExist(A_ScriptDir . "\welcome.ps1")
            welcomeScript := A_ScriptDir . "\welcome.ps1"
        else if FileExist(EnvGet("APPDATA") . "\alacritty\welcome.ps1")
            welcomeScript := EnvGet("APPDATA") . "\alacritty\welcome.ps1"

        if (welcomeScript != "")
        {
            shellProg := GetDefaultShell()
            argFlag := (g_ShowHelpOnStart == "tip") ? " -TipOnly" : ""
            Run(Format('alacritty.exe -e {1} -NoLogo -NoExit -ExecutionPolicy Bypass -File "{2}"{3}', shellProg, welcomeScript, argFlag))

            if (g_ShowHelpOnStart == "first-run" && g_FirstRun)
            {
                g_FirstRun := false
                if (g_ConfigFile != "" && FileExist(g_ConfigFile))
                    try IniWrite("false", g_ConfigFile, "General", "FirstRun")
            }
            return
        }
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

    if (g_MultiMonitorMode == "isolated" && firstHwnd)
    {
        if (!g_MonitorWindows.Has(targetMon))
            g_MonitorWindows[targetMon] := []
        g_MonitorWindows[targetMon].Push(firstHwnd)
    }

    TileAlacritty(targetMon)

    if (firstHwnd && WinExist("ahk_id " firstHwnd))
        WinActivate("ahk_id " firstHwnd)
}

; Toggles the terminal visor on the display containing the mouse cursor
ToggleVisor()
{
    global g_MultiMonitorMode, g_MonitorWindows, g_AlacrittyOrder
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
                WinHide("ahk_id " hwnd)
            ClearDividers(targetMon)
        }
        else
        {
            ; Show and tile terminals on this display
            TileAlacritty(targetMon)
            if (monWindows.Length > 0 && WinExist("ahk_id " monWindows[1]))
                WinActivate("ahk_id " monWindows[1])
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
            WinActivate("ahk_id " windows[1])
            return
        }

        ; If already showing on the mouse monitor -> hide all
        for hwnd in windows
            WinHide("ahk_id " hwnd)
        ClearDividers(0)
    }
    else
    {
        ; If tucked away -> show, tile on mouse screen, and focus
        TileAlacritty(targetMon)
        WinActivate("ahk_id " windows[1])
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
        if (newHwnd)
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
        }

        TileAlacritty(targetMon)

        if (newHwnd && WinExist("ahk_id " newHwnd))
            WinActivate("ahk_id " newHwnd)
        else if (g_MonitorWindows[targetMon].Length > oldCount)
            WinActivate("ahk_id " g_MonitorWindows[targetMon][g_MonitorWindows[targetMon].Length])
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
        }

        TileAlacritty(targetMon)

        if (newHwnd && WinExist("ahk_id " newHwnd))
            WinActivate("ahk_id " newHwnd)
        else if (g_AlacrittyOrder.Length > oldCount)
            WinActivate("ahk_id " g_AlacrittyOrder[g_AlacrittyOrder.Length])
    }
}

; Closes focused window and auto-rebalances remaining windows
CloseSplit()
{
    global g_TwoPaneLayout, g_TileLayout, g_SinglePaneSide
    global g_MultiMonitorMode, g_MonitorWindows

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

        WinClose("ahk_id " activeHwnd)
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
        }

        if (g_MonitorWindows[targetMon].Length > 0)
        {
            TileAlacritty(targetMon)
            WinActivate("ahk_id " g_MonitorWindows[targetMon][g_MonitorWindows[targetMon].Length])
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

        WinClose("ahk_id " activeHwnd)
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
        }

        TileAlacritty()
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
; Script Initialization
; -------------------------------------------------------------
LoadConfig()
RegisterHotkeys()
OnMessage(0x007E, OnDisplayChange)
A_IconTip := "Quake Alacritty"

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
