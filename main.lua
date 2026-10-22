local Document = require("src.document")
local Brush = require("src.brush")
local Fill = require("src.fill")
local Stabilizer = require("src.stabilizer")
local UI = require("src.ui")
local palette = require("src.palette")
local Native = require("src.native")

local app = {
    tool="brush", brushSize=12, brushOpacity=1, stabilization=0.25,
    brushHardness=0.82, brushSpacing=0.18, brushTip=0,
    brushFlow=1, pressureOpacity=0.75, tipMask=nil, activeTouch=nil,
    fillTolerance=0.02, colorIndex=1, color=palette[1],
    zoom=1, offsetX=0, offsetY=0, dragging=nil,
    message="Bem-vindo ao Inkora! B: pincel | G: balde | I: conta-gotas",
}

local SHAPES={line=true,rectangle=true,ellipse=true}

local function workspace()
    local w,h=love.graphics.getDimensions()
    return 75,59,w-281,h-35
end

local function onWorkspace(x,y)
    local l,t,r,b=workspace()
    return x>=l and x<r and y>=t and y<b
end

local function insideDocument(doc,x,y)
    return x>=0 and y>=0 and x<doc.width and y<doc.height
end

function app:statusMessage(message)
    self.message=message
end

function app:fitView()
    local l,t,r,b=workspace()
    local aw,ah=r-l-80,b-t-78
    self.zoom=math.max(0.08,math.min(1,aw/self.doc.width,ah/self.doc.height))
    self.offsetX=(l+r-self.doc.width*self.zoom)/2
    self.offsetY=(t+b-self.doc.height*self.zoom)/2
end

function app:screenToDocument(x,y)
    return (x-self.offsetX)/self.zoom,(y-self.offsetY)/self.zoom
end

function app:zoomAt(factor,x,y)
    if not onWorkspace(x,y) then return end
    local dx,dy=self:screenToDocument(x,y)
    self.zoom=math.max(0.08,math.min(8,self.zoom*factor))
    self.offsetX=x-dx*self.zoom
    self.offsetY=y-dy*self.zoom
end

function app:newDocument(w,h)
    self.doc=Document.new(w or 1280,h or 800,"Novo desenho")
    self.dragging=nil
    self:fitView()
    self:statusMessage(("Novo documento: %d x %d"):format(self.doc.width,self.doc.height))
end

function app:saveProject(name)
    local ok,result=pcall(function()return self.doc:save(name)end)
    if ok then self:statusMessage("Projeto salvo em "..result)
    else self:statusMessage("Falha ao salvar: "..tostring(result)) end
end

function app:openProject(key)
    local ok,result=pcall(Document.load,key)
    if ok then
        self.doc=result
        self.dragging=nil
        self:fitView()
        self:statusMessage("Projeto aberto: "..self.doc.name)
    else self:statusMessage("Falha ao abrir: "..tostring(result)) end
end

function app:exportPNG()
    local ok,result=pcall(function()return self.doc:exportPNG()end)
    if ok then self:statusMessage("PNG exportado: "..result)
    else self:statusMessage("Falha na exportacao: "..tostring(result)) end
end

-- Imported brush tips use PNG alpha, or inverted luminance for opaque PNGs.
function app:loadBrushMask(bytes,persist)
    assert(type(bytes)=="string" and #bytes>0 and #bytes<=12*1024*1024,
        "Arquivo de ponta muito grande (maximo 12 MB)")
    local source=love.filesystem.newFileData(bytes,"brush-tip.png")
    local pixels=love.image.newImageData(source)
    local mask=Native.createMask(pixels)
    if persist then
        assert(love.filesystem.createDirectory("brushes"))
        assert(love.filesystem.write("brushes/custom-tip.png",bytes))
    end
    self.tipMask=mask
    self.brushTip=3
    self.tool="brush"
    self.ui.tab="brush"
    self:statusMessage(("Ponta personalizada: %d x %d"):format(mask.width,mask.height))
end

function app:strokeStart(x,y,pressure)
    local dx,dy=self:screenToDocument(x,y)
    if not insideDocument(self.doc,dx,dy) then return end
    local layer=self.doc.layers[self.doc.selected]
    if not layer.visible then
        self:statusMessage("Ative a visibilidade da camada antes de desenhar.")
        return
    end
    self.doc:checkpoint()
    local nativeStroke=Brush.beginStroke(layer.canvas,{
        hardness=self.brushHardness,spacing=self.brushSpacing,
        tip=self.brushTip,aspect=0.3,
        angle=self.brushTip==3 and 0 or 25,grain=0.85,seed=239,
        mask=self.brushTip==3 and self.tipMask or nil,
        flow=self.brushFlow,pressureOpacity=self.pressureOpacity,
    })
    self.dragging={
        kind="draw",x=dx,y=dy,nativeStroke=nativeStroke,pressure=pressure or 1,
        smoother=Stabilizer.new(dx,dy,self.stabilization),
    }
    Brush.segment(layer.canvas,dx,dy,dx,dy,self.color,self.brushSize,
        self.brushOpacity,self.tool=="eraser",self.dragging.nativeStroke,
        self.dragging.pressure,self.dragging.pressure)
end

function app:strokeMove(x,y,pressure)
    local drag=self.dragging
    if not drag or drag.kind~="draw" then return end
    local targetX,targetY=self:screenToDocument(x,y)
    local dx,dy=drag.smoother:push(targetX,targetY)
    local layer=self.doc.layers[self.doc.selected]
    Brush.segment(layer.canvas,drag.x,drag.y,dx,dy,self.color,
        self.brushSize,self.brushOpacity,self.tool=="eraser",drag.nativeStroke,
        drag.pressure,pressure or 1)
    drag.pressure=pressure or 1
    drag.x,drag.y=dx,dy
    self.doc:markCompositeDirty()
end

function app:strokeEnd(x,y,pressure)
    local drag=self.dragging
    if not drag or drag.kind~="draw" then return end
    local dx,dy=self:screenToDocument(x,y)
    dx,dy=drag.smoother:finish(dx,dy)
    Brush.segment(self.doc.layers[self.doc.selected].canvas,drag.x,drag.y,
        dx,dy,self.color,self.brushSize,self.brushOpacity,self.tool=="eraser",
        drag.nativeStroke,drag.pressure,pressure or 1)
    self.doc:markCompositeDirty()
end

function app:shapeStart(x,y)
    local dx,dy=self:screenToDocument(x,y)
    if not insideDocument(self.doc,dx,dy) then return end
    if not self.doc.layers[self.doc.selected].visible then
        self:statusMessage("Camada oculta: ative-a antes de desenhar.")
        return
    end
    self.dragging={kind="shape",shape=self.tool,x1=dx,y1=dy,x2=dx,y2=dy}
end

function app:shapeMove(x,y)
    local d=self.dragging
    if d and d.kind=="shape" then
        d.x2,d.y2=self:screenToDocument(x,y)
    end
end

function app:shapeEnd(x,y)
    local d=self.dragging
    if not d or d.kind~="shape" then return end
    d.x2,d.y2=self:screenToDocument(x,y)
    self.doc:checkpoint()
    Brush.shape(self.doc.layers[self.doc.selected].canvas,d.shape,
        d.x1,d.y1,d.x2,d.y2,self.color,self.brushSize,self.brushOpacity)
end

function app:fillAt(x,y)
    local dx,dy=self:screenToDocument(x,y)
    if not insideDocument(self.doc,dx,dy) then return end
    local selected=self.doc.selected
    local layer=self.doc.layers[selected]
    if not layer.visible then
        self:statusMessage("Camada oculta: ative-a antes de preencher.")
        return
    end
    local success,err=pcall(function()
        local data=layer.canvas:newImageData()
        if Fill.apply(data,dx,dy,self.color,self.fillTolerance) then
            self.doc:replaceLayerData(selected,data)
            self:statusMessage("Regiao preenchida na camada "..selected)
        else self:statusMessage("Nenhuma alteracao na area selecionada") end
    end)
    if not success then self:statusMessage("Erro no balde: "..tostring(err)) end
end

function app:sampleAt(x,y)
    local dx,dy=self:screenToDocument(x,y)
    local ok,result=pcall(function()return self.doc:sampleColor(dx,dy)end)
    if ok and result then
        self.color=result
        self.colorIndex=nil
        self.tool="brush"
        self.ui.tab="brush"
        self:statusMessage("Cor capturada. Pincel ativado.")
    elseif not ok then
        self:statusMessage("Erro no conta-gotas: "..tostring(result))
    end
end

function love.load()
    love.graphics.setBackgroundColor(0.15,0.19,0.25)
    love.keyboard.setKeyRepeat(true)
    app.ui=UI.new()
    app:newDocument(1280,800)
    if love.filesystem.getInfo("brushes/custom-tip.png") then
        local bytes=love.filesystem.read("brushes/custom-tip.png")
        local ok,err=pcall(function() app:loadBrushMask(bytes,false) end)
        if not ok then app:statusMessage("Erro na ponta salva: "..tostring(err)) end
    end
    if Brush.nativeAvailable() then
        app:statusMessage("Motor C++ v1 ativo | LuaJIT FFI | projeto Inkora")
    else
        app:statusMessage("Prototipo Lua (C++ ausente): "..tostring(Brush.nativeError()))
    end
    if os.getenv("INKORA_TEST")=="1" then
        local ok,err=pcall(function()
            love.draw()
            app.ui.tab="layers"
            love.draw()
            require("tests.runtime").run()
        end)
        if not ok then
            io.stderr:write("INKORA_GPU_SMOKE_FAILED: "..tostring(err).."\n")
        end
        os.exit(ok and 0 or 1)
    end
end

function love.draw()
    love.graphics.clear(0.15,0.19,0.25,1)
    local l,t,r,b=workspace()
    love.graphics.setScissor(l,t,r-l,b-t)
    local x,y=app.offsetX,app.offsetY
    local w,h=app.doc.width*app.zoom,app.doc.height*app.zoom
    love.graphics.setColor(0.05,0.07,0.11,0.22)
    love.graphics.rectangle("fill",x+9,y+13,w,h)
    app.doc:draw(x,y,app.zoom)
    love.graphics.setColor(0.45,0.50,0.55,0.55)
    love.graphics.rectangle("line",x-0.5,y-0.5,w+1,h+1)

    -- Previa de formas: nao altera a camada antes de soltar o mouse.
    local d=app.dragging
    if d and d.kind=="shape" then
        love.graphics.push("all")
        love.graphics.translate(x,y)
        love.graphics.scale(app.zoom,app.zoom)
        Brush.shape(nil,d.shape,d.x1,d.y1,d.x2,d.y2,app.color,
            app.brushSize,app.brushOpacity)
        love.graphics.pop()
    end
    love.graphics.setScissor()

    if not app.ui.modal and app.tool~="hand" and app.tool~="fill"
        and app.tool~="picker" then
        local mx,my=love.mouse.getPosition()
        if onWorkspace(mx,my) then
            love.graphics.setColor(0.20,0.85,0.85,0.75)
            love.graphics.setLineWidth(1)
            love.graphics.circle("line",mx,my,
                math.max(2,app.brushSize*app.zoom/2))
        end
    end
    app.ui:draw(app)
end

function love.mousepressed(x,y,button,istouch)
    if istouch then return end
    if button==1 and app.ui:click(x,y) then return end
    if not onWorkspace(x,y) or app.ui.modal then return end
    if button==2 or (button==1 and
        (app.tool=="hand" or love.keyboard.isDown("space"))) then
        app.dragging={kind="pan"}
    elseif button==1 then
        if app.tool=="brush" or app.tool=="eraser" then app:strokeStart(x,y)
        elseif SHAPES[app.tool] then app:shapeStart(x,y)
        elseif app.tool=="fill" then app:fillAt(x,y)
        elseif app.tool=="picker" then app:sampleAt(x,y) end
    end
end

function love.mousemoved(x,y,dx,dy,istouch)
    if istouch then return end
    if app.ui:mousemoved(x,y) then return end
    if not app.dragging then return end
    if app.dragging.kind=="pan" then
        app.offsetX=app.offsetX+dx
        app.offsetY=app.offsetY+dy
    elseif app.dragging.kind=="draw" then app:strokeMove(x,y)
    elseif app.dragging.kind=="shape" then app:shapeMove(x,y) end
end

function love.mousereleased(x,y,button,istouch)
    if istouch then return end
    if button==1 then
        app.ui:mousereleased()
        if app.dragging and app.dragging.kind=="draw" then
            app:strokeEnd(x,y)
        elseif app.dragging and app.dragging.kind=="shape" then
            app:shapeEnd(x,y)
        end
        app.dragging=nil
    elseif button==2 and app.dragging and app.dragging.kind=="pan" then
        app.dragging=nil
    end
end

-- LÖVE touch events supply pressure when the device reports it.
-- This does not replace WinTab/Windows Ink tablet integration.
function love.touchpressed(id,x,y,dx,dy,pressure)
    if app.activeTouch then return end
    app.activeTouch=id
    if app.ui:click(x,y) then return end
    if not onWorkspace(x,y) or app.ui.modal then return end
    if app.tool=="hand" then app.dragging={kind="pan"}
    elseif app.tool=="brush" or app.tool=="eraser" then app:strokeStart(x,y,pressure)
    elseif SHAPES[app.tool] then app:shapeStart(x,y)
    elseif app.tool=="fill" then app:fillAt(x,y)
    elseif app.tool=="picker" then app:sampleAt(x,y) end
end

function love.touchmoved(id,x,y,dx,dy,pressure)
    if id~=app.activeTouch then return end
    if app.ui:mousemoved(x,y) then return end
    if app.dragging and app.dragging.kind=="pan" then
        app.offsetX=app.offsetX+dx
        app.offsetY=app.offsetY+dy
    elseif app.dragging and app.dragging.kind=="draw" then
        app:strokeMove(x,y,pressure)
    elseif app.dragging and app.dragging.kind=="shape" then
        app:shapeMove(x,y)
    end
end

function love.touchreleased(id,x,y,dx,dy,pressure)
    if id~=app.activeTouch then return end
    app.ui:mousereleased()
    if app.dragging and app.dragging.kind=="draw" then
        app:strokeEnd(x,y,pressure)
    elseif app.dragging and app.dragging.kind=="shape" then
        app:shapeEnd(x,y)
    end
    app.dragging=nil
    app.activeTouch=nil
end

function love.wheelmoved(_,y)
    if app.ui.modal or y==0 then return end
    local x,my=love.mouse.getPosition()
    if love.keyboard.isDown("lshift","rshift") then
        app.brushSize=math.max(1,math.min(120,app.brushSize+(y>0 and 2 or -2)))
    else app:zoomAt(1.15^y,x,my) end
end

function love.keypressed(key,_,isrepeat)
    if app.ui:keypressed(app,key) then return end
    local ctrl=love.keyboard.isDown("lctrl","rctrl")
    local shift=love.keyboard.isDown("lshift","rshift")
    if ctrl and key=="z" then app.doc:undo()
    elseif ctrl and key=="y" then app.doc:redo()
    elseif ctrl and key=="n" then app.ui:askNew(app)
    elseif ctrl and key=="o" then app.ui:askOpen(app)
    elseif ctrl and shift and key=="s" then app:exportPNG()
    elseif ctrl and key=="s" then
        if app.doc.projectKey then app:saveProject(app.doc.name)
        else app.ui:askSave(app) end
    elseif not ctrl and not isrepeat then
        local shortcuts={
            b="brush", e="eraser", h="hand", g="fill",
            i="picker", l="line", r="rectangle", o="ellipse"
        }
        if shortcuts[key] then app.tool=shortcuts[key]
        elseif key=="f" then app:fitView()
        elseif key=="[" then app.brushSize=math.max(1,app.brushSize-2)
        elseif key=="]" then app.brushSize=math.min(120,app.brushSize+2)
        end
    end
end

function love.textinput(text)
    app.ui:textinput(text)
end

function love.filedropped(file)
    if not file:getFilename():lower():match("%.png$") then
        app:statusMessage("Somente arquivos PNG podem ser importados.")
        return
    end
    if love.keyboard.isDown("lshift","rshift") then
        local ok,err=pcall(function()
            file:open("r")
            local bytes=file:read()
            file:close()
            app:loadBrushMask(bytes,true)
        end)
        if not ok then app:statusMessage("Falha na ponta PNG: "..tostring(err)) end
    else
        local ok,err=pcall(function()app.doc:importPNG(file)end)
        if ok then
            app.ui.tab="layers"
            app:statusMessage("PNG importado em nova camada.")
        else app:statusMessage("Falha ao importar: "..tostring(err)) end
    end
end

function love.resize()
    if app.doc then app:fitView() end
end

function love.update()
    if app.doc then
        love.window.setTitle("Inkora | "..app.doc.name..(app.doc.dirty and " *" or ""))
    end
end
