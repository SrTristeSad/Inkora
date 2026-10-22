local Native = require("src.native")
local Document = {}
Document.__index = Document

local MAX_LAYERS = 16
local MAX_HISTORY = 10
-- Logical RGBA history budget, not a hard RAM/VRAM allocation cap.
local HISTORY_BUDGET_BYTES = 256 * 1024 * 1024
local COMPOSITE_TILE = 128
local COMPOSITE_BUILD_TILE = 512
local BLEND_MODES={"Normal","Multiply","Screen","Add","Overlay"}

Document.BLEND_MODES=BLEND_MODES

local function checkMode(mode)
    return type(mode)=="number" and mode%1==0 and mode>=0 and mode<=4
end

local function newCanvas(w, h)
    local c = love.graphics.newCanvas(w, h, {format = "rgba8"})
    love.graphics.push("all")
    love.graphics.setCanvas(c)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.pop()
    return c
end

local function cloneCanvas(original, w, h)
    local copy = newCanvas(w, h)
    love.graphics.push("all")
    love.graphics.setCanvas(copy)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.draw(original)
    love.graphics.pop()
    return copy
end

local function cloneMask(mask)
    if not mask then return nil end
    local w,h=mask:getDimensions()
    local copy=love.image.newImageData(w,h,"rgba8")
    copy:paste(mask,0,0,0,0,w,h)
    return copy
end

local function newMask(w,h,selection)
    -- Red channel is mask coverage, alpha remains fully opaque.
    local canvas=newCanvas(w,h)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0,0,0,1)
    if selection then
        love.graphics.setColor(1,1,1,1)
        love.graphics.rectangle("fill",selection.x0,selection.y0,
            selection.x1-selection.x0,selection.y1-selection.y0)
    else love.graphics.clear(1,1,1,1) end
    love.graphics.pop()
    return canvas:newImageData()
end

local function layer(w, h, name)
    local canvas = newCanvas(w, h)
    Native.registerBlank(canvas)
    return {canvas = canvas, name = name, opacity = 1, visible = true,
        blendMode=0, alphaLock=false, clipping=false, mask=nil}
end

local function cleanText(s)
    s = tostring(s or ""):gsub("[\r\n\t]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s:sub(1, 64)
end


-- Metadata snapshots keep immutable references to pixel buffers.
-- A real raster mutation must call ensureLayerWritable() first.
-- No deep canvas/mask copy is needed to reorder or toggle layers.
local function copyLayerDescriptor(l)
    return {
        canvas=l.canvas,name=l.name,opacity=l.opacity,visible=l.visible,
        blendMode=l.blendMode or 0,alphaLock=l.alphaLock or false,
        clipping=l.clipping or false,mask=l.mask,
    }
end

local function createSnapshot(self)
    local snap={layers={},selected=self.selected}
    for i,l in ipairs(self.layers) do
        snap.layers[i]=copyLayerDescriptor(l)
    end
    return snap
end

local function snapshotUsesResource(self,value,property)
    if not value then return false end
    for _,stack in ipairs({self.history,self.future}) do
        for _,entry in ipairs(stack) do
            if entry.layers then
                for _,layer in ipairs(entry.layers) do
                    if layer[property]==value then return true end
                end
            end
        end
    end
    return false
end

-- Copy on first write only when an old snapshot owns the same pixels.
function Document:ensureLayerWritable(index)
    local current=self.layers[index]
    if not current then return false end
    if snapshotUsesResource(self,current.canvas,"canvas") then
        current.canvas=cloneCanvas(current.canvas,self.width,self.height)
        -- The fresh Canvas contains existing pixels, not an empty layer.
        Native.invalidate(current.canvas)
        self:trimHistory()
    end
    return true
end

local function ensureMaskWritable(self,index)
    local current=self.layers[index]
    if current and current.mask and
       snapshotUsesResource(self,current.mask,"mask") then
        current.mask=cloneMask(current.mask)
    end
end

function Document.new(w, h, name)
    assert(w >= 64 and h >= 64 and w <= 4096 and h <= 4096, "Tamanho invalido")
    local self = setmetatable({
        width = w, height = h, name = name or "Sem titulo",
        selected = 1, layers = {layer(w, h, "Camada 1")},
        history = {}, future = {}, dirty = false, projectKey = nil,
        historyBudgetBytes=HISTORY_BUDGET_BYTES,
        compositeDirty=true, compositeCanvas=nil, selection=nil,
        compositeInvalidFull=true, compositeDirtyTiles={},
        compositeMetrics={fullBuilds=0,partialBuilds=0,lastTiles=0,
            lastPixels=0,totalPixels=0,lastBatches=0,
            peakRegionPixels=0,regionReads=0},
    }, Document)
    return self
end

-- A rectangular brush upload invalidates only the overlapping 128px tiles.
-- Structural edits, undos, masks and blends invalidate the entire composite.
function Document:markCompositeDirty(region)
    if not region or not self.compositeCanvas then
        self.compositeInvalidFull=true
        self.compositeDirtyTiles={}
        self.compositeDirty=true
        return
    end
    if self.compositeInvalidFull then return end
    local x,y,w,h=region.x,region.y,region.width,region.height
    if type(x)~="number" or type(y)~="number" or
       type(w)~="number" or type(h)~="number" or
       x~=x or y~=y or w~=w or h~=h then
        self:markCompositeDirty()
        return
    end
    if w<=0 or h<=0 then return end
    local x0=math.max(0,math.floor(x))
    local y0=math.max(0,math.floor(y))
    local x1=math.min(self.width,math.ceil(x+w))
    local y1=math.min(self.height,math.ceil(y+h))
    if x0>=x1 or y0>=y1 then return end
    for ty=math.floor(y0/COMPOSITE_TILE),math.floor((y1-1)/COMPOSITE_TILE) do
        for tx=math.floor(x0/COMPOSITE_TILE),math.floor((x1-1)/COMPOSITE_TILE) do
            local key=ty*math.ceil(self.width/COMPOSITE_TILE)+tx
            self.compositeDirtyTiles[key]={
                x=tx*COMPOSITE_TILE,y=ty*COMPOSITE_TILE,
                width=math.min(COMPOSITE_TILE,self.width-tx*COMPOSITE_TILE),
                height=math.min(COMPOSITE_TILE,self.height-ty*COMPOSITE_TILE),
            }
        end
    end
    self.compositeDirty=true
end

-- The history snapshot does not change visible pixels by itself. Brush
-- strokes can defer invalidation until their actual dirty upload is known.
-- Brush history is copy-on-write at 128x128 tile granularity. The first
-- time a tile is touched by one stroke, save only that tile's RGBA bytes.
-- Structural edits intentionally keep their existing whole-layer snapshots.
local function tileBounds(doc,tx,ty)
    local x,y=tx*COMPOSITE_TILE,ty*COMPOSITE_TILE
    return x,y,math.min(COMPOSITE_TILE,doc.width-x),
        math.min(COMPOSITE_TILE,doc.height-y)
end

local function captureTile(canvas,x,y,w,h)
    return canvas:newImageData(1,1,x,y,w,h)
end

function Document:beginStrokeHistory()
    local entry={kind="stroke",layerIndex=self.selected,tiles={},
        tileKeys={},bytes=0}
    table.insert(self.history,entry)
    if #self.history>MAX_HISTORY then table.remove(self.history,1) end
    self.future={}
    self.dirty=true
    self:trimHistory()
    return entry
end

-- Capture an exact pixel rectangle once per 128x128 history tile.
-- This is also used by native fill after determining its dirty bounds.
function Document:captureHistoryRect(x,y,width,height)
    local entry=self.history[#self.history]
    if not entry or entry.kind~="stroke" or
        entry.layerIndex~=self.selected then return false end
    local x0=math.max(0,math.floor(x))
    local y0=math.max(0,math.floor(y))
    local x1=math.min(self.width,math.ceil(x+width))
    local y1=math.min(self.height,math.ceil(y+height))
    if x1<=x0 or y1<=y0 then return false end
    local canvas=self.layers[entry.layerIndex].canvas
    local tilesWide=math.ceil(self.width/COMPOSITE_TILE)
    for ty=math.floor(y0/COMPOSITE_TILE),math.floor((y1-1)/COMPOSITE_TILE) do
        for tx=math.floor(x0/COMPOSITE_TILE),math.floor((x1-1)/COMPOSITE_TILE) do
            local key=ty*tilesWide+tx
            if not entry.tileKeys[key] then
                local px,py,pw,ph=tileBounds(self,tx,ty)
                entry.tiles[#entry.tiles+1]={
                    x=px,y=py,w=pw,h=ph,
                    data=captureTile(canvas,px,py,pw,ph)
                }
                entry.tileKeys[key]=true
                entry.bytes=entry.bytes+pw*ph*4
            end
        end
    end
    return true
end

function Document:captureStrokeRegion(x0,y0,x1,y1,diameter,scatter)
    local radius=math.max(0.5,diameter*0.5)+
        diameter*0.4*(scatter or 0)+4
    local left=math.max(0,math.floor(math.min(x0,x1)-radius))
    local top=math.max(0,math.floor(math.min(y0,y1)-radius))
    local right=math.min(self.width-1,math.ceil(math.max(x0,x1)+radius))
    local bottom=math.min(self.height-1,math.ceil(math.max(y0,y1)+radius))
    if right<left or bottom<top then return false end
    return self:captureHistoryRect(left,top,right-left+1,bottom-top+1)
end

local function swapStrokeTiles(self,entry)
    -- Undo/redo may edit pixels shared by an earlier structural snapshot.
    self:ensureLayerWritable(entry.layerIndex)
    local target=self.layers[entry.layerIndex]
    assert(target and target.canvas,"Camada do historico inexistente")
    local canvas=target.canvas
    local replacement={}
    -- Read all current tiles before writing any replacement pixels.
    for i,tile in ipairs(entry.tiles) do
        replacement[i]={
            x=tile.x,y=tile.y,w=tile.w,h=tile.h,
            data=captureTile(canvas,tile.x,tile.y,tile.w,tile.h)
        }
    end
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.setBlendMode("replace","premultiplied")
    love.graphics.setColor(1,1,1,1)
    for _,tile in ipairs(entry.tiles) do
        local image=love.graphics.newImage(tile.data)
        love.graphics.draw(image,tile.x,tile.y)
        image:release()
    end
    love.graphics.pop()
    Native.invalidate(canvas)
    return {kind="stroke",layerIndex=entry.layerIndex,
        tiles=replacement,bytes=entry.bytes}
end

function Document:historyStats()
    -- Count each stored RGBA resource at most once, and exclude buffers
    -- already owned by the live document. This is an approximate logical
    -- history cost, not physical VRAM usage or allocator overhead.
    local tiles,strokeCount,fullCount,bytes=0,0,0,0
    local owned={}
    for _,layer in ipairs(self.layers) do
        owned[layer.canvas]=true
        if layer.mask then owned[layer.mask]=true end
    end
    local seen={}
    local unique=0
    for _,stack in ipairs({self.history,self.future}) do
        for _,entry in ipairs(stack) do
            if entry.kind=="stroke" then
                strokeCount=strokeCount+1
                tiles=tiles+#entry.tiles
                bytes=bytes+entry.bytes
            else
                fullCount=fullCount+1
                for _,layer in ipairs(entry.layers) do
                    for _,resource in ipairs({layer.canvas,layer.mask or false}) do
                        if resource and not seen[resource] then
                            seen[resource]=true
                            if not owned[resource] then
                                bytes=bytes+self.width*self.height*4
                                unique=unique+1
                            end
                        end
                    end
                end
            end
        end
    end
    local budget=self.historyBudgetBytes or HISTORY_BUDGET_BYTES
    return {steps=#self.history,redo=#self.future,
        strokeCount=strokeCount,fullCount=fullCount,
        tiles=tiles,bytes=bytes,uniqueBuffers=unique,
        budgetBytes=budget,overBudget=bytes>budget}
end

-- Keep the most recent undo or redo action even when one entry alone
-- exceeds the budget. Drop oldest undo first, then most distant redo.
-- Called after writes/detaches and after a brush stroke has finished.
function Document:trimHistory()
    local budget=self.historyBudgetBytes or HISTORY_BUDGET_BYTES
    local info=self:historyStats()
    while info.bytes>budget and (#self.history+#self.future)>1 do
        if #self.history>1 then
            table.remove(self.history,1)
        elseif #self.future>0 then
            table.remove(self.future,1)
        else break end
        info=self:historyStats()
    end
    return info
end

function Document:checkpoint(preserveComposite)
    if not preserveComposite then self:markCompositeDirty() end
    table.insert(self.history, createSnapshot(self))
    if #self.history > MAX_HISTORY then table.remove(self.history, 1) end
    self.future = {}
    self.dirty = true
    self:trimHistory()
end

function Document:undo()
    if #self.history==0 then return false end
    local previous=table.remove(self.history)
    if previous.kind=="stroke" then
        table.insert(self.future,swapStrokeTiles(self,previous))
        self.selected=previous.layerIndex
    else
        table.insert(self.future,createSnapshot(self))
        self.layers,self.selected=previous.layers,previous.selected
    end
    self:markCompositeDirty()
    self.dirty=true
    return true
end

function Document:redo()
    if #self.future==0 then return false end
    local nextEntry=table.remove(self.future)
    if nextEntry.kind=="stroke" then
        table.insert(self.history,swapStrokeTiles(self,nextEntry))
        self.selected=nextEntry.layerIndex
    else
        table.insert(self.history,createSnapshot(self))
        self.layers,self.selected=nextEntry.layers,nextEntry.selected
    end
    self:markCompositeDirty()
    self.dirty=true
    return true
end

function Document:addLayer(name)
    if #self.layers >= MAX_LAYERS then return false end
    self:checkpoint()
    table.insert(self.layers, layer(self.width, self.height, name or ("Camada " .. (#self.layers + 1))))
    self.selected = #self.layers
    return true
end

function Document:removeLayer()
    if #self.layers <= 1 then return false end
    self:checkpoint()
    table.remove(self.layers, self.selected)
    self.selected = math.min(self.selected, #self.layers)
    self:trimHistory()
    return true
end

function Document:moveLayer(delta)
    local index = self.selected
    local target = index + delta
    if target < 1 or target > #self.layers then return false end
    self:checkpoint()
    local selected = table.remove(self.layers, index)
    table.insert(self.layers, target, selected)
    self.selected = target
    return true
end

function Document:toggleLayer(index)
    if not self.layers[index] then return end
    self:checkpoint()
    self.layers[index].visible = not self.layers[index].visible
end

function Document:setLayerOpacity(index, value, alreadyCheckpoint)
    local l = self.layers[index]
    if not l then return end
    value = math.max(0.05, math.min(1, value))
    if math.abs(l.opacity - value) < 0.005 then return end
    if not alreadyCheckpoint then self:checkpoint() end
    l.opacity = value
    self:markCompositeDirty()
end

-- Selection is temporary canvas state, not stored in history or project.
-- Document coordinates are zero-based, right/bottom edges exclusive.
function Document:setSelection(x0,y0,x1,y1)
    x0,y0,x1,y1=tonumber(x0),tonumber(y0),tonumber(x1),tonumber(y1)
    if not x0 or not y0 or not x1 or not y1 then return false end
    local left=math.max(0,math.min(self.width,math.floor(math.min(x0,x1))))
    local top=math.max(0,math.min(self.height,math.floor(math.min(y0,y1))))
    local right=math.max(0,math.min(self.width,math.floor(math.max(x0,x1))+1))
    local bottom=math.max(0,math.min(self.height,math.floor(math.max(y0,y1))+1))
    if left>=right or top>=bottom then return false end
    self.selection={x0=left,y0=top,x1=right,y1=bottom}
    return true
end

function Document:clearSelection()
    self.selection=nil
end

function Document:setLayerAlphaLock(index,enabled)
    local layer=self.layers[index]
    if not layer then return false end
    enabled=not not enabled
    if (layer.alphaLock or false)==enabled then return false end
    self:checkpoint()
    layer.alphaLock=enabled
    return true
end

function Document:setClipping(index,enabled)
    local layer=self.layers[index]
    if not layer or index<=1 or not Native.available() then return false end
    enabled=not not enabled
    if layer.clipping==enabled then return false end
    self:checkpoint()
    layer.clipping=enabled
    return true
end

function Document:createLayerMask(index)
    local layer=self.layers[index]
    if not layer or not Native.available() then return false end
    self:checkpoint()
    layer.mask=newMask(self.width,self.height,self.selection)
    self:trimHistory()
    return true
end

function Document:invertLayerMask(index)
    local layer=self.layers[index]
    if not layer or not layer.mask then return false end
    self:checkpoint()

    -- The mask may be shared by a structural snapshot. Detach first.
    ensureMaskWritable(self,index)
    layer.mask:mapPixel(function(x,y,r,g,b,a)
        return 1-r,1-g,1-b,a
    end)
    self:trimHistory()
    return true
end

function Document:removeLayerMask(index)
    local layer=self.layers[index]
    if not layer or not layer.mask then return false end
    self:checkpoint()
    layer.mask=nil
    self:trimHistory()
    return true
end

function Document:setLayerBlend(index,mode)
    local layer=self.layers[index]
    if not layer or not checkMode(mode) then return false end
    if mode~=0 and not Native.available() then return false end
    if (layer.blendMode or 0)==mode then return false end
    self:checkpoint()
    layer.blendMode=mode
    return true
end

function Document:hasBlendLayers()
    for _,layer in ipairs(self.layers) do
        if layer.visible and ((layer.blendMode or 0)~=0 or
            layer.mask~=nil or layer.clipping) then
            return true
        end
    end
    return false
end

-- Extract an exact source-region mask without mutating the source.
local function subMask(mask,x,y,w,h)
    if not mask then return nil end
    local crop=love.image.newImageData(w,h,"rgba8")
    crop:paste(mask,0,0,x,y,w,h)
    return crop
end

-- Compose one tile from the original source layers. The native compositor
-- sees the same RGBA8 pixels/masks/clipping as the historical full pass.
local function composeTile(self,region)
    local x,y,w,h=region.x,region.y,region.width,region.height
    local base=newCanvas(w,h)
    love.graphics.push("all")
    love.graphics.setCanvas(base)
    love.graphics.clear(1,1,1,1)
    love.graphics.pop()
    local output=base:newImageData()
    for index,layer in ipairs(self.layers) do
        if layer.visible and layer.opacity>0 then
            local source=layer.canvas:newImageData(1,1,x,y,w,h)
            local options={mask=subMask(layer.mask,x,y,w,h),
                clipping=layer.clipping}
            if layer.clipping then
                local preceding=self.layers[index-1]
                if preceding and preceding.visible then
                    options.clip=preceding.canvas:newImageData(1,1,x,y,w,h)
                    options.clipMask=subMask(preceding.mask,x,y,w,h)
                    options.clipOpacity=preceding.opacity
                end
            end
            Native.blendLayer(output,source,layer.opacity,
                layer.blendMode or 0,options)
        end
    end
    return output
end

-- Normal-mode documents keep the GPU fast path. Documents with effects
-- perform a full native pass only at creation/structural invalidation.
-- Brush strokes subsequently recompose ONLY affected 128x128 regions.
function Document:compositedCanvas()
    if not Native.available() then return nil end
    if not self.compositeDirty and self.compositeCanvas then
        return self.compositeCanvas
    end
    local metrics=self.compositeMetrics
    local full=self.compositeInvalidFull or not self.compositeCanvas
    local canvas=self.compositeCanvas or newCanvas(self.width,self.height)
    -- The full pass is streamed in 512x512 chunks, rather than reading
    -- 4096x4096 RGBA from every visible source layer in one allocation.
    -- Brush updates retain finer 128x128 regions for better responsiveness.
    local buildSize=full and COMPOSITE_BUILD_TILE or COMPOSITE_TILE
    local regions={}
    if full then
        for y=0,self.height-1,buildSize do
            for x=0,self.width-1,buildSize do
                regions[#regions+1]={
                    x=x,y=y,
                    width=math.min(buildSize,self.width-x),
                    height=math.min(buildSize,self.height-y)
                }
            end
        end
    else
        for _,region in pairs(self.compositeDirtyTiles) do
            regions[#regions+1]=region
        end
    end
    local count,pixels,peak=0,0,0
    for _,region in ipairs(regions) do
        -- Source GPU readbacks must happen with no destination canvas bound.
        local sub=composeTile(self,region)
        local image=love.graphics.newImage(sub)
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.setBlendMode("replace","premultiplied")
        love.graphics.setColor(1,1,1,1)
        love.graphics.draw(image,region.x,region.y)
        love.graphics.pop()
        count=count+1
        local area=region.width*region.height
        pixels=pixels+area
        peak=math.max(peak,area)
        -- A region's temporary texture need not survive the subsequent
        -- readback: do not accumulate a full document of temporary images.
        image:release()
    end
    self.compositeCanvas=canvas
    self.compositeInvalidFull=false
    self.compositeDirtyTiles={}
    self.compositeDirty=false
    if full then
        metrics.fullBuilds=metrics.fullBuilds+1
    else
        metrics.partialBuilds=metrics.partialBuilds+1
    end
    metrics.lastBatches=count
    metrics.lastTiles=full and
        math.ceil(self.width/COMPOSITE_TILE)*
        math.ceil(self.height/COMPOSITE_TILE) or count
    metrics.lastPixels=pixels
    metrics.totalPixels=metrics.totalPixels+pixels
    metrics.peakRegionPixels=math.max(metrics.peakRegionPixels,peak)
    -- Count regional source reads, separate from the final composite GPU
    -- and from LÖVE's internally managed memory allocations.
    local visible=0
    for _,layer in ipairs(self.layers) do
        if layer.visible and layer.opacity>0 then
            visible=visible+1
        end
    end
    metrics.regionReads=metrics.regionReads+count*visible
    return canvas
end

-- Profiling counters describe work performed, not measured RAM or elapsed
-- time. peakRegionPixels bounds one temporary RGBA buffer at a time.
function Document:compositorStats()
    local m=self.compositeMetrics
    return {fullBuilds=m.fullBuilds,partialBuilds=m.partialBuilds,
        lastTiles=m.lastTiles,lastPixels=m.lastPixels,
        totalPixels=m.totalPixels,tileSize=COMPOSITE_TILE,
        buildTileSize=COMPOSITE_BUILD_TILE,lastBatches=m.lastBatches,
        peakRegionPixels=m.peakRegionPixels,regionReads=m.regionReads}
end

-- Upload a filled CPU rectangle without replacing the entire canvas.
-- The undo entry captures only touched tiles and is compatible with COW.
function Document:applyFillRegion(index,imageData,dirty)
    assert(index==self.selected and self.layers[index],"Camada de preenchimento invalida")
    assert(imageData:getWidth()==self.width and imageData:getHeight()==self.height,
        "Dimensoes invalidas para preenchimento")
    local x,y,w,h=dirty.x,dirty.y,dirty.width,dirty.height
    assert(x>=0 and y>=0 and w>0 and h>0 and x+w<=self.width and y+h<=self.height,
        "Retangulo de preenchimento invalido")
    self:beginStrokeHistory()
    self:ensureLayerWritable(index)
    assert(self:captureHistoryRect(x,y,w,h))
    local part=love.image.newImageData(w,h,"rgba8")
    part:paste(imageData,0,0,x,y,w,h)
    local upload=love.graphics.newImage(part)
    local canvas=self.layers[index].canvas
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.setBlendMode("replace","premultiplied")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(upload,x,y)
    love.graphics.pop()
    upload:release()
    Native.invalidate(canvas)
    self:markCompositeDirty(dirty)
    self:trimHistory()
    return true
end

-- Atualiza uma camada inteira como uma unica operacao de desfazer.
function Document:replaceLayerData(index, imageData)
    assert(imageData:getWidth()==self.width and imageData:getHeight()==self.height,
        "Dimensoes invalidas")
    if not self.layers[index] then error("Camada inexistente") end
    self:checkpoint()
    local canvas=newCanvas(self.width,self.height)
    local image=love.graphics.newImage(imageData)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image)
    love.graphics.pop()
    Native.invalidate(canvas)
    self.layers[index].canvas=canvas
    self:trimHistory()
end

-- Compoe amostras de 1 pixel das camadas visiveis.
function Document:sampleColor(px,py)
    px,py=math.floor(px),math.floor(py)
    if px<0 or py<0 or px>=self.width or py>=self.height then return nil end
    if self:hasBlendLayers() and Native.available() then
        local canvas=self:compositedCanvas()
        local image=canvas:newImageData(1,1,px,py,1,1)
        local r,g,b=image:getPixel(0,0)
        return {r,g,b}
    end
    local r,g,b=1,1,1
    for _,l in ipairs(self.layers) do
        if l.visible and l.opacity>0 then
            local pixel=l.canvas:newImageData(1,1,px,py,1,1)
            local pr,pg,pb,pa=pixel:getPixel(0,0)
            local a=pa*l.opacity
            r,g,b=pr*a+r*(1-a),pg*a+g*(1-a),pb*a+b*(1-a)
        end
    end
    return {r,g,b}
end

function Document:draw(x, y, scale)
    if self:hasBlendLayers() and Native.available() then
        local composite=self:compositedCanvas()
        love.graphics.push("all")
        love.graphics.setColor(1,1,1,1)
        love.graphics.setBlendMode("alpha","alphamultiply")
        love.graphics.draw(composite,x,y,0,scale,scale)
        love.graphics.pop()
        return
    end
    love.graphics.push("all")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", x, y, self.width * scale, self.height * scale)
    love.graphics.setBlendMode("alpha", "premultiplied")
    for _, l in ipairs(self.layers) do
        if l.visible then
            love.graphics.setColor(1, 1, 1, l.opacity)
            love.graphics.draw(l.canvas, x, y, 0, scale, scale)
        end
    end
    love.graphics.pop()
end

local function pngBytes(canvas)
    return canvas:newImageData():encode("png"):getString()
end

function Document:save(name)
    self.name = cleanText(name or self.name)
    if self.name == "" then self.name = "Sem titulo" end
    if not self.projectKey then
        self.projectKey = os.date("%Y%m%d-%H%M%S") .. "-" .. tostring(love.math.random(100000, 999999))
    end
    local root = "projects/" .. self.projectKey
    assert(love.filesystem.createDirectory(root))
    local manifest = {
        "INKORA1",
        "size\t" .. self.width .. "\t" .. self.height,
        "name\t" .. self.name,
        "selected\t" .. self.selected,
    }
    for i, l in ipairs(self.layers) do
        assert(love.filesystem.write(root .. ("/layer-%02d.png"):format(i), pngBytes(l.canvas)))
        if l.mask then
            assert(love.filesystem.write(root .. ("/mask-%02d.png"):format(i),
                l.mask:encode("png"):getString()))
        end
        manifest[#manifest + 1] = table.concat({
            "layer", l.visible and "1" or "0",
            ("%.4f"):format(l.opacity), cleanText(l.name),
            tostring(l.blendMode or 0), l.alphaLock and "1" or "0",
            l.clipping and "1" or "0", l.mask and "1" or "0",
        }, "\t")
    end
    assert(love.filesystem.write(root .. "/manifest.txt", table.concat(manifest, "\n") .. "\n"))
    self.dirty = false
    return love.filesystem.getSaveDirectory() .. "/" .. root
end

local function splitTabs(line)
    local fields = {}
    for part in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = part end
    return fields
end

function Document.listProjects()
    if not love.filesystem.getInfo("projects", "directory") then return {} end
    local projects = {}
    for _, key in ipairs(love.filesystem.getDirectoryItems("projects")) do
        if key:match("^[%w%-]+$") then
            local s = love.filesystem.read("projects/" .. key .. "/manifest.txt")
            if s and s:match("^INKORA1\n") then
                local name = s:match("\nname\t([^\r\n]+)") or key
                projects[#projects + 1] = {key = key, name = name}
            end
        end
    end
    table.sort(projects, function(a, b) return a.key > b.key end)
    return projects
end

function Document.load(key)
    if not key:match("^[%w%-]+$") then error("Nome de projeto invalido") end
    local root = "projects/" .. key
    local manifest = assert(love.filesystem.read(root .. "/manifest.txt"), "Projeto nao encontrado")
    local lines = {}
    for line in manifest:gmatch("[^\r\n]+") do lines[#lines + 1] = splitTabs(line) end
    if not lines[1] or lines[1][1] ~= "INKORA1" then error("Manifesto invalido") end
    if not lines[2] or lines[2][1] ~= "size" then error("Dimensoes ausentes") end
    local w, h = tonumber(lines[2][2]), tonumber(lines[2][3])
    if not w or not h or w % 1 ~= 0 or h % 1 ~= 0 then error("Dimensoes invalidas") end
    local result = Document.new(w, h, lines[3] and cleanText(lines[3][2]) or "Sem titulo")
    result.layers = {}
    for n = 5, #lines do
        local fields = lines[n]
        if fields[1] == "layer" then
            if #result.layers >= MAX_LAYERS then error("Camadas em excesso") end
            local path = root .. ("/layer-%02d.png"):format(#result.layers + 1)
            local data = love.image.newImageData(path)
            if data:getWidth() ~= w or data:getHeight() ~= h then error("Dimensao de camada divergente") end
            local l = layer(w, h, cleanText(fields[4]) or ("Camada " .. n))
            local image = love.graphics.newImage(data)
            love.graphics.push("all")
            love.graphics.setCanvas(l.canvas)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setBlendMode("alpha", "premultiplied")
            love.graphics.draw(image)
            love.graphics.pop()
            Native.invalidate(l.canvas)
            l.visible = fields[2] == "1"
            l.opacity = math.max(0, math.min(1, tonumber(fields[3]) or 1))
            local mode=tonumber(fields[5]) or 0
            l.blendMode=checkMode(mode) and mode or 0 -- backwards compatible
            l.alphaLock=fields[6]=="1"
            l.clipping=fields[7]=="1" and #result.layers>=1
            if fields[8]=="1" then
                local maskPath=root .. ("/mask-%02d.png"):format(#result.layers+1)
                local mask=love.image.newImageData(maskPath)
                if mask:getWidth()~=w or mask:getHeight()~=h or
                    mask:getFormat()~="rgba8" then
                    error("Mascara de camada invalida")
                end
                l.mask=mask
            end
            table.insert(result.layers, l)
        end
    end
    if #result.layers < 1 then error("Projeto sem camadas") end
    result.selected = math.max(1, math.min(#result.layers, tonumber(lines[4] and lines[4][2]) or 1))
    result.projectKey, result.dirty = key, false
    return result
end

function Document:exportPNG()
    local output
    if self:hasBlendLayers() and Native.available() then
        output=self:compositedCanvas()
    else
        output=newCanvas(self.width,self.height)
        love.graphics.push("all")
    love.graphics.setCanvas(output)
    love.graphics.clear(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "premultiplied")
    for _, l in ipairs(self.layers) do
        if l.visible then
            love.graphics.setColor(1, 1, 1, l.opacity)
            love.graphics.draw(l.canvas)
        end
    end
        love.graphics.pop()
    end
    assert(love.filesystem.createDirectory("exports"))
    local safe = self.name:gsub("[^%w%-_]", "_"):sub(1, 35)
    local name = (safe ~= "" and safe or "Inkora") .. "-" .. os.date("%Y%m%d-%H%M%S") .. ".png"
    assert(love.filesystem.write("exports/" .. name, pngBytes(output)))
    return love.filesystem.getSaveDirectory() .. "/exports/" .. name
end

function Document:importPNG(file)
    file:open("r")
    local bytes = file:read()
    file:close()
    if not bytes then error("Nao foi possivel ler a imagem") end
    local imageData = love.image.newImageData(love.filesystem.newFileData(bytes, "import.png"))
    if not self:addLayer("Imagem importada") then error("Limite de camadas atingido") end
    local iw, ih = imageData:getDimensions()
    local factor = math.min(1, self.width / iw, self.height / ih)
    local image = love.graphics.newImage(imageData)
    love.graphics.push("all")
    love.graphics.setCanvas(self.layers[self.selected].canvas)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.draw(image, (self.width - iw * factor)/2, (self.height - ih * factor)/2, 0, factor, factor)
    love.graphics.pop()
    Native.invalidate(self.layers[self.selected].canvas)
    self.dirty = true
end

return Document
