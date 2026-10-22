local Document = require("src.document")
local Brush = require("src.brush")
local UI = require("src.ui")
local palette = require("src.palette")

local app = {
    tool = "brush", brushSize = 12, brushOpacity = 1,
    colorIndex = 1, color = palette[1],
    zoom = 1, offsetX = 0, offsetY = 0, dragging = nil,
    message = "Bem-vindo ao Inkora! Pinte com o mouse ou arraste um PNG.",
}

local function bounds()
    local w, h = love.graphics.getDimensions()
    return 75, 59, w - 281, h - 35
end

local function inWorkspace(x, y)
    local l,t,r,b = bounds()
    return x >= l and x < r and y >= t and y < b
end

function app:statusMessage(message)
    self.message = message
end

function app:fitView()
    local l,t,r,b = bounds()
    local aw, ah = r-l-80, b-t-78
    self.zoom = math.min(1, aw/self.doc.width, ah/self.doc.height)
    self.zoom = math.max(0.08, self.zoom)
    self.offsetX = (l+r-self.doc.width*self.zoom)/2
    self.offsetY = (t+b-self.doc.height*self.zoom)/2
end

function app:screenToDocument(x, y)
    return (x-self.offsetX)/self.zoom, (y-self.offsetY)/self.zoom
end

function app:zoomAt(mult, x, y)
    if not inWorkspace(x,y) then return end
    local docx, docy = self:screenToDocument(x,y)
    self.zoom = math.max(0.08, math.min(8, self.zoom * mult))
    self.offsetX = x - docx*self.zoom
    self.offsetY = y - docy*self.zoom
end

function app:newDocument()
    self.doc = Document.new(1280, 800, "Novo desenho")
    self:fitView()
    self:statusMessage("Novo documento 1280 x 800")
end

function app:saveProject(name)
    local ok, result = pcall(function() return self.doc:save(name) end)
    if ok then
        self:statusMessage("Projeto salvo: " .. result)
    else
        self:statusMessage("Falha ao salvar: " .. tostring(result))
    end
end

function app:openProject(key)
    local ok, result = pcall(Document.load, key)
    if ok then
        self.doc = result
        self:fitView()
        self:statusMessage("Projeto aberto: " .. self.doc.name)
    else
        self:statusMessage("Falha ao abrir: " .. tostring(result))
    end
end

function app:exportPNG()
    local ok, result = pcall(function() return self.doc:exportPNG() end)
    if ok then self:statusMessage("PNG exportado: " .. result)
    else self:statusMessage("Falha na exportacao: " .. tostring(result)) end
end

function app:startStroke(x, y)
    local dx, dy = self:screenToDocument(x,y)
    if dx < 0 or dy < 0 or dx >= self.doc.width or dy >= self.doc.height then return end
    local layer = self.doc.layers[self.doc.selected]
    if not layer or not layer.visible then
        self:statusMessage("Ative a visibilidade da camada para desenhar.")
        return
    end
    self.doc:checkpoint()
    self.dragging = {kind="draw", x=dx, y=dy}
    Brush.segment(layer.canvas, dx, dy, dx, dy,
        self.color, self.brushSize, self.brushOpacity, self.tool=="eraser")
end

function app:moveStroke(x, y)
    if not self.dragging then return end
    if self.dragging.kind == "pan" then return end
    local dx, dy = self:screenToDocument(x,y)
    local layer = self.doc.layers[self.doc.selected]
    Brush.segment(layer.canvas, self.dragging.x, self.dragging.y, dx, dy,
        self.color, self.brushSize, self.brushOpacity, self.tool=="eraser")
    self.dragging.x, self.dragging.y = dx, dy
end

function love.load()
    love.graphics.setBackgroundColor(0.15, 0.19, 0.25)
    love.keyboard.setKeyRepeat(true)
    app.ui = UI.new()
    app:newDocument()
    app:statusMessage("Inkora inicializado. B: pincel | E: borracha | F: ajustar")
end

function love.draw()
    love.graphics.clear(0.15, 0.19, 0.25, 1)
    local l,t,r,b = bounds()
    love.graphics.setScissor(l,t,r-l,b-t)
    local x,y = app.offsetX,app.offsetY
    local w,h = app.doc.width*app.zoom,app.doc.height*app.zoom
    love.graphics.setColor(0.05, 0.07, 0.11, 0.22)
    love.graphics.rectangle("fill", x+9, y+13, w, h)
    app.doc:draw(x,y,app.zoom)
    love.graphics.setColor(0.45,0.50,0.55,0.55)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x-0.5,y-0.5,w+1,h+1)
    love.graphics.setScissor()

    if app.tool ~= "hand" and not app.ui.modal then
        local mx,my = love.mouse.getPosition()
        if inWorkspace(mx,my) then
            love.graphics.setColor(0.20,0.85,0.85,0.75)
            love.graphics.setLineWidth(1)
            love.graphics.circle("line", mx, my, math.max(2,app.brushSize*app.zoom/2))
        end
    end
    app.ui:draw(app)
end

function love.mousepressed(x,y,button)
    if button == 1 and app.ui:click(x,y) then return end
    if not inWorkspace(x,y) or app.ui.modal then return end
    if button == 2 or (button==1 and (app.tool=="hand" or love.keyboard.isDown("space"))) then
        app.dragging = {kind="pan"}
        return
    end
    if button == 1 and app.tool ~= "hand" then app:startStroke(x,y) end
end

function love.mousemoved(x,y,dx,dy)
    if not app.dragging then return end
    if app.dragging.kind == "pan" then
        app.offsetX = app.offsetX + dx
        app.offsetY = app.offsetY + dy
    elseif app.dragging.kind == "draw" then
        app:moveStroke(x,y)
    end
end

function love.mousereleased(_,_,button)
    if button == 1 or button == 2 then app.dragging = nil end
end

function love.wheelmoved(_,y)
    if app.ui.modal then return end
    local x,my = love.mouse.getPosition()
    if love.keyboard.isDown("lshift","rshift") then
        app.brushSize = math.max(1,math.min(120,app.brushSize+(y>0 and 2 or -2)))
    else
        app:zoomAt(1.15^y,x,my)
    end
end

function love.keypressed(key,_,isrepeat)
    if app.ui:keypressed(app,key) then return end
    local ctrl = love.keyboard.isDown("lctrl","rctrl")
    local shift = love.keyboard.isDown("lshift","rshift")
    if ctrl and key == "z" then app.doc:undo()
    elseif ctrl and key == "y" then app.doc:redo()
    elseif ctrl and key == "n" then
        if app.doc.dirty then
            app.ui:confirm("O documento atual nao foi salvo.", function() app:newDocument() end)
        else app:newDocument() end
    elseif ctrl and key == "o" then app.ui:askOpen(app)
    elseif ctrl and shift and key == "s" then app:exportPNG()
    elseif ctrl and key == "s" then
        if app.doc.projectKey then app:saveProject(app.doc.name)
        else app.ui:askSave(app) end
    elseif not ctrl and not isrepeat then
        if key == "b" then app.tool="brush"
        elseif key == "e" then app.tool="eraser"
        elseif key == "h" then app.tool="hand"
        elseif key == "f" then app:fitView()
        elseif key == "[" then app.brushSize=math.max(1,app.brushSize-2)
        elseif key == "]" then app.brushSize=math.min(120,app.brushSize+2)
        end
    end
end

function love.textinput(text)
    app.ui:textinput(text)
end

function love.filedropped(file)
    local filename = file:getFilename():lower()
    if not filename:match("%.png$") then
        app:statusMessage("Importacao disponivel somente para arquivos PNG.")
        return
    end
    local ok, err = pcall(function() app.doc:importPNG(file) end)
    if ok then app:statusMessage("PNG importado em nova camada.")
    else app:statusMessage("Falha ao importar: " .. tostring(err)) end
end

function love.resize()
    if app.doc then app:fitView() end
end

function love.update()
    if app.doc then
        love.window.setTitle("Inkora | " .. app.doc.name .. (app.doc.dirty and " *" or ""))
    end
end
