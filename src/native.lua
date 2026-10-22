-- Inkora ABI v2: gerenciamento de tiles RGBA8 para o motor raster em C++.
-- Tiles CPU (128x128) sao inicializados sob demanda lendo apenas seu recorte da GPU.
-- Permanecem em cache entre pinceladas, removendo a leitura integral por stroke.
-- O C++ e responsavel pelo pixel/alpha; Lua organiza entrada e upload por tiles.
local Native={library=nil,error=nil,attempted=false,lastUpload=nil}
local ffiOK,ffi=pcall(require,"ffi")
local TILE_SIZE=128
local layerCaches=setmetatable({},{__mode="k"})
local metrics={readbacks=0,readbackPixels=0,uploadedPixels=0,uploadCalls=0,cacheHits=0,zeroTiles=0}

if ffiOK then
    ffi.cdef[[
    typedef struct InkoraStroke {
        uint8_t *pixels;
        int32_t width, height, stride;
        uint64_t buffer_bytes;
        float x0, y0, x1, y1;
        float diameter, hardness, opacity, spacing;
        float r, g, b, pressure0, pressure1;
        int32_t eraser;
    } InkoraStroke;
    typedef struct InkoraStrokeState {
        float distance_to_next;
        int32_t initialized;
    } InkoraStrokeState;
    typedef struct InkoraRect {
        int32_t x, y, width, height;
    } InkoraRect;
    int32_t inkora_core_api_version(void);
    int32_t inkora_core_stroke_v2(const InkoraStroke *stroke,
        InkoraStrokeState *state, InkoraRect *dirty);
    ]]
end

local function locations()
    local out={}
    local override=os.getenv("INKORA_CORE_PATH")
    if override and override~="" then out[#out+1]=override end
    local base=love and love.filesystem and love.filesystem.getSourceBaseDirectory()
    local osname=love and love.system and love.system.getOS() or "Linux"
    local lib=osname=="Windows" and "inkora_core.dll"
        or osname=="OS X" and "libinkora_core.dylib" or "libinkora_core.so"
    if base then
        out[#out+1]=base.."/"..lib
        out[#out+1]=base.."/build/native/"..lib
        out[#out+1]=base.."/native/"..lib
        out[#out+1]=base.."/build/native/Release/"..lib
    end
    return out
end

function Native.available()
    if Native.attempted then return Native.library~=nil end
    Native.attempted=true
    if not ffiOK then
        Native.error="LuaJIT FFI indisponivel"
        return false
    end
    for _,p in ipairs(locations()) do
        local ok,lib=pcall(ffi.load,p)
        if ok then
            local vok,version=pcall(function() return tonumber(lib.inkora_core_api_version()) end)
            if vok and version==2 then
                Native.library=lib;Native.path=p;Native.error=nil
                return true
            end
            Native.error="ABI C++ incompativel (requer v2)"
        end
    end
    Native.error=Native.error or "inkora_core nao encontrado (modo Lua)"
    return false
end

-- Invalide sempre que uma operacao fora do core C++ alterar esse Canvas.
-- Historico/undo pode reutilizar canvases anteriores, que sao chaves fracas.
function Native.invalidate(canvas)
    if canvas then layerCaches[canvas]=nil end
end

-- So pode ser chamado em canvases sabidamente transparentes e nao desenhados.
-- Evita o primeiro readback ao editar camadas novas vazias.
function Native.registerBlank(canvas)
    if not canvas then return end
    local w,h=canvas:getDimensions()
    layerCaches[canvas]={canvas=canvas,width=w,height=h,tiles={},blank=true}
end

function Native.stats()
    local out={}
    for k,v in pairs(metrics) do out[k]=v end
    return out
end

function Native.resetStats()
    for k in pairs(metrics) do metrics[k]=0 end
end

local function getTile(cache,tx,ty)
    local key=tx..":"..ty
    local tile=cache.tiles[key]
    if tile then
        metrics.cacheHits=metrics.cacheHits+1
        return tile
    end
    local x,y=tx*TILE_SIZE,ty*TILE_SIZE
    local w=math.min(TILE_SIZE,cache.width-x)
    local h=math.min(TILE_SIZE,cache.height-y)
    local data
    if cache.blank then
        data=love.image.newImageData(w,h,"rgba8")
        metrics.zeroTiles=metrics.zeroTiles+1
    else
        data=cache.canvas:newImageData(1,1,x,y,w,h)
        metrics.readbacks=metrics.readbacks+1
        metrics.readbackPixels=metrics.readbackPixels+w*h
    end
    assert(data:getFormat()=="rgba8","Inkora exige RGBA8 para tiles")
    local image=love.graphics.newImage(data)
    image:setFilter("nearest","nearest")
    tile={x=x,y=y,w=w,h=h,data=data,image=image}
    cache.tiles[key]=tile
    return tile
end

function Native.beginStroke(canvas,settings)
    if not Native.available() then return nil end
    local cache=layerCaches[canvas]
    if not cache then
        local w,h=canvas:getDimensions()
        cache={canvas=canvas,width=w,height=h,tiles={}}
        layerCaches[canvas]=cache
    end
    return {cache=cache,canvas=canvas,settings=settings or {},
        state=ffi.new("InkoraStrokeState[1]")}
end

local function paintTile(session,tile,x0,y0,x1,y1,color,diameter,opacity,
                         eraser,pressure0,pressure1,originalState)
    local stroke=ffi.new("InkoraStroke[1]")
    local s=stroke[0]
    s.pixels=ffi.cast("uint8_t*",tile.data:getFFIPointer())
    s.width=tile.w;s.height=tile.h;s.stride=tile.w*4
    s.buffer_bytes=tile.data:getSize()
    s.x0=x0-tile.x;s.y0=y0-tile.y
    s.x1=x1-tile.x;s.y1=y1-tile.y
    s.diameter=diameter;s.hardness=session.settings.hardness or 0.82
    s.opacity=opacity;s.spacing=session.settings.spacing or 0.18
    s.r=color[1];s.g=color[2];s.b=color[3]
    s.pressure0=pressure0 or 1;s.pressure1=pressure1 or 1
    s.eraser=eraser and 1 or 0
    local localState=ffi.new("InkoraStrokeState[1]")
    localState[0].distance_to_next=originalState.distance_to_next
    localState[0].initialized=originalState.initialized
    local dirty=ffi.new("InkoraRect[1]")
    if Native.library.inkora_core_stroke_v2(stroke,localState,dirty)~=1 then
        error("Motor C++ recusou segmento por tile")
    end
    return {x=tonumber(dirty[0].x),y=tonumber(dirty[0].y),
        width=tonumber(dirty[0].width),height=tonumber(dirty[0].height)},
        {distance_to_next=tonumber(localState[0].distance_to_next),
         initialized=tonumber(localState[0].initialized)}
end

local function updateTile(session,tile,r)
    if r.width<=0 or r.height<=0 then return end
    local patch=love.image.newImageData(r.width,r.height,"rgba8")
    patch:paste(tile.data,0,0,r.x,r.y,r.width,r.height)
    tile.image:replacePixels(patch,1,1,r.x,r.y)
    local quad=love.graphics.newQuad(r.x,r.y,r.width,r.height,tile.w,tile.h)
    love.graphics.push("all")
    love.graphics.setCanvas(session.canvas)
    love.graphics.setBlendMode("replace","premultiplied")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(tile.image,quad,tile.x+r.x,tile.y+r.y)
    love.graphics.pop()
    local px=r.width*r.height
    metrics.uploadCalls=metrics.uploadCalls+1
    metrics.uploadedPixels=metrics.uploadedPixels+px
    return {x=tile.x+r.x,y=tile.y+r.y,width=r.width,height=r.height}
end

local function union(a,b)
    if not a then return b end
    local x=math.min(a.x,b.x),y=math.min(a.y,b.y)
    local right=math.max(a.x+a.width,b.x+b.width)
    local bottom=math.max(a.y+a.height,b.y+b.height)
    return {x=x,y=y,width=right-x,height=bottom-y}
end

local function advanceState(session,x0,y0,x1,y1,color,diameter,opacity,
                            eraser,pressure0,pressure1,originalState)
    -- Sem tiles visiveis: avance a fase de spacing via um bitmap descartavel.
    local empty={x=-10000,y=-10000,w=1,h=1,data=session.dummy}
    if not empty.data then
        session.dummy=love.image.newImageData(1,1,"rgba8")
        empty.data=session.dummy
    end
    local _,updated=paintTile(session,empty,x0,y0,x1,y1,color,diameter,opacity,
        eraser,pressure0,pressure1,originalState)
    return updated
end

function Native.segment(session,x0,y0,x1,y1,color,diameter,opacity,eraser,pressure0,pressure1)
    if not session or not Native.available() then return false end
    local cache=session.cache
    local radius=math.max(0.5,diameter/2)+2
    local left=math.max(0,math.floor(math.min(x0,x1)-radius))
    local top=math.max(0,math.floor(math.min(y0,y1)-radius))
    local right=math.min(cache.width-1,math.ceil(math.max(x0,x1)+radius))
    local bottom=math.min(cache.height-1,math.ceil(math.max(y0,y1)+radius))
    local old=session.state[0]
    local initial={distance_to_next=old.distance_to_next,initialized=old.initialized}
    local newState=nil
    local bounds=nil
    local pixels=0

    if left<=right and top<=bottom then
        for ty=math.floor(top/TILE_SIZE),math.floor(bottom/TILE_SIZE) do
            for tx=math.floor(left/TILE_SIZE),math.floor(right/TILE_SIZE) do
                local tile=getTile(cache,tx,ty)
                local dirty,state=paintTile(session,tile,x0,y0,x1,y1,color,diameter,
                    opacity,eraser,pressure0,pressure1,initial)
                newState=state
                if dirty.width>0 and dirty.height>0 then
                    local updated=updateTile(session,tile,dirty)
                    bounds=union(bounds,updated)
                    pixels=pixels+dirty.width*dirty.height
                end
            end
        end
    end
    if not newState then
        newState=advanceState(session,x0,y0,x1,y1,color,diameter,opacity,
            eraser,pressure0,pressure1,initial)
    end
    session.state[0].distance_to_next=newState.distance_to_next
    session.state[0].initialized=newState.initialized

    Native.lastUpload=bounds or {x=0,y=0,width=0,height=0}
    Native.lastUpload.pixels=pixels
    return true
end

return Native
