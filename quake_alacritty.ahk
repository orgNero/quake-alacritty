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
global g_MultiMonitorMode   := "hopping"
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
global g_AlacrittyOrder     := []
global g_Dividers           := []

; Helper: Resolves configuration file location and loads user preferences
LoadConfig()
{
    global g_ConfigFile, g_BorderGap, g_BorderColor, g_VisorHeightPercent, g_MultiMonitorMode, g_FirstRun
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
        g_MultiMonitorMode := IniRead(g_ConfigFile, "General", "MultiMonitorMode", "hopping")
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

; Initialize configuration and register hotkeys
LoadConfig()
RegisterHotkeys()
A_IconTip := "Quake Alacritty"


; Helper: Clears and destroys active divider lines
ClearDividers()
{
    global g_Dividers
    for div in g_Dividers
    {
        try div.Destroy()
    }
    g_Dividers := []
}

; Helper: Creates a click-through divider line
CreateDivider(x, y, w, h, color)
{
    global g_Dividers
    ; +AlwaysOnTop, -Caption, +ToolWindow, +E0x20 (click-through WS_EX_TRANSPARENT), -DPIScale (pixel-accurate)
    div := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
    div.BackColor := color
    div.Show(Format("x{1} y{2} w{3} h{4} NoActivate", x, y, w, h))
    g_Dividers.Push(div)
}

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

; Helper: Maintains a stable window ordering so existing splits don't jump around
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

; Helper: Tiles Alacritty windows dynamically:
; 1 window:  Top 100% width, 40% height (or 50% width full-height if positioned left/right)
; 2 windows: Configurable 2-pane mode (side-by-side visor/full, left-stacked, right-stacked)
; 3 windows: 4-cardinal master orientations (bottom, top, left, right)
; 4 windows: Top 50% / 50% width, Bottom 50% / 50% width (2x2 Quad, cyan cross seams)
TileAlacritty(targetMon := 0)
{
    global g_BorderGap, g_BorderColor, g_VisorHeightPercent, g_TileLayout, g_TwoPaneLayout, g_SinglePaneSide
    DetectHiddenWindows true
    realWindows := GetAlacrittyWindows()
    count := realWindows.Length
    if (count == 0)
    {
        ClearDividers()
        return
    }

    ClearDividers()
    windows := SyncWindowOrder(realWindows)

    if (targetMon == 0)
    {
        ; If any terminal window is already visible, keep it on its current monitor
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
        ; Otherwise, place it where the mouse cursor is
        if (targetMon == 0)
            targetMon := GetMouseMonitor()
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
        if (g_SinglePaneSide == "left")
        {
            thisW := Floor((totalWidth - gap) / 2)
            WinMove(wLeft, wTop, thisW, totalHeight, "ahk_id " hwnd)
        }
        else if (g_SinglePaneSide == "right")
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
        if (g_TwoPaneLayout == "left-stacked")
        {
            colW := Floor((totalWidth - gap) / 2)
            availHeight := totalHeight - gap
            h1 := Floor(availHeight / 2)
            h2 := availHeight - h1

            WinMove(wLeft, wTop, colW, h1, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(wLeft, wTop + h1, colW, gap, g_BorderColor)
            WinMove(wLeft, wTop + h1 + gap, colW, h2, "ahk_id " windows[2])
        }
        else if (g_TwoPaneLayout == "right-stacked")
        {
            colW := Floor((totalWidth - gap) / 2)
            leftX := wLeft + totalWidth - colW
            availHeight := totalHeight - gap
            h1 := Floor(availHeight / 2)
            h2 := availHeight - h1

            WinMove(leftX, wTop, colW, h1, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(leftX, wTop + h1, colW, gap, g_BorderColor)
            WinMove(leftX, wTop + h1 + gap, colW, h2, "ahk_id " windows[2])
        }
        else ; "side-by-side-visor" or "side-by-side-full"
        {
            paneHeight := (g_TwoPaneLayout == "side-by-side-full") ? totalHeight : Floor(totalHeight * g_VisorHeightPercent)
            availWidth := totalWidth - gap
            col1W := Floor(availWidth / 2)
            col2W := availWidth - col1W

            WinMove(wLeft, wTop, col1W, paneHeight, "ahk_id " windows[1])
            if (gap > 0)
                CreateDivider(wLeft + col1W, wTop, gap, paneHeight, g_BorderColor)
            WinMove(wLeft + col1W + gap, wTop, col2W, paneHeight, "ahk_id " windows[2])
        }
        return
    }

    ; -------------------------------------------------------------
    ; Case 3: Exactly 3 windows (4 Cardinal Master Orientations)
    ; -------------------------------------------------------------
    if (count == 3)
    {
        if (g_TileLayout == "top")
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
                CreateDivider(wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

            ; Window 2: Bottom-Left
            WinMove(wLeft, botY, bot1W, botHeight, "ahk_id " windows[2])

            ; Bottom vertical divider
            if (gap > 0)
                CreateDivider(wLeft + bot1W, botY, gap, botHeight, g_BorderColor)

            ; Window 3: Bottom-Right
            WinMove(wLeft + bot1W + gap, botY, bot2W, botHeight, "ahk_id " windows[3])
        }
        else if (g_TileLayout == "left")
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
                CreateDivider(wLeft + masterWidth, wTop, gap, totalHeight, g_BorderColor)

            ; Window 2: Top-Right
            WinMove(rightX, wTop, rightWidth, h1, "ahk_id " windows[2])

            ; Horizontal divider in right column
            if (gap > 0)
                CreateDivider(rightX, wTop + h1, rightWidth, gap, g_BorderColor)

            ; Window 3: Bottom-Right
            WinMove(rightX, wTop + h1 + gap, rightWidth, h2, "ahk_id " windows[3])
        }
        else if (g_TileLayout == "right")
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
                CreateDivider(wLeft, wTop + h1, leftWidth, gap, g_BorderColor)

            ; Window 3: Bottom-Left
            WinMove(wLeft, wTop + h1 + gap, leftWidth, h2, "ahk_id " windows[3])

            ; Full-height vertical divider
            if (gap > 0)
                CreateDivider(wLeft + leftWidth, wTop, gap, totalHeight, g_BorderColor)

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
                CreateDivider(wLeft + top1W, wTop, gap, topHeight, g_BorderColor)

            ; Window 2: Top-Right
            WinMove(wLeft + top1W + gap, wTop, top2W, topHeight, "ahk_id " windows[2])

            ; Full-width horizontal divider
            if (gap > 0)
                CreateDivider(wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

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
            CreateDivider(currentX, wTop, gap, topHeight, g_BorderColor)
            currentX += gap
        }
    }

    ; 4. Tile Bottom Row (if any, with horizontal divider and vertical dividers)
    if (botCount > 0)
    {
        ; Horizontal divider between top and bottom rows
        if (gap > 0)
            CreateDivider(wLeft, wTop + topHeight, totalWidth, gap, g_BorderColor)

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
                CreateDivider(currentX, botY, gap, botHeight, g_BorderColor)
                currentX += gap
            }
        }
    }
}

; Helper: Switch keyboard typing focus between splits using directional keys
FocusDirection(dir)
{
    activeHwnd := WinActive("A")
    if (!activeHwnd)
        return

    realWindows := GetAlacrittyWindows()
    if (realWindows.Length <= 1)
        return

    WinGetPos(&ax, &ay, &aw, &ah, "ahk_id " activeHwnd)
    acx := ax + (aw / 2)
    acy := ay + (ah / 2)

    bestHwnd := 0
    bestDist := 99999999
    bestTcx  := 0
    bestTcy  := 0

    for hwnd in realWindows
    {
        if (hwnd == activeHwnd)
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
            ; Tie-breaking for equidistant targets (e.g. Master pane navigating to 2 stacked panes):
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
    activeHwnd := WinActive("A")
    if (!activeHwnd)
        return

    realWindows := GetAlacrittyWindows()
    if (realWindows.Length <= 1)
        return

    ; Ensure g_AlacrittyOrder is synchronized with current live windows
    global g_AlacrittyOrder
    SyncWindowOrder(realWindows)

    WinGetPos(&ax, &ay, &aw, &ah, "ahk_id " activeHwnd)
    acx := ax + (aw / 2)
    acy := ay + (ah / 2)

    bestHwnd := 0
    bestDist := 99999999
    bestTcx  := 0
    bestTcy  := 0

    for hwnd in realWindows
    {
        if (hwnd == activeHwnd)
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
            ; Tie-breaker: If distances are almost equal (within 100px difference),
            ; prefer the window further to the left (smaller tcx) or higher up (smaller tcy)
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

    ; Swap activeHwnd and bestHwnd inside g_AlacrittyOrder
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

        TileAlacritty()
        WinActivate("ahk_id " activeHwnd)
    }
}

; Helper: Rotate all terminal pane positions cyclically
RotateWindows(clockwise := true)
{
    activeHwnd := WinActive("A")
    if (!activeHwnd)
        return

    realWindows := GetAlacrittyWindows()
    if (realWindows.Length <= 1)
        return

    global g_AlacrittyOrder
    SyncWindowOrder(realWindows)

    if (g_AlacrittyOrder.Length <= 1)
        return

    if (clockwise)
    {
        ; Shift last item to the front
        lastItem := g_AlacrittyOrder.Pop()
        g_AlacrittyOrder.InsertAt(1, lastItem)
    }
    else
    {
        ; Shift first item to the back
        firstItem := g_AlacrittyOrder.RemoveAt(1)
        g_AlacrittyOrder.Push(firstItem)
    }

    TileAlacritty()
    if (activeHwnd)
        WinActivate("ahk_id " activeHwnd)
}

; Helper: Cycles multi-pane terminal layouts live without editing config.ini
CycleLayout()
{
    global g_TileLayout, g_TwoPaneLayout, g_SinglePaneSide
    activeHwnd := WinActive("A")
    realWindows := GetAlacrittyWindows()
    count := realWindows.Length

    if (count == 1)
    {
        ; Cycle single-pane: full-width visor -> left-half full-height -> right-half full-height -> full-width visor
        if (g_SinglePaneSide == "")
            g_SinglePaneSide := "left"
        else if (g_SinglePaneSide == "left")
            g_SinglePaneSide := "right"
        else
            g_SinglePaneSide := ""
    }
    else if (count == 2)
    {
        ; Cycle 2-pane modes: side-by-side-visor -> side-by-side-full -> left-stacked -> right-stacked -> side-by-side-visor
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
        ; Cycle 3-pane master orientations: bottom -> top -> left -> right -> bottom
        if (g_TileLayout == "bottom")
            g_TileLayout := "top"
        else if (g_TileLayout == "top")
            g_TileLayout := "left"
        else if (g_TileLayout == "left")
            g_TileLayout := "right"
        else
            g_TileLayout := "bottom"
    }

    TileAlacritty()
    if (activeHwnd && WinExist("ahk_id " activeHwnd))
        WinActivate("ahk_id " activeHwnd)
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

; Toggles the terminal visor on the display containing the mouse cursor
ToggleVisor()
{
    global g_FirstRun, g_ConfigFile
    DetectHiddenWindows true
    windows := GetAlacrittyWindows()

    ; Detect monitor containing mouse cursor
    targetMon := GetMouseMonitor()

    ; If none are running, launch the first one
    if (windows.Length == 0)
    {
        if (g_FirstRun)
        {
            welcomeScript := ""
            if FileExist(A_ScriptDir . "\welcome.ps1")
                welcomeScript := A_ScriptDir . "\welcome.ps1"
            else if FileExist(EnvGet("APPDATA") . "\alacritty\welcome.ps1")
                welcomeScript := EnvGet("APPDATA") . "\alacritty\welcome.ps1"

            if (welcomeScript != "")
            {
                shellProg := GetDefaultShell()
                Run(Format('alacritty.exe -e {1} -NoLogo -NoExit -ExecutionPolicy Bypass -File "{2}"', shellProg, welcomeScript))
            }
            else
            {
                Run("alacritty.exe")
            }

            ; Mark first run complete and persist to config.ini
            g_FirstRun := false
            if (g_ConfigFile != "" && FileExist(g_ConfigFile))
            {
                try IniWrite("false", g_ConfigFile, "General", "FirstRun")
            }
        }
        else
        {
            Run("alacritty.exe")
        }
        firstHwnd := 0
        ; Adaptive polling: tile immediately once window appears (up to 1.5s cold start)
        Loop 75 {
            Sleep 20
            firstWins := GetAlacrittyWindows()
            if (firstWins.Length > 0)
            {
                firstHwnd := firstWins[1]
                break
            }
        }
        TileAlacritty(targetMon)

        if (firstHwnd)
            WinActivate("ahk_id " firstHwnd)
        else
        {
            firstWins := GetAlacrittyWindows()
            if (firstWins.Length > 0)
                WinActivate("ahk_id " firstWins[1])
        }
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
        ClearDividers()
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
    oldWindows := GetAlacrittyWindows()
    oldCount := oldWindows.Length
    Run("alacritty.exe")

    newHwnd := 0
    ; Adaptive polling: tile immediately once new window appears (up to 450ms max)
    Loop 30 {
        Sleep 15
        currentWindows := GetAlacrittyWindows()
        if (currentWindows.Length > oldCount)
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
                    newHwnd := hwnd
                    break
                }
            }
            break
        }
    }

    ; Handle dynamic transitions:
    if (oldCount == 1 && newHwnd)
    {
        ; 1 -> 2 panes:
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
        ; 2 -> 3 panes:
        if (g_TwoPaneLayout == "left-stacked")
        {
            g_TileLayout := "right"
            ; In right master mode: [1: Top-Left, 2: Right-Master, 3: Bottom-Left]
            ; Ensure old windows remain in their slots and new window becomes Right-Master
            if (oldWindows.Length >= 2)
                g_AlacrittyOrder := [oldWindows[1], newHwnd, oldWindows[2]]
        }
        else if (g_TwoPaneLayout == "right-stacked")
        {
            g_TileLayout := "left"
            ; In left master mode: [1: Left-Master, 2: Top-Right, 3: Bottom-Right]
            ; New window becomes Left-Master, old windows remain Top-Right and Bottom-Right
            if (oldWindows.Length >= 2)
                g_AlacrittyOrder := [newHwnd, oldWindows[1], oldWindows[2]]
        }
    }

    TileAlacritty()

    ; Shift keyboard typing focus to the newly created split terminal
    if (newHwnd)
        WinActivate("ahk_id " newHwnd)
    else if (g_AlacrittyOrder.Length > oldCount)
        WinActivate("ahk_id " g_AlacrittyOrder[g_AlacrittyOrder.Length])
}

; Closes focused window and auto-rebalances remaining windows
CloseSplit()
{
    global g_TwoPaneLayout, g_TileLayout, g_SinglePaneSide
    activeHwnd := WinActive("A")
    oldWindows := GetAlacrittyWindows()
    oldCount := oldWindows.Length

    WinClose("ahk_id " activeHwnd)
    ; Adaptive polling: re-tile immediately once window closes (up to 200ms max)
    Loop 20 {
        Sleep 10
        if (!WinExist("ahk_id " activeHwnd))
            break
    }

    ; Handle dynamic transitions when closing panes:
    if (oldCount == 2)
    {
        ; 2 -> 1 pane:
        ; When closing a pane from left-stacked or right-stacked, remaining terminal stays on its half
        if (g_TwoPaneLayout == "left-stacked")
            g_SinglePaneSide := "left"
        else if (g_TwoPaneLayout == "right-stacked")
            g_SinglePaneSide := "right"
        else
            g_SinglePaneSide := ""
    }
    else if (oldCount == 3)
    {
        ; 3 -> 2 panes:
        if (g_TileLayout == "right")
            g_TwoPaneLayout := "left-stacked"
        else if (g_TileLayout == "left")
            g_TwoPaneLayout := "right-stacked"
    }

    TileAlacritty()
}