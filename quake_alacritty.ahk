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

; Hotkey mappings (defaults if config is absent or partial)
global g_KeyToggleVisor     := "#sc029"
global g_KeySplit           := "!Enter"
global g_KeyClose           := "!w"
global g_KeyRetile          := "!r"
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
    }

    ; 4. [Hotkeys]
    try {
        g_KeyToggleVisor := IniRead(g_ConfigFile, "Hotkeys", "ToggleVisor", g_KeyToggleVisor)
        g_KeySplit       := IniRead(g_ConfigFile, "Hotkeys", "SplitWindow", g_KeySplit)
        g_KeyClose       := IniRead(g_ConfigFile, "Hotkeys", "CloseWindow", g_KeyClose)
        g_KeyRetile      := IniRead(g_ConfigFile, "Hotkeys", "Retile", g_KeyRetile)
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

    RegisterKey(g_KeySplit,      (*) => SpawnSplit())
    RegisterKey(g_KeyClose,      (*) => CloseSplit())
    RegisterKey(g_KeyRetile,     (*) => TileAlacritty())
    RegisterKey(g_KeyFocusLeft,  (*) => FocusDirection("left"))
    RegisterKey(g_KeyFocusRight, (*) => FocusDirection("right"))
    RegisterKey(g_KeyFocusUp,    (*) => FocusDirection("up"))
    RegisterKey(g_KeyFocusDown,  (*) => FocusDirection("down"))
    RegisterKey(g_KeySwapLeft,   (*) => SwapDirection("left"))
    RegisterKey(g_KeySwapRight,  (*) => SwapDirection("right"))
    RegisterKey(g_KeySwapUp,     (*) => SwapDirection("up"))
    RegisterKey(g_KeySwapDown,   (*) => SwapDirection("down"))
    RegisterKey(g_KeyRotate,     (*) => RotateWindows())
    RegisterKey(g_KeyReload,     (*) => Reload())

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
; 1 window:  Top 100% width, 40% height (borderless)
; 2 windows: Top 50% / 50% width, 40% height (vertical cyan seam)
; 3 windows: Top 50% / 50% width, Bottom 100% width (T-split cyan seams)
; 4 windows: Top 50% / 50% width, Bottom 50% / 50% width (2x2 Quad, cyan cross seams)
TileAlacritty(targetMon := 0)
{
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

    ; Row distribution:
    ; 1-2 windows: all on top row
    ; 3 windows: 2 top, 1 bottom
    ; 4 windows: 2 top, 2 bottom
    topCount := (count <= 2) ? count : Ceil(count / 2)
    botCount := count - topCount

    ; Height distribution:
    ; 40% visor when only top row exists; 50/50 split (minus gap) when bottom row is filled
    gap := (count > 1) ? g_BorderGap : 0
    if (botCount == 0)
    {
        topHeight := Floor(totalHeight * g_VisorHeightPercent)
        botHeight := 0
        botY      := 0
    }
    else
    {
        availHeight := totalHeight - gap
        topHeight   := Floor(availHeight / 2)
        botHeight   := availHeight - topHeight
        botY        := wTop + topHeight + gap
    }

    ; 3. Tile Top Row (with vertical dividers between adjacent windows)
    topAvailWidth := totalWidth - ((topCount - 1) * gap)
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

        botAvailWidth := totalWidth - ((botCount - 1) * gap)
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
            if (dist < bestDist)
            {
                bestDist := dist
                bestHwnd := hwnd
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
            if (dist < bestDist - 100 || (Abs(dist - bestDist) <= 100 && tcx < acx))
            {
                bestDist := dist
                bestHwnd := hwnd
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


; -------------------------------------------------------------
; Window Management Actions
; -------------------------------------------------------------

; Toggles the terminal visor on the display containing the mouse cursor
ToggleVisor()
{
    DetectHiddenWindows true
    windows := GetAlacrittyWindows()

    ; Detect monitor containing mouse cursor
    targetMon := GetMouseMonitor()

    ; If none are running, launch the first one
    if (windows.Length == 0)
    {
        Run("alacritty.exe")
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
    global g_AlacrittyOrder
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
    activeHwnd := WinActive("A")
    WinClose("ahk_id " activeHwnd)
    ; Adaptive polling: re-tile immediately once window closes (up to 200ms max)
    Loop 20 {
        Sleep 10
        if (!WinExist("ahk_id " activeHwnd))
            break
    }
    TileAlacritty()
}