local Document = require("src.document")
local Brush = require("src.brush")
local Fill = require("src.fill")
local Stabilizer = require("src.stabilizer")
local UI = require("src.ui")
local palette = require("src.palette")
local Native = require("src.native")
local Presets = require("src.presets")
local Profiles = require("src.brush_profiles")
local Viewport = require("src.viewport")
local Tablet = require("src.tablet")
local Startup = require("src.startup")

local app = {
    tool="brush", brushSize=12, brushOpacity=1, stabilization=0.25,
    brushHardness=0.82, brushSpacing=0.18, brushTip=0,
    brushAngle=25, brushFollowPath=false,
    brushTexture=0,brushScatter=0,brushSizeJitter=0,
    brushWetness=0,brushPigmentLoad=1,
    brushPigmentPickup=0,brushPigmentRetention=0,
    brushFlow=1, pressureOpacity=0.75, tipMask=nil, activeTouch=nil,
    presetId="ink", profiles={}, pressureCurve="Linear",
    sampledPressure=nil,
    fillTolerance=0.02, colorIndex=1, color=palette[1],
    zoom=1, offsetX=0, offsetY=0, rotation=0, dragging=nil,
    favorites={ink=true,pencil=true},
    screen="editor",startup=nil,
    message="Bem-vindo ao Inkora! B: pincel | G: balde | I: conta-gotas",
}

local SHAPES={line=true,rectangle=true,ellipse=true}

local function workspace()
    if app.ui and app.ui.workspaceBounds then
        return app.ui:workspaceBounds()
    end
    local w,h=love.graphics.getDimensions()
    return 88,73,w-332,h-44
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

-- Editable profiles are independent from factory brush presets.
-- Only "Save preset" persists the current settings.
function app:presetStyle(id)
    local original=Presets.find(id)
    if not original then return nil end
    local style=Profiles.merge(original,self.profiles[id])
    if style.tip==3 and not self.tipMask then
        if original.tip==3 then return nil end
        style.tip=original.tip
    end
    return style
end

function app:choosePreset(id)
    local p=self:presetStyle(id)
    if not p then return false end
    self.presetId=p.id
    Profiles.apply(self,p)
    self.tool="brush"
    if self.ui then self.ui.tab="brush" end
    return true
end

function app:saveBrushProfile()
    local id=self.presetId
    if not Presets.find(id) then return false end
    local before=self.profiles[id]
    self.profiles[id]=Profiles.capture(self)
    local ok,err=Profiles.write(self.profiles)
    if not ok then
        self.profiles[id]=before
        self:statusMessage("Nao foi possivel salvar pincel: "..tostring(err))
        return false
    end
    require("src.brush_preview").invalidate(id)
    self:statusMessage("Ajustes de "..(Presets.find(id).name).." salvos")
    return true
end

function app:resetBrushProfile()
    local id=self.presetId
    if not Presets.find(id) then return false end
    local before=self.profiles[id]
    self.profiles[id]=nil
    local ok,err=Profiles.write(self.profiles)
    if not ok then
        self.profiles[id]=before
        self:statusMessage("Nao foi possivel restaurar: "..tostring(err))
        return false
    end
    require("src.brush_preview").invalidate(id)
    self:choosePreset(id)
    if self.ui then self.ui.tab="settings" end
    self:statusMessage("Pincel restaurado para o padrao")
    return true
end

function app:setPressureCurve(name)
    local valid=false
    for _,curve in ipairs(Tablet.curves) do
        if name==curve then valid=true;break end
    end
    if not valid then return false end
    if not love.filesystem.write("pen-pressure-curve.txt",name) then
        self:statusMessage("Nao foi possivel salvar curva de pressao")
        return false
    end
    self.pressureCurve=name
    return true
end

function app:pressureFromTablet()
    -- WinTab reports raw packets; SDL provides the matching cursor position.
    -- A disconnected driver or an old sample never replaces the mouse.
    local now=love.timer.getTime()
    Tablet.poll(now)
    local raw=Tablet.pressure(now)
    self.sampledPressure=raw
    if raw then return Tablet.applyCurve(raw,self.pressureCurve) end
    return 1
end

function app:fitView()
    local l,t,r,b=workspace()
    local aw,ah=r-l-80,b-t-78
    local dw,dh=Viewport.bounds(self.doc.width,self.doc.height,self.rotation)
    self.zoom=math.max(0.08,math.min(1,aw/dw,ah/dh))
    self.offsetX=(l+r-self.doc.width*self.zoom)/2
    self.offsetY=(t+b-self.doc.height*self.zoom)/2
end

function app:screenToDocument(x,y)
    return Viewport.toDocument(x,y,self.doc.width,self.doc.height,
        self.zoom,self.offsetX,self.offsetY,self.rotation)
end

function app:documentToScreen(x,y)
    return Viewport.toScreen(x,y,self.doc.width,self.doc.height,
        self.zoom,self.offsetX,self.offsetY,self.rotation)
end

function app:zoomAt(factor,x,y)
    if not onWorkspace(x,y) then return end
    local dx,dy=self:screenToDocument(x,y)
    self.zoom=math.max(0.08,math.min(8,self.zoom*factor))
    self.offsetX,self.offsetY=Viewport.reanchor(dx,dy,x,y,
        self.doc.width,self.doc.height,self.zoom,self.rotation)
end

-- Rotate the *view* around a screen-space pivot. Document pixels and
-- exported PNG stay in their original unrotated coordinates.
function app:rotateAt(deltaDegrees,x,y)
    if not onWorkspace(x,y) then return end
    local dx,dy=self:screenToDocument(x,y)
    self.rotation=(self.rotation+math.rad(deltaDegrees))%(math.pi*2)
    if math.abs(self.rotation-math.pi*2)<0.000001 then self.rotation=0 end
    self.offsetX,self.offsetY=Viewport.reanchor(dx,dy,x,y,
        self.doc.width,self.doc.height,self.zoom,self.rotation)
end

function app:resetRotation()
    if self.rotation==0 then return end
    local l,t,r,b=workspace()
    local cx,cy=(l+r)/2,(t+b)/2
    self:rotateAt(-math.deg(self.rotation),cx,cy)
    self.rotation=0
end

function app:loadFavorites()
    local bytes=love.filesystem.read("brush-favorites.txt")
    if not bytes then return end
    local ids={}
    for id in bytes:gmatch("[^\r\n]+") do
        if Presets.find(id) then ids[id]=true end
    end
    self.favorites=ids
end

function app:toggleFavorite(id)
    if not Presets.find(id) then return false end
    if self.favorites[id] then self.favorites[id]=nil
    else self.favorites[id]=true end
    local ids={}
    for _,preset in ipairs(Presets) do
        if self.favorites[preset.id] then
            ids[#ids+1]=preset.id
        end
    end
    assert(love.filesystem.write("brush-favorites.txt",table.concat(ids,"\n")))
    return true
end

function app:newDocument(w,h,name)
    self.doc=Document.new(w or 1280,h or 800,name or "Novo desenho")
    self.dragging=nil
    self:fitView()
    self:statusMessage(("Novo documento: %d x %d"):format(self.doc.width,self.doc.height))
end

function app:saveProject(name)
    local ok,result=pcall(function()return self.doc:save(name)end)
    if ok then self:statusMessage("Projeto salvo em "..result)
    else self:statusMessage("Falha ao salvar: "..tostring(result)) end
    return ok
end

-- Artwork flow follows title -> My Gallery -> canvas size -> native editor.
-- Gallery and title do not change the Lua/C++ painting engine.
function app:createArtwork(w,h,name)
    local previous=self.doc
    local ok,err=pcall(function()
        self:newDocument(w,h,name~="" and name or "Meu desenho")
        self.doc:save(self.doc.name) -- new blank works already exist in gallery
        if self.startup.galleryFolder~="" then
            self.startup.folders:moveProjects(
                {self.doc.projectKey},self.startup.galleryFolder)
        end
    end)
    if not ok then
        self.doc=previous
        self.startup.error="Erro ao criar desenho: "..tostring(err)
        return false
    end
    self.screen="editor"
    self:statusMessage("Tela criada! Comece a desenhar e volte pela Galeria.")
    return true
end

function app:openArtwork(key)
    local ok,err=pcall(function()self.doc=Document.load(key)end)
    if not ok then
        self.startup.error="Nao foi possivel abrir: "..tostring(err)
        return false
    end
    self.screen="editor"
    self.dragging=nil
    self.rotation=0
    self:fitView()
    self:statusMessage("Obra aberta: "..self.doc.name)
    return true
end

function app:returnToGallery()
    if self.doc and (self.doc.dirty or not self.doc.projectKey) then
        if not self:saveProject(self.doc.name) then
            self:statusMessage("Erro ao salvar. A galeria nao foi aberta.")
            return false
        end
    end
    self.dragging=nil
    self.startup:openGallery(self,true)
    return true
end

function app:goHome()
    if self.screen=="editor" and not self:returnToGallery() then return false end
    self.screen="home"
    return true
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
    require("src.brush_preview").invalidate("custom")
    self.brushTip=3
    self.presetId="custom"
    self.tool="brush"
    self.ui.tab="brush"
    self:statusMessage(("Ponta personalizada: %d x %d"):format(mask.width,mask.height))
end

-- The C++ brush reports the exact uploaded region. When native drawing
-- is unavailable, invalidate fully rather than guessing a bounding box.
function app:markBrushComposite(drag)
    if drag and drag.nativeStroke and Native.lastUpload then
        self.doc:markCompositeDirty(Native.lastUpload)
    else
        self.doc:markCompositeDirty()
    end
end

function app:strokeStart(x,y,pressure)
    local dx,dy=self:screenToDocument(x,y)
    if not insideDocument(self.doc,dx,dy) then return end
    local layer=self.doc.layers[self.doc.selected]
    if not layer.visible then
        self:statusMessage("Ative a visibilidade da camada antes de desenhar.")
        return
    end
    if layer.alphaLock and self.tool=="eraser" then
        self:statusMessage("Alpha Lock ativo: desative para usar a borracha.")
        return
    end
    if (layer.alphaLock or self.doc.selection) and not Native.available() then
        self:statusMessage("Selecao e Alpha Lock exigem o motor C++ v6.")
        return
    end
    self.doc:beginStrokeHistory()
    -- Metadata history may share an older version of this layer's canvas.
    -- Detach on actual pixel editing, not on property-only edits.
    self.doc:ensureLayerWritable(self.doc.selected)
    -- Copy-on-write may replace the Canvas; never paint its stale alias.
    layer=self.doc.layers[self.doc.selected]
    local nativeStroke=Brush.beginStroke(layer.canvas,{
        hardness=self.brushHardness,spacing=self.brushSpacing,
        tip=self.brushTip,aspect=0.3,
        angle=self.brushAngle,followPath=self.brushFollowPath,
        grain=0.85,seed=239,
        mask=self.brushTip==3 and self.tipMask or nil,
        flow=self.brushFlow,pressureOpacity=self.pressureOpacity,
        texture=self.brushTexture,scatter=self.brushScatter,
        sizeJitter=self.brushSizeJitter,
        wetness=self.brushWetness,pigmentLoad=self.brushPigmentLoad,
        pigmentPickup=self.brushPigmentPickup,
        pigmentRetention=self.brushPigmentRetention,
        alphaLock=layer.alphaLock,selection=self.doc.selection,
    })
    self.dragging={
        kind="draw",x=dx,y=dy,nativeStroke=nativeStroke,pressure=pressure or 1,
        smoother=Stabilizer.new(dx,dy,self.stabilization),
        lastTick=love.timer.getTime(),
        targetX=dx,targetY=dy,
    }
    self.doc:captureStrokeRegion(dx,dy,dx,dy,
        self.brushSize,self.brushScatter)
    Brush.segment(layer.canvas,dx,dy,dx,dy,self.color,self.brushSize,
        self.brushOpacity,self.tool=="eraser",self.dragging.nativeStroke,
        self.dragging.pressure,self.dragging.pressure)
    self:markBrushComposite(self.dragging)
end

function app:strokeMove(x,y,pressure,dt)
    local drag=self.dragging
    if not drag or drag.kind~="draw" then return end
    local targetX,targetY=self:screenToDocument(x,y)
    local now=love.timer.getTime()
    local elapsed=dt or (now-drag.lastTick)
    drag.lastTick=now
    drag.targetX,drag.targetY=targetX,targetY
    local dx,dy=drag.smoother:push(targetX,targetY,elapsed)
    local layer=self.doc.layers[self.doc.selected]
    local nextPressure=pressure or 1
    self.doc:captureStrokeRegion(drag.x,drag.y,dx,dy,
        self.brushSize,self.brushScatter)
    Brush.segment(layer.canvas,drag.x,drag.y,dx,dy,self.color,
        self.brushSize,self.brushOpacity,self.tool=="eraser",drag.nativeStroke,
        drag.pressure,nextPressure)
    drag.pressure=nextPressure
    drag.x,drag.y=dx,dy
    self:markBrushComposite(drag)
end

function app:strokeEnd(x,y,pressure)
    local drag=self.dragging
    if not drag or drag.kind~="draw" then return end
    local targetX,targetY=self:screenToDocument(x,y)
    local tail=drag.smoother:finishPath(targetX,targetY,self.brushSize)
    local canvas=self.doc.layers[self.doc.selected].canvas
    local finalPressure=pressure or 1
    for i,point in ipairs(tail) do
        local t=i/#tail
        local samplePressure=drag.pressure+(finalPressure-drag.pressure)*t
        self.doc:captureStrokeRegion(drag.x,drag.y,point[1],point[2],
            self.brushSize,self.brushScatter)
        Brush.segment(canvas,drag.x,drag.y,point[1],point[2],
            self.color,self.brushSize,self.brushOpacity,
            self.tool=="eraser",drag.nativeStroke,drag.pressure,samplePressure)
        drag.x,drag.y,drag.pressure=point[1],point[2],samplePressure
        self:markBrushComposite(drag)
    end
    self.doc:trimHistory()
end

function app:selectionStart(x,y)
    local dx,dy=self:screenToDocument(x,y)
    self.dragging={kind="selection",x1=dx,y1=dy,x2=dx,y2=dy}
end

function app:selectionMove(x,y)
    local d=self.dragging
    if d and d.kind=="selection" then d.x2,d.y2=self:screenToDocument(x,y) end
end

function app:selectionEnd(x,y)
    local d=self.dragging
    if not d or d.kind~="selection" then return end
    d.x2,d.y2=self:screenToDocument(x,y)
    if self.doc:setSelection(d.x1,d.y1,d.x2,d.y2) then
        self:statusMessage("Selecao retangular ativa | Ctrl+D para limpar")
    else
        self:statusMessage("Selecao fora do documento.")
    end
end

function app:shapeStart(x,y)
    local layer=self.doc.layers[self.doc.selected]
    if self.doc.selection or (layer and layer.alphaLock) then
        self:statusMessage("Formas com selecao/Alpha Lock ainda nao suportadas; use o pincel.")
        return
    end
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
    self.doc:ensureLayerWritable(self.doc.selected)
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
        local changed,dirty=Fill.apply(data,dx,dy,self.color,self.fillTolerance,{
            selection=self.doc.selection,alphaLock=layer.alphaLock
        })
        if changed then
            self.doc:applyFillRegion(selected,data,dirty)
            self:statusMessage(("Balde: %dx%d px | camada %d"):format(
                dirty.width,dirty.height,selected))
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
    -- Screenshots use isolated artwork data; never mix automatic GPU
    -- regression files with a person's real gallery or normal editor saves.
    local previewIdentity=os.getenv("INKORA_PREVIEW")
    if previewIdentity=="gallery" or previewIdentity=="gallery-folder"
        or previewIdentity=="create" then
        love.filesystem.setIdentity("Inkora-gallery-preview",true)
    end
    love.graphics.setBackgroundColor(0.15,0.19,0.25)
    love.keyboard.setKeyRepeat(true)
    app.ui=UI.new()
    app.startup=Startup.new()
    app.startup:refreshGallery()
    local savedCurve=love.filesystem.read("pen-pressure-curve.txt")
    for _,curve in ipairs(Tablet.curves) do
        if savedCurve==curve then app.pressureCurve=curve;break end
    end
    app.profiles=Profiles.read()
    app:loadFavorites()
    app:choosePreset("ink")
    app:newDocument(1280,800)
    if love.filesystem.getInfo("brushes/custom-tip.png") then
        local bytes=love.filesystem.read("brushes/custom-tip.png")
        local ok,err=pcall(function() app:loadBrushMask(bytes,false) end)
        if not ok then app:statusMessage("Erro na ponta salva: "..tostring(err)) end
    end
    if Brush.nativeAvailable() then
        app:statusMessage("Motor C++ v13 ativo | LuaJIT FFI | Inkora")
    else
        app:statusMessage("Prototipo Lua (C++ ausente): "..tostring(Brush.nativeError()))
    end
    local preview=os.getenv("INKORA_PREVIEW")
    -- Existing native test/preview modes still enter the editor directly.
    app.screen=(os.getenv("INKORA_TEST")=="1" or
        (preview and preview~="home" and preview~="gallery"
        and preview~="gallery-folder" and preview~="create"))
        and "editor" or "home"
    if preview=="gallery" or preview=="gallery-folder" or
        preview=="create" then
        local group=require("tests.preview").gallery(app)
        if preview=="gallery-folder" and group~="" then
            app.startup:galleryOpenFolder(group)
        elseif preview=="create" then
            app.startup:openCreate(app)
        end
    end
    if preview=="brush" or preview=="layers" or preview=="color"
        or preview=="rotate" or preview=="settings"
        or preview=="stabilization" or preview=="direction"
        or preview=="texture" or preview=="wet" or preview=="fill" then
        if preview=="direction" then
            require("tests.preview").directional(app)
        else require("tests.preview").seed(app) end
        if preview=="fill" then
            app.tool="fill"
            app.fillTolerance=0.12
            app.ui.tab="settings"
            app:statusMessage("Inkora: balde nativo C++ v13 - tolerancia ajustavel")
        elseif preview=="rotate" then
            local l,t,r,b=workspace()
            app:rotateAt(28,(l+r)/2,(t+b)/2)
            app.ui.tab="brush"
        elseif preview=="direction" then
            app.ui.tab="settings"
        elseif preview=="wet" then
            app:choosePreset("watercolor")
            app.ui.tab="wet"
            app:statusMessage("Inkora: tinta umida e mistura de pigmentos C++")
        elseif preview=="texture" then
            app:choosePreset("chalk")
            app.brushTexture=0.9
            app.brushScatter=0.55
            app.brushSizeJitter=0.65
            app.ui.tab="texture"
            app:statusMessage("Textura C++ v9: dispersao e variacao de tamanho")
        elseif preview=="stabilization" then
            app:choosePreset("pencil")
            app.stabilization=0.96
            app.ui.tab="settings"
            app:statusMessage("Estabilizacao adaptativa - previa em tempo real")
        else app.ui.tab=preview end
        app._previewName=preview
    elseif preview=="home" or preview=="gallery" or
        preview=="gallery-folder" or preview=="create" then
        app._previewName=preview
    end
    if os.getenv("INKORA_TEST")=="1" then
        local ok,err=pcall(function()
            love.draw()
            app.ui.tab="layers"
            love.draw()
            require("tests.runtime").run(app)
        end)
        if not ok then
            io.stderr:write("INKORA_GPU_SMOKE_FAILED: "..tostring(err).."\n")
        end
        os.exit(ok and 0 or 1)
    end
end

local function saveStartupScreenshot(app)
    if app._previewName and not app._captureQueued then
        app._captureQueued=true
        local filename="Inkora-Preview-"..app._previewName..".png"
        love.graphics.captureScreenshot(function(pixels)
            local ok,err=love.filesystem.write(filename,
                pixels:encode("png"):getString())
            if ok then
                print("INKORA_SCREENSHOT_OK "..love.filesystem.getSaveDirectory()
                    .."/"..filename)
                love.event.quit(0)
            else
                io.stderr:write("INKORA_SCREENSHOT_FAILED "..tostring(err).."\n")
                love.event.quit(1)
            end
        end)
    end
end

function love.draw()
    if app.screen~="editor" then
        app.startup:draw(app)
        saveStartupScreenshot(app)
        return
    end
    love.graphics.clear(0.11,0.12,0.16,1)
    local l,t,r,b=workspace()
    love.graphics.setScissor(l,t,r-l,b-t)
    -- Quiet patterned worktop reinforces the actual canvas boundaries.
    love.graphics.setColor(0.135,0.148,0.19,1)
    love.graphics.rectangle("fill",l,t,r-l,b-t)
    love.graphics.setColor(0.16,0.17,0.21,0.45)
    for yy=t,b,48 do
        for xx=l,r,48 do
            if (math.floor((yy-t)/48)+math.floor((xx-l)/48))%2==0 then
                love.graphics.rectangle("fill",xx,yy,48,48)
            end
        end
    end
    local x,y=app.offsetX,app.offsetY
    local w,h=app.doc.width*app.zoom,app.doc.height*app.zoom
    local cx,cy=x+w/2,y+h/2
    love.graphics.push("all")
    love.graphics.translate(cx,cy)
    love.graphics.rotate(app.rotation)
    love.graphics.translate(-w/2,-h/2)
    love.graphics.setColor(0.05,0.07,0.11,0.26)
    love.graphics.rectangle("fill",9,13,w,h)
    app.doc:draw(0,0,app.zoom)
    -- An empty canvas stays blank, as in ibisPaint. Do not overlay onboarding
    -- text on the artist's actual pixels or the drawing workspace.
    love.graphics.setColor(0.60,0.68,0.77,0.55)
    love.graphics.rectangle("line",-0.5,-0.5,w+1,h+1)

    -- Previa de formas: nao altera a camada antes de soltar o mouse.
    local d=app.dragging
    if d and d.kind=="shape" then
        love.graphics.push("all")
        love.graphics.scale(app.zoom,app.zoom)
        Brush.shape(nil,d.shape,d.x1,d.y1,d.x2,d.y2,app.color,
            app.brushSize,app.brushOpacity)
        love.graphics.pop()
    end
    local sel=app.doc.selection
    if app.dragging and app.dragging.kind=="selection" then
        local d=app.dragging
        local left=math.min(d.x1,d.x2)
        local top=math.min(d.y1,d.y2)
        sel={x0=left,y0=top,x1=math.max(d.x1,d.x2),y1=math.max(d.y1,d.y2)}
    end
    if sel then
        local sx=sel.x0*app.zoom
        local sy=sel.y0*app.zoom
        local sw=(sel.x1-sel.x0)*app.zoom
        local sh=(sel.y1-sel.y0)*app.zoom
        love.graphics.push("all")
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0,0,0,0.9)
        love.graphics.rectangle("line",sx-1,sy-1,sw+2,sh+2)
        love.graphics.setColor(0.3,0.91,0.93,1)
        love.graphics.rectangle("line",sx,sy,sw,sh)
        love.graphics.pop()
    end
    love.graphics.pop() -- rotated canvas transform
    love.graphics.setScissor()

    if not app.ui.modal and app.tool~="hand" and app.tool~="fill"
        and app.tool~="picker" then
        local mx,my=love.mouse.getPosition()
        if onWorkspace(mx,my) then
            local radius=math.max(2,app.brushSize*app.zoom/2)
            love.graphics.setColor(app.color[1],app.color[2],app.color[3],0.18)
            love.graphics.circle("fill",mx,my,radius)
            love.graphics.setColor(0.95,0.96,0.98,0.85)
            love.graphics.setLineWidth(1)
            love.graphics.circle("line",mx,my,radius)
        end
    end
    if app.dragging and app.dragging.kind=="draw"
        and app.stabilization>0 and app.dragging.smoother then
        local d=app.dragging
        local sx,sy=app:documentToScreen(d.x,d.y)
        local tx,ty=app:documentToScreen(d.targetX,d.targetY)
        love.graphics.push("all")
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.98,0.98,0.98,0.35)
        love.graphics.line(sx,sy,tx,ty)
        love.graphics.setColor(0.44,0.82,0.91,0.92)
        love.graphics.circle("line",sx,sy,4.5)
        love.graphics.pop()
    end
    app.ui:draw(app)
    saveStartupScreenshot(app)
end

function love.mousepressed(x,y,button,istouch)
    if istouch then return end
    if app.screen~="editor" then
        if button==1 then
            if app.screen=="gallery" then app.startup:pointerPressed(x,y)
            else app.startup:click(x,y) end
        end
        return
    end
    if button==1 and app.ui:click(x,y) then return end
    if not onWorkspace(x,y) or app.ui.modal then return end
    if button==2 or (button==1 and
        (app.tool=="hand" or love.keyboard.isDown("space"))) then
        app.dragging={kind="pan"}
    elseif button==1 then
        if app.tool=="brush" or app.tool=="eraser" then
            app:strokeStart(x,y,app:pressureFromTablet())
        elseif SHAPES[app.tool] then app:shapeStart(x,y)
        elseif app.tool=="fill" then app:fillAt(x,y)
        elseif app.tool=="picker" then app:sampleAt(x,y)
        elseif app.tool=="select" then app:selectionStart(x,y) end
    end
end

function love.mousemoved(x,y,dx,dy,istouch)
    if istouch then return end
    if app.screen~="editor" then
        if app.screen=="gallery" then app.startup:pointerMoved(x,y) end
        return
    end
    if app.ui:mousemoved(x,y) then return end
    if not app.dragging then return end
    if app.dragging.kind=="pan" then
        app.offsetX=app.offsetX+dx
        app.offsetY=app.offsetY+dy
    elseif app.dragging.kind=="draw" then
        app:strokeMove(x,y,app:pressureFromTablet())
    elseif app.dragging.kind=="shape" then app:shapeMove(x,y)
    elseif app.dragging.kind=="selection" then app:selectionMove(x,y) end
end

function love.mousereleased(x,y,button,istouch)
    if istouch then return end
    if app.screen~="editor" then
        if app.screen=="gallery" and button==1 then
            app.startup:pointerReleased(x,y)
        end
        return
    end
    if button==1 then
        app.ui:mousereleased()
        if app.dragging and app.dragging.kind=="draw" then
            app:strokeEnd(x,y,app:pressureFromTablet())
        elseif app.dragging and app.dragging.kind=="shape" then
            app:shapeEnd(x,y)
        elseif app.dragging and app.dragging.kind=="selection" then
            app:selectionEnd(x,y)
        end
        app.dragging=nil
    elseif button==2 and app.dragging and app.dragging.kind=="pan" then
        app.dragging=nil
    end
end

-- LÖVE touch events supply pressure when the device reports it.
-- This does not replace WinTab/Windows Ink tablet integration.
function love.touchpressed(id,x,y,dx,dy,pressure)
    if app.screen~="editor" then
        if app.screen=="gallery" then app.startup:pointerPressed(x,y)
        else app.startup:click(x,y) end
        return
    end
    if app.activeTouch then return end
    app.activeTouch=id
    if app.ui:click(x,y) then return end
    if not onWorkspace(x,y) or app.ui.modal then return end
    if app.tool=="hand" then app.dragging={kind="pan"}
    elseif app.tool=="brush" or app.tool=="eraser" then app:strokeStart(x,y,pressure)
    elseif SHAPES[app.tool] then app:shapeStart(x,y)
    elseif app.tool=="fill" then app:fillAt(x,y)
    elseif app.tool=="picker" then app:sampleAt(x,y)
    elseif app.tool=="select" then app:selectionStart(x,y) end
end

function love.touchmoved(id,x,y,dx,dy,pressure)
    if app.screen~="editor" then
        if app.screen=="gallery" then app.startup:pointerMoved(x,y) end
        return
    end
    if id~=app.activeTouch then return end
    if app.ui:mousemoved(x,y) then return end
    if app.dragging and app.dragging.kind=="pan" then
        app.offsetX=app.offsetX+dx
        app.offsetY=app.offsetY+dy
    elseif app.dragging and app.dragging.kind=="draw" then
        app:strokeMove(x,y,pressure)
    elseif app.dragging and app.dragging.kind=="shape" then
        app:shapeMove(x,y)
    elseif app.dragging and app.dragging.kind=="selection" then
        app:selectionMove(x,y)
    end
end

function love.touchreleased(id,x,y,dx,dy,pressure)
    if app.screen~="editor" then
        if app.screen=="gallery" then app.startup:pointerReleased(x,y) end
        return
    end
    if id~=app.activeTouch then return end
    app.ui:mousereleased()
    if app.dragging and app.dragging.kind=="draw" then
        app:strokeEnd(x,y,pressure)
    elseif app.dragging and app.dragging.kind=="shape" then
        app:shapeEnd(x,y)
    elseif app.dragging and app.dragging.kind=="selection" then
        app:selectionEnd(x,y)
    end
    app.dragging=nil
    app.activeTouch=nil
end

function love.wheelmoved(_,y)
    if app.screen~="editor" then
        if app.screen=="gallery" then app.startup:wheel(y) end
        return
    end
    if app.ui.modal or y==0 then return end
    local x,my=love.mouse.getPosition()
    if app.ui:mousewheel(x,y) then return end
    if love.keyboard.isDown("lalt","ralt") then
        app:rotateAt(y*5,x,my)
    elseif love.keyboard.isDown("lshift","rshift") then
        app.brushSize=math.max(1,math.min(120,app.brushSize+(y>0 and 2 or -2)))
    else app:zoomAt(1.15^y,x,my) end
end

function love.keypressed(key,_,isrepeat)
    if app.screen~="editor" then
        app.startup:keypressed(app,key)
        return
    end
    if key=="escape" and not app.ui.modal then
        app:returnToGallery()
        return
    end
    if app.ui:keypressed(app,key) then return end
    local ctrl=love.keyboard.isDown("lctrl","rctrl")
    local shift=love.keyboard.isDown("lshift","rshift")
    if ctrl and key=="z" then app.doc:undo()
    elseif ctrl and key=="y" then app.doc:redo()
    elseif key=="tab" and not ctrl then
        app.ui.tab=app.ui.tab=="brush" and "layers" or "brush"
    elseif key=="c" and not ctrl then
        app.ui.tab="color"
    elseif ctrl and key=="0" then
        app:resetRotation()
    elseif ctrl and key=="d" then
        app.doc:clearSelection()
        app:statusMessage("Selecao removida.")
    elseif ctrl and key=="n" then app.ui:askNew(app)
    elseif ctrl and key=="o" then app.ui:askOpen(app)
    elseif ctrl and shift and key=="s" then app:exportPNG()
    elseif ctrl and key=="s" then
        if app.doc.projectKey then app:saveProject(app.doc.name)
        else app.ui:askSave(app) end
    elseif not ctrl and not isrepeat then
        local shortcuts={
            b="brush", e="eraser", h="hand", g="fill",
            i="picker", l="line", r="rectangle", o="ellipse",m="select"
        }
        if shortcuts[key] then
            app.tool=shortcuts[key]
            if app.tool=="fill" then app.ui.tab="settings"
            elseif app.tool=="brush" or app.tool=="eraser" then
                app.ui.tab="brush"
            end
        elseif key=="escape" then
            app.doc:clearSelection()
            app:statusMessage("Selecao removida.")
        elseif key=="comma" then
            local l,t,r,b=workspace()
            app:rotateAt(-15,(l+r)/2,(t+b)/2)
        elseif key=="period" then
            local l,t,r,b=workspace()
            app:rotateAt(15,(l+r)/2,(t+b)/2)
        elseif key=="0" then app:resetRotation()
        elseif key=="f" then app:fitView()
        elseif key=="[" then app.brushSize=math.max(1,app.brushSize-2)
        elseif key=="]" then app.brushSize=math.min(120,app.brushSize+2)
        end
    end
end

function love.textinput(text)
    if app.screen~="editor" then
        if app.screen=="create" or app.screen=="gallery" then
            app.startup:textinput(text)
        end
    else app.ui:textinput(text) end
end

-- Import a dropped PNG as a REAL editable Inkora document while New is open.
-- The original pixels become an ordinary layer and save to the active folder.
function app:importGalleryPNG(file)
    local previous=self.doc
    local ok,err=pcall(function()
        file:open("r")
        local bytes=assert(file:read(),"Falha lendo PNG")
        file:close()
        assert(#bytes<=64*1024*1024,"Imagem excede 64 MB")
        local data=love.image.newImageData(love.filesystem.newFileData(bytes,"artwork.png"))
        local w,h=data:getDimensions()
        assert(w>=1 and h>=1 and w<=4096 and h<=4096,
            "Imagem deve ter no maximo 4096 x 4096 pixels")
        local name=file:getFilename():gsub(string.char(92),"/"):match("([^/]+)%.%w+$") or "Imagem"
        self:newDocument(w,h,name)
        self.doc:importPNG(file)
        self.doc:save(name)
        if self.startup.galleryFolder~="" then
            self.startup.folders:moveProjects({self.doc.projectKey},
                self.startup.galleryFolder)
        end
    end)
    if not ok then
        self.doc=previous
        self.startup.error=tostring(err)
        return false
    end
    self.startup.galleryModal=nil
    self.screen="editor"
    self.dragging=nil
    self.rotation=0
    self:fitView()
    self:statusMessage("PNG importado como obra editavel")
    return true
end

-- Open a native ibisPaint IPV as a NEW flattened Inkora document.
-- The original IPV is never modified. Raster/text layers and editing
-- history are deliberately not represented as editable IPV layers.
function app:importGalleryIPV(file)
    local reader=require("src.ibis_ipv")
    local ok,content=pcall(reader.readFile,file)
    if not ok then
        local message="Falha ao ler .ipv: "..tostring(content)
        self.startup.error=message
        if self.screen=="editor" then self:statusMessage(message) end
        return false
    end
    -- Never discard an unsaved painting when dropping a new IPV over
    -- an active editor. A save failure leaves the existing doc untouched.
    if self.screen=="editor" and self.doc and
        (self.doc.dirty or not self.doc.projectKey) then
        if not self:saveProject(self.doc.name) then
            self.startup.error="Salve o desenho atual antes de importar IPV."
            return false
        end
    end
    local pngName=file:getFilename():gsub("%.[iI][pP][vV]$",".png")
    local name=pngName:gsub(string.char(92),"/"):
        match("([^/]+)%.%w+$") or "Imagem IPV"
    -- First try the independent RPNG decoder. A hidden flattened canvas
    -- stays in the document for comparison if layer order differs.
    -- Incomplete/unsupported RPNG data never yields fake editable layers.
    local layerReason="nenhuma camada RPNG reconhecida"
    if #content.rasterLayers>0 then
        local decoded,rasters=pcall(reader.decodeRasterLayers,content)
        if decoded then
            -- Ensure the editable Normal layers actually reproduce the PNG
            -- exported by ibisPaint. Unsupported blend/visibility/opacities
            -- must never silently be presented as a faithful import.
            local checked,report=pcall(function()
                local reference=love.image.newImageData(
                    love.filesystem.newFileData(content.png,"ipv-check.png"))
                return require("src.ipv_visual_verify").assess(rasters,reference)
            end)
            if not checked or not report.matches then
                if checked then
                    layerReason=("raster diverge da imagem final (erro maximo %.3f)"):format(
                        report.maxError)
                else
                    layerReason="nao foi possivel verificar pixels: "..tostring(report)
                end
            else
                if report.direction=="reverse" then
                    local reversed={}
                    for i=#rasters,1,-1 do
                        reversed[#reversed+1]=rasters[i]
                    end
                    rasters=reversed
                end
                local previous=self.doc
                local created,doc=pcall(Document.fromIPVRasters,
                    content.width,content.height,name,rasters,content.png)
            if created then
                local saved,err=pcall(function()
                    doc:save(name)
                    if self.startup.galleryFolder~="" then
                        self.startup.folders:moveProjects({doc.projectKey},
                            self.startup.galleryFolder)
                    end
                end)
                if saved then
                    self.doc=doc
                    self.startup.galleryModal=nil
                    self.screen="editor"
                    self.dragging=nil
                    self.rotation=0
                    self:fitView()
                    local orderMessage=content.layerOrderSource=="layer-list"
                        and "ordem lida de registro IPV (validacao real pendente)"
                        or "ordem estimada por ID"
                    local checkMessage=report.direction=="reverse"
                        and "pilha invertida para corresponder ao PNG"
                        or "pixels comparados ao PNG"
                    self:statusMessage(
                        ("IPV: %d camadas raster editaveis; %s; %s (%d amostras)."):format(
                            #rasters,orderMessage,checkMessage,report.checked))
                    return true
                end
                layerReason=tostring(err)
            else
                layerReason=tostring(doc)
            end
                self.doc=previous
            end
        else
            layerReason=tostring(rasters)
        end
    end
    -- Compatible with older IPV files or unsupported layer variants:
    -- import only the flattened PNG and clearly report the limitation.
    local virtualPNG={
        getFilename=function()return pngName end,
        open=function()end,
        read=function()return content.png end,
        close=function()end,
    }
    local imported=self:importGalleryPNG(virtualPNG)
    if imported then
        self:statusMessage("IPV: apenas imagem composta importada ("..
            layerReason..").")
    end
    return imported
end

function love.filedropped(file)
    local extension=file:getFilename():lower()
    if extension:match("%.ipv$") then
        -- Opens a fresh Inkora project, even if the artist was editing
        -- something else. Source .ipv is retained untouched.
        app:importGalleryIPV(file)
        return
    end
    if app.screen~="editor" then
        if (app.screen=="gallery" or app.screen=="home") and
            extension:match("%.png$") then
            app:importGalleryPNG(file)
        else
            app.startup.error="Arraste um PNG ou IPV para importar."
        end
        return
    end
    if not extension:match("%.png$") then
        app:statusMessage("Apenas arquivos PNG ou IPV podem ser importados.")
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
    if app.screen=="editor" and app.doc then app:fitView() end
end

function love.update()
    local now=love.timer.getTime()
    Tablet.poll(now)
    app.sampledPressure=Tablet.pressure(now)
    if app.screen=="editor" and app.doc then
        love.window.setTitle("Inkora | "..app.doc.name..(app.doc.dirty and " *" or ""))
    else
        love.window.setTitle("Inkora | "..(app.screen=="home" and "Inicio"
            or app.screen=="gallery" and "Minha galeria" or "Novo desenho"))
    end
end

function love.quit()
    Tablet.shutdown()
end
