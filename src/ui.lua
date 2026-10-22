local palette = require("src.palette")
local Document = require("src.document")
local UI = {}
UI.__index = UI

local C = {
    top = {0.080, 0.106, 0.155}, side = {0.100, 0.133, 0.190},
    panel = {0.090, 0.118, 0.172}, surface = {0.145, 0.187, 0.256},
    surface2 = {0.175, 0.219, 0.299}, accent = {0.260, 0.800, 0.789},
    white = {0.937, 0.963, 0.980}, muted = {0.625, 0.692, 0.756},
    divider = {0.223, 0.280, 0.350}, red = {0.910, 0.370, 0.397},
}

local function fill(color, alpha)
    love.graphics.setColor(color[1], color[2], color[3], alpha or 1)
end

local function contains(x, y, box)
    return x >= box.x and x <= box.x + box.w
        and y >= box.y and y <= box.y + box.h
end

function UI.new()
    return setmetatable({
        hits = {}, modal = nil,
        small = love.graphics.newFont(12),
        font = love.graphics.newFont(14),
        large = love.graphics.newFont(21),
    }, UI)
end

function UI:rect(x, y, w, h, color, radius)
    fill(color)
    love.graphics.rectangle("fill", x, y, w, h, radius or 0, radius or 0)
end

function UI:print(text, x, y, color, font, width, align)
    love.graphics.setFont(font or self.font)
    fill(color or C.white)
    if width then
        love.graphics.printf(text, x, y, width, align or "left")
    else
        love.graphics.print(text, x, y)
    end
end

function UI:register(x, y, w, h, action)
    self.hits[#self.hits + 1] = {x=x, y=y, w=w, h=h, action=action}
end

function UI:button(x, y, w, h, text, action, style)
    local mx, my = love.mouse.getPosition()
    local hovered = contains(mx, my, {x=x, y=y, w=w, h=h})
    local base = style == "primary" and C.accent or C.surface
    if style == "danger" then base = C.red end
    if style == "ghost" then base = C.side end
    self:rect(x, y, w, h, hovered and C.surface2 or base, 7)
    self:print(text, x + 2, y + (h - self.font:getHeight()) / 2, 
        style == "primary" and C.top or C.white, self.font, w - 4, "center")
    if action then self:register(x, y, w, h, action) end
end

function UI:slider(x, y, w, value, label, action, suffix)
    self:print(label, x, y - 18, C.muted, self.small)
    self:print(suffix or "", x, y - 18, C.white, self.small, w, "right")
    self:rect(x, y + 5, w, 5, C.surface2, 3)
    self:rect(x, y + 5, w * value, 5, C.accent, 3)
    fill(C.white)
    love.graphics.circle("fill", x + w * value, y + 7.5, 7)
    self:register(x - 8, y - 4, w + 16, 24, function(px)
        action(math.max(0, math.min(1, (px - x) / w)))
    end)
end

function UI:confirm(message, action)
    self.modal = {kind = "confirm", message = message, action = action}
end

function UI:askSave(app)
    self.modal = {kind = "save", value = app.doc.name}
end

function UI:askOpen(app)
    local open = function()
        self.modal = {kind = "open", projects = Document.listProjects()}
    end
    if app.doc.dirty then
        self:confirm("Alteracoes nao salvas serao perdidas.", open)
    else
        open()
    end
end

function UI:click(x, y)
    for i = #self.hits, 1, -1 do
        local hit = self.hits[i]
        if contains(x, y, hit) then
            if hit.action then hit.action(x, y) end
            return true
        end
    end
    return self.modal ~= nil -- a caixa modal bloqueia a tela atras
end

function UI:keypressed(app, key)
    if not self.modal then return false end
    local modal = self.modal
    if key == "escape" then self.modal = nil; return true end
    if modal.kind == "save" then
        if key == "return" or key == "kpenter" then
            self.modal = nil
            app:saveProject(modal.value)
        elseif key == "backspace" then
            local utf8 = require("utf8")
            local byteoffset = utf8.offset(modal.value, -1)
            if byteoffset then modal.value = modal.value:sub(1, byteoffset - 1) end
        end
    elseif modal.kind == "confirm" then
        if key == "return" then self.modal = nil; modal.action() end
    end
    return true
end

function UI:textinput(text)
    if self.modal and self.modal.kind == "save" then
        self.modal.value = (self.modal.value .. text:gsub("[\r\n\t]", "")):sub(1, 64)
    end
end

function UI:drawModal(app)
    if not self.modal then return end
    local modal = self.modal
    local w, h = love.graphics.getDimensions()
    fill(C.top, 0.82)
    love.graphics.rectangle("fill", 0, 0, w, h)
    self.hits = {} -- proibe clicar nas ferramentas atras do modal
    local boxW, boxH = 460, modal.kind == "open" and 400 or 214
    local x, y = (w - boxW) / 2, (h - boxH) / 2
    self:rect(x, y, boxW, boxH, C.side, 14)
    self:print("Inkora", x + 25, y + 19, C.accent, self.large)
    if modal.kind == "confirm" then
        self:print("Descartar alteracoes?", x + 25, y + 62, C.white)
        self:print(modal.message, x + 25, y + 88, C.muted, self.small)
        self:button(x + 24, y + boxH - 62, 194, 38, "Cancelar", function() self.modal = nil end)
        self:button(x + 240, y + boxH - 62, 194, 38, "Descartar", function()
            self.modal = nil
            modal.action()
        end, "danger")
    elseif modal.kind == "save" then
        self:print("Nome do projeto:", x + 25, y + 63, C.muted)
        self:rect(x + 24, y + 92, 412, 38, C.panel, 7)
        self:print(modal.value .. "_", x + 36, y + 101, C.white)
        self:button(x + 24, y + boxH - 62, 194, 38, "Cancelar", function() self.modal = nil end)
        self:button(x + 240, y + boxH - 62, 194, 38, "Salvar projeto", function()
            self.modal = nil
            app:saveProject(modal.value)
        end, "primary")
    elseif modal.kind == "open" then
        self:print("Projetos salvos", x + 25, y + 60, C.white)
        if #modal.projects == 0 then
            self:print("Nenhum projeto salvo ainda.", x + 25, y + 121, C.muted)
        end
        for i = 1, math.min(6, #modal.projects) do
            local project = modal.projects[i]
            self:button(x + 24, y + 94 + (i-1) * 40, 412, 34,
                project.name, function()
                    self.modal = nil
                    app:openProject(project.key)
                end, "ghost")
        end
        self:button(x + 282, y + boxH - 49, 154, 32, "Fechar", function()
            self.modal = nil
        end)
    end
end

function UI:draw(app)
    self.hits = {}
    love.graphics.push("all")
    local w, h = love.graphics.getDimensions()
    local right = w - 280

    self:rect(0, 0, w, 58, C.top)
    self:rect(0, 58, 74, h-92, C.side)
    self:rect(right, 58, 280, h-92, C.panel)
    self:rect(0, h-34, w, 34, C.top)
    self:rect(74, 58, 1, h-92, C.divider)
    self:rect(right, 58, 1, h-92, C.divider)

    self:print("INKORA", 20, 16, C.accent, self.large)
    self:button(173, 10, 75, 37, "Novo", function()
        local create = function() app:newDocument() end
        if app.doc.dirty then
            self:confirm("O documento atual nao foi salvo.", create)
        else create() end
    end)
    self:button(258, 10, 78, 37, "Salvar", function()
        if app.doc.projectKey then app:saveProject(app.doc.name)
        else self:askSave(app) end
    end)
    self:button(346, 10, 75, 37, "Abrir", function() self:askOpen(app) end)
    self:button(431, 10, 91, 37, "PNG", function() app:exportPNG() end)
    self:button(540, 10, 69, 37, "Voltar", function() app.doc:undo() end)
    self:button(618, 10, 77, 37, "Refazer", function() app.doc:redo() end)
    self:button(707, 10, 95, 37, "Ajustar", function() app:fitView() end)

    self:print("FERRAMENTAS", 7, 80, C.muted, self.small, 60, "center")
    local tools = {
        {"Pincel", "brush", "B"}, {"Borracha", "eraser", "E"}, {"Mover", "hand", "H"}
    }
    for i, t in ipairs(tools) do
        local yy = 111 + (i-1)*80
        self:button(8, yy, 58, 40, t[3], function() app.tool = t[2] end,
            app.tool == t[2] and "primary" or nil)
        self:print(t[1], 4, yy + 44, C.muted, self.small, 66, "center")
    end
    self:print("100%", 6, h-88, C.muted, self.small, 64, "center")
    self:button(9, h-67, 56, 26, "F", function() app:fitView() end)

    local px, pw = right + 20, 240
    self:print("PINCEL", px, 78, C.white, self.font)
    self:print(app.tool == "eraser" and "Borracha" or app.tool == "hand" and "Mover" or "Redondo", px, 104, C.muted, self.small)
    self:slider(px+6, 147, pw-12, (app.brushSize - 1)/119, "Tamanho",
        function(v) app.brushSize = math.max(1, math.floor(1 + v * 119 + 0.5)) end,
        tostring(app.brushSize) .. " px")
    self:slider(px+6, 203, pw-12, app.brushOpacity, "Opacidade do traco",
        function(v) app.brushOpacity = math.max(0.05, v) end,
        tostring(math.floor(app.brushOpacity * 100 + 0.5)) .. "%")

    self:print("CORES", px, 242, C.white)
    for i, swatch in ipairs(palette) do
        local col, row = (i-1)%6, math.floor((i-1)/6)
        local bx, by = px + col*40, 268 + row*39
        if app.colorIndex == i then
            fill(C.accent)
            love.graphics.rectangle("line", bx-3, by-3, 34, 34, 6, 6)
        end
        fill(swatch)
        love.graphics.rectangle("fill", bx, by, 28, 28, 5, 5)
        self:register(bx-3, by-3, 34, 34, function()
            app.colorIndex = i
            app.color = swatch
            if app.tool == "eraser" then app.tool = "brush" end
        end)
    end

    self:rect(px, 395, pw, 1, C.divider)
    self:print("CAMADAS", px, 407, C.white)
    self:button(px, 439, 51, 31, "+", function()
        if not app.doc:addLayer() then app:statusMessage("Limite de 16 camadas") end
    end)
    self:button(px+61, 439, 51, 31, "-", function() app.doc:removeLayer() end)
    self:button(px+122, 439, 51, 31, "Cima", function() app.doc:moveLayer(1) end)
    self:button(px+183, 439, 57, 31, "Baixo", function() app.doc:moveLayer(-1) end)

    local availableRows = math.max(1, math.floor((h - 590)/42))
    local doc = app.doc
    local rowStart = math.max(1, math.min(doc.selected - availableRows + 1, #doc.layers - availableRows + 1))
    for screenRow = 1, math.min(#doc.layers, availableRows) do
        local index = #doc.layers - screenRow + 1
        -- Manter a camada selecionada visivel com lista rolando de cima para baixo.
        local topIndex = math.min(#doc.layers, math.max(availableRows, doc.selected + availableRows - 1))
        index = topIndex - screenRow + 1
        if index >= 1 and index <= #doc.layers then
            local layer = doc.layers[index]
            local yy = 481 + (screenRow-1)*42
            self:rect(px, yy, pw, 37, index == doc.selected and C.surface2 or C.surface, 7)
            self:button(px+6, yy+4, 47, 29, layer.visible and "Ver" or "Off", function()
                doc:toggleLayer(index)
            end, "ghost")
            self:print(layer.name, px+61, yy+10, index == doc.selected and C.accent or C.white, self.small)
            self:register(px+58, yy, pw-60, 37, function()
                doc.selected = index
            end)
        end
    end
    local l = doc.layers[doc.selected]
    if l then
        self:slider(px+6, h-68, pw-12, l.opacity, "Opacidade da camada",
            function(v) doc:setLayerOpacity(doc.selected, v) end,
            tostring(math.floor(l.opacity*100+0.5)) .. "%")
    end

    local status = app.message or "Pronto"
    self:print(status, 14, h-26, C.white, self.small, math.max(200,w-610))
    self:print(("%dx%d  |  %d camadas  |  zoom %d%%"):format(
        doc.width, doc.height, #doc.layers, app.zoom*100),
        w-600, h-26, C.muted, self.small, 585, "right")
    if self.modal then self:drawModal(app) end
    love.graphics.pop()
end

return UI
