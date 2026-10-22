local Native = require("src.native")
local Document = {}
Document.__index = Document

local MAX_LAYERS = 16
local MAX_HISTORY = 10
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

local function layer(w, h, name)
    local canvas = newCanvas(w, h)
    Native.registerBlank(canvas)
    return {canvas = canvas, name = name, opacity = 1, visible = true, blendMode=0}
end

local function cleanText(s)
    s = tostring(s or ""):gsub("[\r\n\t]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s:sub(1, 64)
end

local function createSnapshot(self)
    local snap = {layers = {}, selected = self.selected}
    for i, l in ipairs(self.layers) do
        snap.layers[i] = {
            canvas = cloneCanvas(l.canvas, self.width, self.height),
            name = l.name, opacity = l.opacity, visible = l.visible,
            blendMode = l.blendMode or 0,
        }
    end
    return snap
end

function Document.new(w, h, name)
    assert(w >= 64 and h >= 64 and w <= 4096 and h <= 4096, "Tamanho invalido")
    local self = setmetatable({
        width = w, height = h, name = name or "Sem titulo",
        selected = 1, layers = {layer(w, h, "Camada 1")},
        history = {}, future = {}, dirty = false, projectKey = nil,
        compositeDirty=true, compositeCanvas=nil,
    }, Document)
    return self
end

function Document:markCompositeDirty()
    self.compositeDirty=true
end

function Document:checkpoint()
    self:markCompositeDirty()
    table.insert(self.history, createSnapshot(self))
    if #self.history > MAX_HISTORY then table.remove(self.history, 1) end
    self.future = {}
    self.dirty = true
end

function Document:undo()
    if #self.history == 0 then return false end
    table.insert(self.future, createSnapshot(self))
    local snap = table.remove(self.history)
    self.layers, self.selected = snap.layers, snap.selected
    self:markCompositeDirty()
    self.dirty = true
    return true
end

function Document:redo()
    if #self.future == 0 then return false end
    table.insert(self.history, createSnapshot(self))
    local snap = table.remove(self.future)
    self.layers, self.selected = snap.layers, snap.selected
    self:markCompositeDirty()
    self.dirty = true
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
        if layer.visible and (layer.blendMode or 0)~=0 then return true end
    end
    return false
end

-- On-demand C++ compositor. Normal-mode documents keep the fast GPU path.
-- The composited bitmap is cached until a pixel/visibility/blend change.
function Document:compositedCanvas()
    if not Native.available() then return nil end
    if not self.compositeDirty and self.compositeCanvas then return self.compositeCanvas end
    local white=newCanvas(self.width,self.height)
    love.graphics.push("all")
    love.graphics.setCanvas(white)
    love.graphics.clear(1,1,1,1)
    love.graphics.pop()
    local pixels=white:newImageData()
    for _,layer in ipairs(self.layers) do
        if layer.visible and layer.opacity>0 then
            local source=layer.canvas:newImageData()
            Native.blendLayer(pixels,source,layer.opacity,layer.blendMode or 0)
        end
    end
    local image=love.graphics.newImage(pixels)
    local canvas=self.compositeCanvas or newCanvas(self.width,self.height)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.setBlendMode("replace","premultiplied")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image)
    love.graphics.pop()
    self.compositeCanvas=canvas
    self.compositeDirty=false
    return canvas
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
        manifest[#manifest + 1] = table.concat({
            "layer", l.visible and "1" or "0",
            ("%.4f"):format(l.opacity), cleanText(l.name),
            tostring(l.blendMode or 0),
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
