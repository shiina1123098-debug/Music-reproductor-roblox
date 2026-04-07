-- ╔══════════════════════════════════════════════════════╗
-- ║         Shiina Music Player v1.0 - Delta Edition     ║
-- ║   YouTube audio via Cobalt API + YTI search          ║
-- ║   Features: Search, Queue, Progress Bar, Volume      ║
-- ╚══════════════════════════════════════════════════════╝

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")
local HttpService   = game:GetService("HttpService")

local player     = Players.LocalPlayer
local playerGui  = player:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════
--  CONFIG — cambiá la instancia si se rompe
-- ══════════════════════════════════════════════
local COBALT_INSTANCES = {
    "https://cobalt.privacyredirect.com",
    "https://cobalt.seitan.ee",
    "https://co.wuk.sh",
    "https://api.cobalt.tools",
}
local COBALT_INDEX = 1  -- instancia activa

-- ══════════════════════════════════════════════
--  PALETA (igual a RedHood Hub)
-- ══════════════════════════════════════════════
local C = {
    bg       = Color3.fromRGB(18,  18,  24),
    panel    = Color3.fromRGB(26,  26,  34),
    row      = Color3.fromRGB(33,  33,  43),
    rowHov   = Color3.fromRGB(42,  42,  54),
    accent   = Color3.fromRGB(210, 30,  50),
    accentDim= Color3.fromRGB(130, 20,  30),
    text     = Color3.fromRGB(230, 230, 235),
    subtext  = Color3.fromRGB(140, 140, 155),
    bar      = Color3.fromRGB(50,  50,  65),
    barFill  = Color3.fromRGB(210, 30,  50),
    black    = Color3.fromRGB(0,   0,   0),
    white    = Color3.fromRGB(255, 255, 255),
    green    = Color3.fromRGB(50,  200, 80),
    disabled = Color3.fromRGB(80,  80,  95),
}

-- ══════════════════════════════════════════════
--  ESTADO
-- ══════════════════════════════════════════════
local queue        = {}   -- { title, videoId, audioUrl }
local currentIdx   = 0
local soundObj     = nil
local isPlaying    = false
local volume       = 0.7
local progressConn = nil

-- ══════════════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════════════
local function corner(inst, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = inst
end

local function stroke(inst, color, thick)
    local s = Instance.new("UIStroke")
    s.Color = color or C.accent
    s.Thickness = thick or 1.5
    s.Parent = inst
end

local function label(parent, txt, size, color, bold, xAlign)
    local l = Instance.new("TextLabel")
    l.Text = txt
    l.TextSize = size or 14
    l.TextColor3 = color or C.text
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.BackgroundTransparency = 1
    l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local function notify(msg, good)
    local ng = Instance.new("ScreenGui")
    ng.Name = "ShiinaNotif"
    ng.ResetOnSpawn = false
    ng.Parent = playerGui

    local f = Instance.new("Frame")
    f.Size = UDim2.new(0, 280, 0, 44)
    f.Position = UDim2.new(0.5, -140, 0, -50)
    f.BackgroundColor3 = good and C.green or C.accent
    f.BorderSizePixel = 0
    f.Parent = ng
    corner(f, 8)

    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -16, 1, 0)
    l.Position = UDim2.new(0, 8, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = msg
    l.TextColor3 = C.white
    l.TextSize = 13
    l.Font = Enum.Font.GothamSemibold
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = f

    TweenService:Create(f, TweenInfo.new(0.3), {
        Position = UDim2.new(0.5, -140, 0, 12)
    }):Play()

    task.delay(2.8, function()
        TweenService:Create(f, TweenInfo.new(0.3), {
            Position = UDim2.new(0.5, -140, 0, -50)
        }):Play()
        task.delay(0.35, function() ng:Destroy() end)
    end)
end

-- ══════════════════════════════════════════════
--  COBALT — obtener URL de audio
-- ══════════════════════════════════════════════
local function getCobaltAudio(videoId, callback)
    local ytUrl = "https://www.youtube.com/watch?v=" .. videoId
    local tried = 0

    local function tryNext()
        tried = tried + 1
        if tried > #COBALT_INSTANCES then
            callback(nil, "Todas las instancias fallaron")
            return
        end
        local base = COBALT_INSTANCES[tried]
        local ok, res = pcall(function()
            return syn and syn.request({
                Url = base .. "/",
                Method = "POST",
                Headers = {
                    ["Content-Type"]  = "application/json",
                    ["Accept"]        = "application/json",
                },
                Body = HttpService:JSONEncode({
                    url          = ytUrl,
                    downloadMode = "audio",
                    audioFormat  = "mp3",
                    audioBitrate = "128",
                })
            }) or http and http.request({
                Url = base .. "/",
                Method = "POST",
                Headers = {
                    ["Content-Type"]  = "application/json",
                    ["Accept"]        = "application/json",
                },
                Body = HttpService:JSONEncode({
                    url          = ytUrl,
                    downloadMode = "audio",
                    audioFormat  = "mp3",
                    audioBitrate = "128",
                })
            })
        end)

        if not ok or not res then
            tryNext(); return
        end

        local data
        local dok = pcall(function()
            data = HttpService:JSONDecode(res.Body)
        end)
        if not dok or not data then tryNext(); return end

        if data.status == "tunnel" or data.status == "redirect" then
            callback(data.url, nil)
        elseif data.url then
            callback(data.url, nil)
        else
            tryNext()
        end
    end

    tryNext()
end

-- ══════════════════════════════════════════════
--  YOUTUBE SEARCH (youtubei — sin key)
-- ══════════════════════════════════════════════
local function searchYouTube(query, callback)
    task.spawn(function()
        local ok, res = pcall(function()
            return syn and syn.request({
                Url    = "https://www.youtube.com/youtubei/v1/search?prettyPrint=false",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["User-Agent"]   = "Mozilla/5.0",
                },
                Body = HttpService:JSONEncode({
                    context = {
                        client = {
                            clientName    = "WEB",
                            clientVersion = "2.20231121.08.00",
                        }
                    },
                    query = query,
                })
            }) or http and http.request({
                Url    = "https://www.youtube.com/youtubei/v1/search?prettyPrint=false",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["User-Agent"]   = "Mozilla/5.0",
                },
                Body = HttpService:JSONEncode({
                    context = {
                        client = {
                            clientName    = "WEB",
                            clientVersion = "2.20231121.08.00",
                        }
                    },
                    query = query,
                })
            })
        end)

        if not ok or not res then callback(nil); return end

        local data
        local dok = pcall(function()
            data = HttpService:JSONDecode(res.Body)
        end)
        if not dok then callback(nil); return end

        local results = {}
        local ok2, _ = pcall(function()
            local contents = data
                .contents
                .twoColumnSearchResultsRenderer
                .primaryContents
                .sectionListRenderer
                .contents[1]
                .itemSectionRenderer
                .contents

            for _, item in ipairs(contents) do
                if item.videoRenderer then
                    local v = item.videoRenderer
                    local id    = v.videoId
                    local title = v.title and v.title.runs and v.title.runs[1] and v.title.runs[1].text or "Sin titulo"
                    local ch    = v.ownerText and v.ownerText.runs and v.ownerText.runs[1] and v.ownerText.runs[1].text or ""
                    local dur   = v.lengthText and v.lengthText.simpleText or "?"
                    table.insert(results, { id = id, title = title, channel = ch, duration = dur })
                    if #results >= 6 then break end
                end
            end
        end)

        callback(#results > 0 and results or nil)
    end)
end

-- ══════════════════════════════════════════════
--  AUDIO PLAYBACK
-- ══════════════════════════════════════════════
local function stopProgress()
    if progressConn then
        progressConn:Disconnect()
        progressConn = nil
    end
end

local function updateProgressBar(bar, timeLabel)
    stopProgress()
    if not soundObj then return end
    progressConn = RunService.Heartbeat:Connect(function()
        if not soundObj or not soundObj.Parent then stopProgress(); return end
        local pos = soundObj.TimePosition
        local len = soundObj.TimeLength
        if len and len > 0 then
            local pct = math.clamp(pos / len, 0, 1)
            bar.Size = UDim2.new(pct, 0, 1, 0)
            local function fmt(s)
                s = math.floor(s)
                return string.format("%d:%02d", math.floor(s/60), s%60)
            end
            if timeLabel then
                timeLabel.Text = fmt(pos) .. " / " .. fmt(len)
            end
        end
    end)
end

local function playSound(url, onEnded)
    if soundObj then
        soundObj:Stop()
        soundObj:Destroy()
        soundObj = nil
    end
    stopProgress()

    local s = Instance.new("Sound")
    s.SoundId    = url
    s.Volume     = volume
    s.RollOffMaxDistance = 1e9
    s.Parent     = workspace
    soundObj     = s

    s:Play()
    isPlaying = true

    s.Ended:Connect(function()
        isPlaying = false
        if onEnded then onEnded() end
    end)

    return s
end

-- ══════════════════════════════════════════════
--  BUILD GUI
-- ══════════════════════════════════════════════
local SG = Instance.new("ScreenGui")
SG.Name           = "ShiinaMusic_v1"
SG.ResetOnSpawn   = false
SG.DisplayOrder   = 9999
SG.Parent         = playerGui

-- Ventana principal
local Main = Instance.new("Frame")
Main.Name             = "Main"
Main.Size             = UDim2.new(0, 370, 0, 560)
Main.Position         = UDim2.new(0.5, -185, 0.5, -280)
Main.BackgroundColor3 = C.bg
Main.BorderSizePixel  = 0
Main.Active           = true
Main.Draggable        = true
Main.Parent           = SG
corner(Main, 10)
stroke(Main, C.accent, 1.5)

-- Barra de titulo
local TitleBar = Instance.new("Frame")
TitleBar.Size             = UDim2.new(1, 0, 0, 48)
TitleBar.BackgroundColor3 = C.panel
TitleBar.BorderSizePixel  = 0
TitleBar.Parent           = Main
corner(TitleBar, 10)

-- Fix esquinas inferiores de TitleBar
local TitleFix = Instance.new("Frame")
TitleFix.Size             = UDim2.new(1, 0, 0.5, 0)
TitleFix.Position         = UDim2.new(0, 0, 0.5, 0)
TitleFix.BackgroundColor3 = C.panel
TitleFix.BorderSizePixel  = 0
TitleFix.Parent           = TitleBar

local TitleIcon = label(TitleBar, "  SHIINA MUSIC", 15, C.accent, true)
TitleIcon.Size     = UDim2.new(1, -50, 1, 0)
TitleIcon.Position = UDim2.new(0, 0, 0, 0)
TitleIcon.TextXAlignment = Enum.TextXAlignment.Left

local SubTitle = label(TitleBar, "Delta Edition v1.0", 11, C.subtext, false)
SubTitle.Size     = UDim2.new(1, -50, 0, 14)
SubTitle.Position = UDim2.new(0, 12, 1, -16)

-- Boton minimizar / cerrar
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size             = UDim2.new(0, 30, 0, 30)
CloseBtn.Position         = UDim2.new(1, -38, 0, 9)
CloseBtn.Text             = "X"
CloseBtn.TextSize         = 13
CloseBtn.Font             = Enum.Font.GothamBold
CloseBtn.TextColor3       = C.text
CloseBtn.BackgroundColor3 = C.accentDim
CloseBtn.BorderSizePixel  = 0
CloseBtn.Parent           = TitleBar
corner(CloseBtn, 6)

CloseBtn.MouseButton1Click:Connect(function()
    if soundObj then soundObj:Stop() end
    SG:Destroy()
end)

-- ── SECCION BUSQUEDA ────────────────────────────
local SearchBox = Instance.new("TextBox")
SearchBox.Size             = UDim2.new(0, 270, 0, 38)
SearchBox.Position         = UDim2.new(0, 10, 0, 56)
SearchBox.PlaceholderText  = "Buscar cancion o pegar link YT..."
SearchBox.Text             = ""
SearchBox.TextSize         = 13
SearchBox.Font             = Enum.Font.Gotham
SearchBox.TextColor3       = C.text
SearchBox.PlaceholderColor3= C.subtext
SearchBox.BackgroundColor3 = C.row
SearchBox.BorderSizePixel  = 0
SearchBox.ClearTextOnFocus = false
SearchBox.Parent           = Main
corner(SearchBox, 7)
stroke(SearchBox, C.bar, 1)

-- padding izq
local SBPad = Instance.new("UIPadding")
SBPad.PaddingLeft = UDim.new(0, 8)
SBPad.Parent      = SearchBox

local SearchBtn = Instance.new("TextButton")
SearchBtn.Size             = UDim2.new(0, 76, 0, 38)
SearchBtn.Position         = UDim2.new(0, 284, 0, 56)
SearchBtn.Text             = "BUSCAR"
SearchBtn.TextSize         = 13
SearchBtn.Font             = Enum.Font.GothamBold
SearchBtn.TextColor3       = C.white
SearchBtn.BackgroundColor3 = C.accent
SearchBtn.BorderSizePixel  = 0
SearchBtn.Parent           = Main
corner(SearchBtn, 7)

-- ── RESULTADOS ──────────────────────────────────
local ResultsLabel = label(Main, "Resultados:", 12, C.subtext, false)
ResultsLabel.Size     = UDim2.new(1, -20, 0, 16)
ResultsLabel.Position = UDim2.new(0, 10, 0, 101)

local ResultsFrame = Instance.new("ScrollingFrame")
ResultsFrame.Size                 = UDim2.new(1, -20, 0, 155)
ResultsFrame.Position             = UDim2.new(0, 10, 0, 119)
ResultsFrame.BackgroundColor3     = C.panel
ResultsFrame.BorderSizePixel      = 0
ResultsFrame.ScrollBarThickness   = 4
ResultsFrame.ScrollBarImageColor3 = C.accent
ResultsFrame.CanvasSize           = UDim2.new(0, 0, 0, 0)
ResultsFrame.AutomaticCanvasSize  = Enum.AutomaticSize.Y
ResultsFrame.Parent               = Main
corner(ResultsFrame, 8)
stroke(ResultsFrame, C.bar, 1)

local RList = Instance.new("UIListLayout")
RList.Padding       = UDim.new(0, 3)
RList.SortOrder     = Enum.SortOrder.LayoutOrder
RList.Parent        = ResultsFrame

local RPad = Instance.new("UIPadding")
RPad.PaddingTop    = UDim.new(0, 4)
RPad.PaddingLeft   = UDim.new(0, 4)
RPad.PaddingRight  = UDim.new(0, 4)
RPad.PaddingBottom = UDim.new(0, 4)
RPad.Parent        = ResultsFrame

-- ── NOW PLAYING ─────────────────────────────────
local NPBar = Instance.new("Frame")
NPBar.Size             = UDim2.new(1, -20, 0, 52)
NPBar.Position         = UDim2.new(0, 10, 0, 282)
NPBar.BackgroundColor3 = C.panel
NPBar.BorderSizePixel  = 0
NPBar.Parent           = Main
corner(NPBar, 8)
stroke(NPBar, C.accentDim, 1)

local NowPlayingIcon = label(NPBar, "NOW PLAYING", 10, C.accent, true)
NowPlayingIcon.Size     = UDim2.new(1, -10, 0, 14)
NowPlayingIcon.Position = UDim2.new(0, 8, 0, 5)

local NowPlayingText = label(NPBar, "Nada reproduciendose...", 13, C.text, false)
NowPlayingText.Size         = UDim2.new(1, -10, 0, 18)
NowPlayingText.Position     = UDim2.new(0, 8, 0, 20)
NowPlayingText.TextTruncate = Enum.TextTruncate.AtEnd

-- ── PROGRESS BAR ────────────────────────────────
local ProgressBG = Instance.new("Frame")
ProgressBG.Size             = UDim2.new(1, -20, 0, 6)
ProgressBG.Position         = UDim2.new(0, 10, 0, 342)
ProgressBG.BackgroundColor3 = C.bar
ProgressBG.BorderSizePixel  = 0
ProgressBG.Parent           = Main
corner(ProgressBG, 3)

local ProgressFill = Instance.new("Frame")
ProgressFill.Size             = UDim2.new(0, 0, 1, 0)
ProgressFill.BackgroundColor3 = C.barFill
ProgressFill.BorderSizePixel  = 0
ProgressFill.Parent           = ProgressBG
corner(ProgressFill, 3)

local TimeLabel = label(Main, "0:00 / 0:00", 11, C.subtext, false, Enum.TextXAlignment.Right)
TimeLabel.Size     = UDim2.new(1, -20, 0, 14)
TimeLabel.Position = UDim2.new(0, 10, 0, 350)

-- ── CONTROLES ───────────────────────────────────
local function makeCtrlBtn(txt, color, xPos)
    local b = Instance.new("TextButton")
    b.Size             = UDim2.new(0, 80, 0, 36)
    b.Position         = UDim2.new(0, xPos, 0, 370)
    b.Text             = txt
    b.TextSize         = 13
    b.Font             = Enum.Font.GothamBold
    b.TextColor3       = C.white
    b.BackgroundColor3 = color
    b.BorderSizePixel  = 0
    b.Parent           = Main
    corner(b, 7)
    return b
end

local PlayBtn  = makeCtrlBtn("PLAY",  C.green,       10)
local PauseBtn = makeCtrlBtn("PAUSE", C.accentDim,   98)
local SkipBtn  = makeCtrlBtn("SKIP",  C.accent,      186)
local StopBtn  = makeCtrlBtn("STOP",  C.disabled,    274)

-- ── VOLUMEN ──────────────────────────────────────
local VolLabel = label(Main, "VOL: 70%", 12, C.subtext, false)
VolLabel.Size     = UDim2.new(0, 70, 0, 16)
VolLabel.Position = UDim2.new(0, 10, 0, 416)

local VolBG = Instance.new("Frame")
VolBG.Size             = UDim2.new(1, -90, 0, 8)
VolBG.Position         = UDim2.new(0, 82, 0, 418)
VolBG.BackgroundColor3 = C.bar
VolBG.BorderSizePixel  = 0
VolBG.Parent           = Main
corner(VolBG, 4)

local VolFill = Instance.new("Frame")
VolFill.Size             = UDim2.new(volume, 0, 1, 0)
VolFill.BackgroundColor3 = C.accent
VolFill.BorderSizePixel  = 0
VolFill.Parent           = VolBG
corner(VolFill, 4)

local VolKnob = Instance.new("Frame")
VolKnob.Size             = UDim2.new(0, 16, 0, 16)
VolKnob.Position         = UDim2.new(volume, -8, 0.5, -8)
VolKnob.BackgroundColor3 = C.white
VolKnob.BorderSizePixel  = 0
VolKnob.Parent           = VolBG
corner(VolKnob, 8)

-- Drag del knob de volumen
local volDragging = false
VolKnob.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        volDragging = true
    end
end)
VolBG.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        volDragging = true
        local rel = math.clamp((i.Position.X - VolBG.AbsolutePosition.X) / VolBG.AbsoluteSize.X, 0, 1)
        volume = rel
        VolFill.Size     = UDim2.new(rel, 0, 1, 0)
        VolKnob.Position = UDim2.new(rel, -8, 0.5, -8)
        VolLabel.Text    = "VOL: " .. math.floor(rel * 100) .. "%"
        if soundObj then soundObj.Volume = volume end
    end
end)
game:GetService("UserInputService").InputChanged:Connect(function(i)
    if volDragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMove) then
        local rel = math.clamp((i.Position.X - VolBG.AbsolutePosition.X) / VolBG.AbsoluteSize.X, 0, 1)
        volume = rel
        VolFill.Size     = UDim2.new(rel, 0, 1, 0)
        VolKnob.Position = UDim2.new(rel, -8, 0.5, -8)
        VolLabel.Text    = "VOL: " .. math.floor(rel * 100) .. "%"
        if soundObj then soundObj.Volume = volume end
    end
end)
game:GetService("UserInputService").InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
        volDragging = false
    end
end)

-- ── COLA ────────────────────────────────────────
local QueueLabel = label(Main, "COLA:", 12, C.subtext, false)
QueueLabel.Size     = UDim2.new(1, -20, 0, 16)
QueueLabel.Position = UDim2.new(0, 10, 0, 436)

local QueueFrame = Instance.new("ScrollingFrame")
QueueFrame.Size                 = UDim2.new(1, -20, 0, 92)
QueueFrame.Position             = UDim2.new(0, 10, 0, 454)
QueueFrame.BackgroundColor3     = C.panel
QueueFrame.BorderSizePixel      = 0
QueueFrame.ScrollBarThickness   = 4
QueueFrame.ScrollBarImageColor3 = C.accent
QueueFrame.CanvasSize           = UDim2.new(0, 0, 0, 0)
QueueFrame.AutomaticCanvasSize  = Enum.AutomaticSize.Y
QueueFrame.Parent               = Main
corner(QueueFrame, 8)
stroke(QueueFrame, C.bar, 1)

local QList = Instance.new("UIListLayout")
QList.Padding   = UDim.new(0, 2)
QList.SortOrder = Enum.SortOrder.LayoutOrder
QList.Parent    = QueueFrame

local QPad = Instance.new("UIPadding")
QPad.PaddingTop    = UDim.new(0, 4)
QPad.PaddingLeft   = UDim.new(0, 4)
QPad.PaddingRight  = UDim.new(0, 4)
QPad.PaddingBottom = UDim.new(0, 4)
QPad.Parent        = QueueFrame

-- ══════════════════════════════════════════════
--  LOGICA DE COLA Y REPRODUCCION
-- ══════════════════════════════════════════════
local function refreshQueueUI()
    for _, c in ipairs(QueueFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for i, item in ipairs(queue) do
        local row = Instance.new("Frame")
        row.Size             = UDim2.new(1, -2, 0, 28)
        row.BackgroundColor3 = (i == currentIdx) and C.accentDim or C.row
        row.BorderSizePixel  = 0
        row.LayoutOrder      = i
        row.Parent           = QueueFrame
        corner(row, 5)

        local num = label(row, tostring(i) .. ".", 11, (i == currentIdx) and C.white or C.subtext, true)
        num.Size     = UDim2.new(0, 24, 1, 0)
        num.Position = UDim2.new(0, 4, 0, 0)
        num.TextXAlignment = Enum.TextXAlignment.Center

        local ttl = label(row, item.title, 12, (i == currentIdx) and C.white or C.text, false)
        ttl.Size         = UDim2.new(1, -54, 1, 0)
        ttl.Position     = UDim2.new(0, 28, 0, 0)
        ttl.TextTruncate = Enum.TextTruncate.AtEnd

        local rmBtn = Instance.new("TextButton")
        rmBtn.Size             = UDim2.new(0, 20, 0, 20)
        rmBtn.Position         = UDim2.new(1, -24, 0.5, -10)
        rmBtn.Text             = "x"
        rmBtn.TextSize         = 11
        rmBtn.Font             = Enum.Font.GothamBold
        rmBtn.TextColor3       = C.subtext
        rmBtn.BackgroundTransparency = 1
        rmBtn.BorderSizePixel  = 0
        rmBtn.Parent           = row
        local capturedI = i
        rmBtn.MouseButton1Click:Connect(function()
            table.remove(queue, capturedI)
            if currentIdx >= capturedI and currentIdx > 1 then
                currentIdx = currentIdx - 1
            end
            refreshQueueUI()
        end)
    end
end

local function playIndex(idx)
    if idx < 1 or idx > #queue then return end
    currentIdx = idx
    local item = queue[idx]

    NowPlayingText.Text = "Cargando: " .. item.title
    notify("Cargando: " .. item.title, true)
    refreshQueueUI()

    if item.audioUrl then
        -- ya tenemos URL cacheada
        playSound(item.audioUrl, function()
            playIndex(currentIdx + 1)
        end)
        NowPlayingText.Text = item.title
        updateProgressBar(ProgressFill, TimeLabel)
        refreshQueueUI()
    else
        -- buscar via Cobalt
        getCobaltAudio(item.videoId, function(url, err)
            if not url then
                notify("Error Cobalt: " .. (err or "?"), false)
                NowPlayingText.Text = "Error al cargar"
                return
            end
            queue[idx].audioUrl = url
            playSound(url, function()
                playIndex(currentIdx + 1)
            end)
            NowPlayingText.Text = item.title
            updateProgressBar(ProgressFill, TimeLabel)
            refreshQueueUI()
        end)
    end
end

local function addToQueue(item)
    table.insert(queue, item)
    refreshQueueUI()
    notify("'" .. item.title .. "' agregado a la cola", true)
    -- auto-play si no hay nada sonando
    if not isPlaying then
        playIndex(#queue)
    end
end

-- ══════════════════════════════════════════════
--  RESULTADO ROW FACTORY
-- ══════════════════════════════════════════════
local function makeResultRow(result)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, -2, 0, 46)
    row.BackgroundColor3 = C.row
    row.BorderSizePixel  = 0
    row.Parent           = ResultsFrame
    corner(row, 6)

    local titleL = label(row, result.title, 13, C.text, false)
    titleL.Size         = UDim2.new(1, -90, 0, 18)
    titleL.Position     = UDim2.new(0, 8, 0, 5)
    titleL.TextTruncate = Enum.TextTruncate.AtEnd

    local meta = label(row, result.channel .. "  |  " .. result.duration, 11, C.subtext, false)
    meta.Size     = UDim2.new(1, -90, 0, 14)
    meta.Position = UDim2.new(0, 8, 0, 25)

    local addBtn = Instance.new("TextButton")
    addBtn.Size             = UDim2.new(0, 72, 0, 28)
    addBtn.Position         = UDim2.new(1, -80, 0.5, -14)
    addBtn.Text             = "+ COLA"
    addBtn.TextSize         = 12
    addBtn.Font             = Enum.Font.GothamBold
    addBtn.TextColor3       = C.white
    addBtn.BackgroundColor3 = C.accent
    addBtn.BorderSizePixel  = 0
    addBtn.Parent           = row
    corner(addBtn, 6)

    addBtn.MouseButton1Click:Connect(function()
        addToQueue({ title = result.title, videoId = result.id, audioUrl = nil })
    end)

    -- hover
    row.MouseEnter:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.15), { BackgroundColor3 = C.rowHov }):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenService:Create(row, TweenInfo.new(0.15), { BackgroundColor3 = C.row }):Play()
    end)
end

-- ══════════════════════════════════════════════
--  BUSQUEDA — detecta link directo o texto
-- ══════════════════════════════════════════════
local function doSearch()
    local q = SearchBox.Text
    if not q or #q < 2 then return end

    -- Limpiar resultados anteriores
    for _, c in ipairs(ResultsFrame:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    -- Detectar si es link de YouTube
    local videoId = q:match("v=([%w%-_]+)") or q:match("youtu%.be/([%w%-_]+)")
    if videoId then
        -- Link directo — agregar directamente
        local item = { title = "Video: " .. videoId, videoId = videoId, audioUrl = nil }
        addToQueue(item)
        return
    end

    notify("Buscando...", true)
    searchYouTube(q, function(results)
        -- limpiar loading
        for _, c in ipairs(ResultsFrame:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        if not results then
            notify("Sin resultados o error de red", false)
            local noR = label(ResultsFrame, "Sin resultados. Proba con otro termino.", 12, C.subtext, false, Enum.TextXAlignment.Center)
            noR.Size = UDim2.new(1, 0, 0, 40)
            return
        end
        for _, r in ipairs(results) do
            makeResultRow(r)
        end
    end)
end

SearchBtn.MouseButton1Click:Connect(doSearch)
SearchBox.FocusLost:Connect(function(enter)
    if enter then doSearch() end
end)

-- ══════════════════════════════════════════════
--  CONTROLES
-- ══════════════════════════════════════════════
PlayBtn.MouseButton1Click:Connect(function()
    if soundObj and not isPlaying then
        soundObj:Play()
        isPlaying = true
        updateProgressBar(ProgressFill, TimeLabel)
    elseif currentIdx == 0 and #queue > 0 then
        playIndex(1)
    end
end)

PauseBtn.MouseButton1Click:Connect(function()
    if soundObj and isPlaying then
        soundObj:Pause()
        isPlaying = false
        stopProgress()
    end
end)

SkipBtn.MouseButton1Click:Connect(function()
    if #queue > 0 then
        local next = currentIdx + 1
        if next > #queue then next = 1 end
        playIndex(next)
    end
end)

StopBtn.MouseButton1Click:Connect(function()
    if soundObj then
        soundObj:Stop()
        soundObj:Destroy()
        soundObj = nil
    end
    stopProgress()
    isPlaying = false
    currentIdx = 0
    NowPlayingText.Text = "Nada reproduciendose..."
    TimeLabel.Text      = "0:00 / 0:00"
    ProgressFill.Size   = UDim2.new(0, 0, 1, 0)
    refreshQueueUI()
end)

-- ══════════════════════════════════════════════
print("[ShiinaMusic] Cargado. Busca algo o pega un link de YT.")
notify("Shiina Music v1.0 listo", true)
