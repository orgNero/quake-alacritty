#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent true
DetectHiddenWindows true
SetWinDelay -1
SetControlDelay -1


; Visual separator styling for adjacent terminal borders
global g_BorderGap   := 2          ; Gap thickness in pixels between adjacent terminals
global g_BorderColor := "38bdf8"   ; Vibrant electric cyan (hex RGB)

; Stable window order tracker across splits and closes
global g_AlacrittyOrder := []
global g_Dividers := []

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
        topHeight := Floor(totalHeight * 0.40)
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
; Global Dropdown Toggle (Win + §)
; -------------------------------------------------------------
#§::
{
    DetectHiddenWindows true
    windows := GetAlacrittyWindows()

    ; Detect monitor containing mouse cursor
    targetMon := GetMouseMonitor()

    ; If none are running, launch the first one
    if (windows.Length == 0)
    {
        Run("alacritty.exe")
        Loop 30 {
            Sleep 20
            if (GetAlacrittyWindows().Length > 0)
                break
        }
        TileAlacritty(targetMon)
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

; -------------------------------------------------------------
; Controls while inside Alacritty
; -------------------------------------------------------------
#HotIf WinActive("ahk_exe alacritty.exe")

; Alt + Enter: Split window (spawns new terminal and dynamically re-tiles into grid)
!Enter::
{
    oldCount := GetAlacrittyWindows().Length
    Run("alacritty.exe")
    ; Adaptive polling: tile immediately once new window appears (up to 450ms max)
    Loop 30 {
        Sleep 15
        if (GetAlacrittyWindows().Length > oldCount)
            break
    }
    TileAlacritty()
}

; Alt + W: Close focused window and auto-rebalance remaining windows
!w::
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

; Alt + Ctrl + R: Clean in-process script reload for development
!^r::Reload()


; Alt + R: Force re-tile
!r::
{
    TileAlacritty()
}

; Alt + Arrow keys: Switch typing focus between panes without touching the mouse
!Left::  FocusDirection("left")
!Right:: FocusDirection("right")
!Up::    FocusDirection("up")
!Down::  FocusDirection("down")

; Alt + Shift + Arrow keys: Swap position of active pane with adjacent pane
!+Left::  SwapDirection("left")
!+Right:: SwapDirection("right")
!+Up::    SwapDirection("up")
!+Down::  SwapDirection("down")

; Alt + Shift + Space: Rotate all pane positions cyclically
!+Space:: RotateWindows()

#HotIf