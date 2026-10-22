-- Inkora ABI v3: cache LRU de tiles RGBA8 + pontas nativas em C++.
-- Tiles CPU (128x128) sao inicializados sob demanda lendo apenas seu recorte da GPU.
-- Permanecem em cache entre pinceladas, removendo a leitura integral por stroke.
-- O C++ e responsavel pelo pixel/alpha; Lua organiza entrada e upload por tiles.
local Native={library=nil,error=nil,attempted=false,lastUpload=nil}
local ffiOK,ffi=pcall(require,"ffi")
local TILE_SIZE=128
local TILE_LIMIT=math.max(4,math.min(256,math.floor(tonumber(os.getenv("INKORA_TILE_LIMIT")) or 96)))
local layerCaches=setmetatable({},{__mode="k"})
local metrics={readbacks=0,readbackPixels=0,uploadedPixels=0,uploadCalls=0,cacheHits=0,zeroTiles=0,evictions=0,pigmentSamples=0}

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
    typedef struct InkoraTip {
        int32_t tip;
        float aspect, angle, grain;
        uint32_t seed;
        int32_t origin_x, origin_y;
    } InkoraTip;
    typedef struct InkoraMask {
        const uint8_t *alpha;
        int32_t width, height, stride;
        uint64_t buffer_bytes;
    } InkoraMask;
    typedef struct InkoraPaintClip {
        int32_t alpha_lock, selection_enabled;
        int32_t left, top, right, bottom;
    } InkoraPaintClip;
    typedef struct InkoraBrushDirection {
        int32_t follow_path;
        int32_t initialized;
        float angle_degrees;
    } InkoraBrushDirection;
    typedef struct InkoraBrushDynamics {
        float texture, scatter, size_jitter;
        uint32_t stamp_index;
    } InkoraBrushDynamics;
    typedef struct InkoraWetPaint {
        float wetness, pigment_load;
    } InkoraWetPaint;
    typedef struct InkoraPigmentCarry {
        float pickup, retention;
        float sample_r, sample_g, sample_b, sample_a;
        float reservoir_r, reservoir_g, reservoir_b;
        int32_t initialized;
    } InkoraPigmentCarry;
    typedef struct InkoraDabSamples {
        const uint8_t *rgba;
        uint64_t buffer_bytes;
        uint32_t count;
    } InkoraDabSamples;
    typedef struct InkoraLayerEffects {
        const uint8_t *mask_rgba;
        uint64_t mask_bytes;
        int32_t mask_stride;
        int32_t clipping_enabled;
        const uint8_t *clip_rgba;
        uint64_t clip_bytes;
        int32_t clip_stride;
        float clip_opacity;
        const uint8_t *clip_mask_rgba;
        uint64_t clip_mask_bytes;
        int32_t clip_mask_stride;
    } InkoraLayerEffects;
    int32_t inkora_core_blend_layer(
        uint8_t* out_rgba, uint64_t out_bytes, int32_t out_stride,
        const uint8_t* layer_rgba, uint64_t layer_bytes, int32_t layer_stride,
        int32_t width, int32_t height, float opacity, int32_t blend_mode);
    int32_t inkora_core_blend_layer_v7(
        uint8_t* out_rgba, uint64_t out_bytes, int32_t out_stride,
        const uint8_t* layer_rgba, uint64_t layer_bytes, int32_t layer_stride,
        int32_t width, int32_t height, float opacity, int32_t blend_mode,
        const InkoraLayerEffects *effects);
    int32_t inkora_core_api_version(void);
    int32_t inkora_core_dab_positions_v12(
        const InkoraStrokeState *state,
        float x0, float y0, float x1, float y1,
        float diameter, float spacing, float *out_xy,
        uint32_t capacity, uint32_t *count);
    int32_t inkora_core_stroke_v12(const InkoraStroke *stroke,
        InkoraStrokeState *state, InkoraRect *dirty, const InkoraTip *tip,
        const InkoraMask *mask, float flow, float pressure_opacity,
        const InkoraPaintClip *clip, InkoraBrushDirection *direction,
        InkoraBrushDynamics *dynamics, const InkoraWetPaint *wet,
        InkoraPigmentCarry *carry, const InkoraDabSamples *samples);
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
            if vok and version==12 then
                Native.library=lib;Native.path=p;Native.error=nil
                return true
            end
            Native.error="ABI C++ incompativel (requer v12)"
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
    layerCaches[canvas]={width=w,height=h,tiles={},count=0,clock=0,blank=true,touched={}}
end

function Native.stats()
    local out={}
    for k,v in pairs(metrics) do out[k]=v end
    return out
end

function Native.cacheSize(canvas)
    local cache=layerCaches[canvas]
    return cache and cache.count or 0
end

function Native.tileLimit()
    return TILE_LIMIT
end

function Native.resetStats()
    for k in pairs(metrics) do metrics[k]=0 end
end

local function getTile(cache,canvas,tx,ty)
    local key=tx..":"..ty
    cache.clock=cache.clock+1
    local tile=cache.tiles[key]
    if tile then
        tile.used=cache.clock
        metrics.cacheHits=metrics.cacheHits+1
        return tile
    end
    if cache.count>=TILE_LIMIT then
        local oldestKey,oldestTick=nil,math.huge
        for k,existing in pairs(cache.tiles) do
            if existing.used<oldestTick then
                oldestTick=existing.used
                oldestKey=k
            end
        end
        if oldestKey then
            -- Todos os pixels ja foram enviados ao Canvas; podemos ler o tile
            -- novamente da GPU quando ele voltar a ser usado.
            cache.tiles[oldestKey]=nil
            cache.count=cache.count-1
            metrics.evictions=metrics.evictions+1
        end
    end
    local x,y=tx*TILE_SIZE,ty*TILE_SIZE
    local w=math.min(TILE_SIZE,cache.width-x)
    local h=math.min(TILE_SIZE,cache.height-y)
    local data
    if cache.blank and not cache.touched[key] then
        data=love.image.newImageData(w,h,"rgba8")
        metrics.zeroTiles=metrics.zeroTiles+1
    else
        data=canvas:newImageData(1,1,x,y,w,h)
        metrics.readbacks=metrics.readbacks+1
        metrics.readbackPixels=metrics.readbackPixels+w*h
    end
    assert(data:getFormat()=="rgba8","Inkora exige RGBA8 para tiles")
    local image=love.graphics.newImage(data)
    image:setFilter("nearest","nearest")
    tile={key=key,x=x,y=y,w=w,h=h,data=data,image=image,used=cache.clock}
    cache.tiles[key]=tile
    cache.count=cache.count+1
    return tile
end

-- Create one-channel straight-alpha mask from an ImageData.
-- If all pixels are opaque, treat the bitmap as black-on-white artwork.
-- The returned cdata buffer is owned by Lua and kept alive by stroke settings.
function Native.createMask(imageData)
    assert(ffiOK, "LuaJIT FFI necessaria para mascara")
    local w,h=imageData:getDimensions()
    assert(w>=1 and h>=1 and w<=512 and h<=512,
        "Ponta de pincel deve ter ate 512x512 pixels")
    local alpha=ffi.new("uint8_t[?]",w*h)
    local opaque=true
    for y=0,h-1 do for x=0,w-1 do
        local _,_,_,a=imageData:getPixel(x,y)
        if a<0.999 then opaque=false end
    end end
    for y=0,h-1 do for x=0,w-1 do
        local r,g,b,a=imageData:getPixel(x,y)
        local value=opaque and (1-(r*0.2126+g*0.7152+b*0.0722)) or a
        alpha[y*w+x]=math.floor(math.max(0,math.min(1,value))*255+0.5)
    end end
    return {buffer=alpha,width=w,height=h,stride=w,bytes=w*h}
end

function Native.beginStroke(canvas,settings)
    if not Native.available() then return nil end
    local cache=layerCaches[canvas]
    if not cache then
        local w,h=canvas:getDimensions()
        cache={width=w,height=h,tiles={},count=0,clock=0,blank=false,touched={}}
        layerCaches[canvas]=cache
    end
    return {cache=cache,canvas=canvas,settings=settings or {},
        state=ffi.new("InkoraStrokeState[1]"),
        direction=ffi.new("InkoraBrushDirection[1]"),
        dynamics=ffi.new("InkoraBrushDynamics[1]"),
        carry=ffi.new("InkoraPigmentCarry[1]")}
end

local function paintTile(session,tile,x0,y0,x1,y1,color,diameter,opacity,
                         eraser,pressure0,pressure1,originalState,originalDirection,originalDynamics,originalCarry,samples)
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
    local tip=ffi.new("InkoraTip[1]")
    tip[0].tip=(session.settings.tip==3) and 0 or (session.settings.tip or 0)
    tip[0].aspect=session.settings.aspect or 0.30
    tip[0].angle=session.settings.angle or 0
    tip[0].grain=session.settings.grain or 0.85
    tip[0].seed=session.settings.seed or 239
    tip[0].origin_x=tile.x
    tip[0].origin_y=tile.y
    local custom=session.settings.mask
    local mask=nil
    if custom then
        mask=ffi.new("InkoraMask[1]")
        mask[0].alpha=ffi.cast("const uint8_t*",custom.buffer)
        mask[0].width=custom.width
        mask[0].height=custom.height
        mask[0].stride=custom.stride
        mask[0].buffer_bytes=custom.bytes
    end
    local clip=ffi.new("InkoraPaintClip[1]")
    clip[0].alpha_lock=session.settings.alphaLock and 1 or 0
    local selection=session.settings.selection
    if selection then
        clip[0].selection_enabled=1
        clip[0].left=selection.x0
        clip[0].top=selection.y0
        clip[0].right=selection.x1
        clip[0].bottom=selection.y1
    end
    local localState=ffi.new("InkoraStrokeState[1]")
    localState[0].distance_to_next=originalState.distance_to_next
    localState[0].initialized=originalState.initialized
    local direction=ffi.new("InkoraBrushDirection[1]")
    direction[0].follow_path=session.settings.followPath and 1 or 0
    direction[0].initialized=originalDirection.initialized
    direction[0].angle_degrees=originalDirection.angle_degrees
    local dynamic=ffi.new("InkoraBrushDynamics[1]")
    dynamic[0].texture=session.settings.texture or 0
    dynamic[0].scatter=session.settings.scatter or 0
    dynamic[0].size_jitter=session.settings.sizeJitter or 0
    dynamic[0].stamp_index=originalDynamics.stamp_index
    local wet=ffi.new("InkoraWetPaint[1]")
    wet[0].wetness=session.settings.wetness or 0
    wet[0].pigment_load=session.settings.pigmentLoad or 1
    local carry=ffi.new("InkoraPigmentCarry[1]")
    carry[0].pickup=session.settings.pigmentPickup or 0
    carry[0].retention=session.settings.pigmentRetention or 0
    carry[0].sample_r=originalCarry.sample_r
    carry[0].sample_g=originalCarry.sample_g
    carry[0].sample_b=originalCarry.sample_b
    carry[0].sample_a=originalCarry.sample_a
    carry[0].reservoir_r=originalCarry.reservoir_r
    carry[0].reservoir_g=originalCarry.reservoir_g
    carry[0].reservoir_b=originalCarry.reservoir_b
    carry[0].initialized=originalCarry.initialized
    local dirty=ffi.new("InkoraRect[1]")
    if Native.library.inkora_core_stroke_v12(stroke,localState,dirty,tip,mask,
            session.settings.flow or 1,session.settings.pressureOpacity or 0,
            clip,direction,dynamic,wet,carry,samples and samples.packet or nil)~=1 then
        error("Motor C++ recusou segmento por tile")
    end
    return {x=tonumber(dirty[0].x),y=tonumber(dirty[0].y),
        width=tonumber(dirty[0].width),height=tonumber(dirty[0].height)},
        {distance_to_next=tonumber(localState[0].distance_to_next),
         initialized=tonumber(localState[0].initialized)},
        {angle_degrees=tonumber(direction[0].angle_degrees),
         initialized=tonumber(direction[0].initialized)},
        {stamp_index=tonumber(dynamic[0].stamp_index)},
        {reservoir_r=tonumber(carry[0].reservoir_r),
         reservoir_g=tonumber(carry[0].reservoir_g),
         reservoir_b=tonumber(carry[0].reservoir_b),
         initialized=tonumber(carry[0].initialized)}
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
    session.cache.touched[tile.key]=true
    return {x=tile.x+r.x,y=tile.y+r.y,width=r.width,height=r.height}
end

local function union(a,b)
    if not a then return b end
    local x,y=math.min(a.x,b.x),math.min(a.y,b.y)
    local right=math.max(a.x+a.width,b.x+b.width)
    local bottom=math.max(a.y+a.height,b.y+b.height)
    return {x=x,y=y,width=right-x,height=bottom-y}
end

local function advanceState(session,x0,y0,x1,y1,color,diameter,opacity,
                            eraser,pressure0,pressure1,originalState,originalDirection,originalDynamics,originalCarry,samples)
    -- Sem tiles visiveis: avance a fase de spacing via um bitmap descartavel.
    local empty={x=-10000,y=-10000,w=1,h=1,data=session.dummy}
    if not empty.data then
        session.dummy=love.image.newImageData(1,1,"rgba8")
        empty.data=session.dummy
    end
    local _,updated,updatedDirection,updatedDynamics,updatedCarry=paintTile(session,empty,x0,y0,x1,y1,color,diameter,opacity,
        eraser,pressure0,pressure1,originalState,originalDirection,originalDynamics,originalCarry,samples)
    return updated,updatedDirection,updatedDynamics,updatedCarry
end

-- Sample the UNPAINTED source-layer pixels at exact native dab locations
-- in a two-pass query. This list is shared across every tile of this segment.
-- Reuse the existing 128px LRU tiles to avoid per-dab GPU readbacks.
local function collectPigmentSamples(session,x0,y0,x1,y1,diameter,initial)
    local state=ffi.new("InkoraStrokeState[1]")
    state[0].initialized=initial.initialized
    state[0].distance_to_next=initial.distance_to_next
    local count=ffi.new("uint32_t[1]")
    local spacing=session.settings.spacing or 0.18
    local ok=Native.library.inkora_core_dab_positions_v12(
        state,x0,y0,x1,y1,diameter,spacing,nil,0,count)
    assert(ok==1,"Motor C++ rejeitou consulta de posicoes de carimbo")
    local n=tonumber(count[0])
    local positions=ffi.new("float[?]",math.max(2,2*n))
    assert(Native.library.inkora_core_dab_positions_v12(
        state,x0,y0,x1,y1,diameter,spacing,positions,n,count)==1,
        "Motor C++ nao enumerou os carimbos")
    local bytes=ffi.new("uint8_t[?]",math.max(4,4*n))
    local cache=session.cache
    local selection=session.settings.selection
    for i=0,n-1 do
        local x=math.floor(tonumber(positions[2*i]))
        local y=math.floor(tonumber(positions[2*i+1]))
        if x>=0 and y>=0 and x<cache.width and y<cache.height
           and (not selection or (x>=selection.x0 and x<selection.x1
               and y>=selection.y0 and y<selection.y1)) then
            local tile=getTile(cache,session.canvas,
                math.floor(x/TILE_SIZE),math.floor(y/TILE_SIZE))
            local r,g,b,a=tile.data:getPixel(x-tile.x,y-tile.y)
            local offset=i*4
            bytes[offset]=math.floor(r*255+0.5)
            bytes[offset+1]=math.floor(g*255+0.5)
            bytes[offset+2]=math.floor(b*255+0.5)
            bytes[offset+3]=math.floor(a*255+0.5)
        end
    end
    metrics.pigmentSamples=metrics.pigmentSamples+n
    local packet=ffi.new("InkoraDabSamples[1]")
    packet[0].rgba=bytes
    packet[0].buffer_bytes=4*n
    packet[0].count=n
    return {packet=packet,bytes=bytes}
end

function Native.segment(session,x0,y0,x1,y1,color,diameter,opacity,eraser,pressure0,pressure1)
    if not session or not Native.available() then return false end
    local cache=session.cache
    -- Worst-case expanded bounds include the maximum scatter offset.
    local radius=math.max(0.5,diameter/2)+diameter*(session.settings.scatter or 0)*0.4+2
    local left=math.max(0,math.floor(math.min(x0,x1)-radius))
    local top=math.max(0,math.floor(math.min(y0,y1)-radius))
    local right=math.min(cache.width-1,math.ceil(math.max(x0,x1)+radius))
    local bottom=math.min(cache.height-1,math.ceil(math.max(y0,y1)+radius))
    local old=session.state[0]
    local initial={distance_to_next=old.distance_to_next,initialized=old.initialized}
    local direction=session.direction[0]
    local originalDirection={
        initialized=direction.initialized,angle_degrees=direction.angle_degrees
    }
    local originalDynamics={
        stamp_index=tonumber(session.dynamics[0].stamp_index)
    }
    -- Obtain one pigment sample from the END of the unpainted segment.
    -- Sampling before any tile update makes all tile results identical.
    local oldCarry=session.carry[0]
    local originalCarry={
        reservoir_r=tonumber(oldCarry.reservoir_r),
        reservoir_g=tonumber(oldCarry.reservoir_g),
        reservoir_b=tonumber(oldCarry.reservoir_b),
        initialized=tonumber(oldCarry.initialized),
        sample_r=0,sample_g=0,sample_b=0,sample_a=0,
    }
    local samples=nil
    if not eraser and (session.settings.pigmentPickup or 0)>0
        and (session.settings.wetness or 0)>0 then
        samples=collectPigmentSamples(session,x0,y0,x1,y1,diameter,initial)
    end
    local newCarry=nil
    local newDynamics=nil
    local newDirection=nil
    local newState=nil
    local bounds=nil
    local pixels=0

    if left<=right and top<=bottom then
        for ty=math.floor(top/TILE_SIZE),math.floor(bottom/TILE_SIZE) do
            for tx=math.floor(left/TILE_SIZE),math.floor(right/TILE_SIZE) do
                local tile=getTile(cache,session.canvas,tx,ty)
                local dirty,state,turned,changedDab,changedCarry=paintTile(session,tile,x0,y0,x1,y1,color,diameter,
                    opacity,eraser,pressure0,pressure1,initial,originalDirection,originalDynamics,originalCarry,samples)
                newState=state
                newDirection=turned
                newDynamics=changedDab
                newCarry=changedCarry
                if dirty.width>0 and dirty.height>0 then
                    local updated=updateTile(session,tile,dirty)
                    bounds=union(bounds,updated)
                    pixels=pixels+dirty.width*dirty.height
                end
            end
        end
    end
    if not newState then
        newState,newDirection,newDynamics,newCarry=advanceState(session,x0,y0,x1,y1,color,diameter,opacity,
            eraser,pressure0,pressure1,initial,originalDirection,originalDynamics,originalCarry,samples)
    end
    session.state[0].distance_to_next=newState.distance_to_next
    session.state[0].initialized=newState.initialized
    session.direction[0].angle_degrees=newDirection.angle_degrees
    session.direction[0].initialized=newDirection.initialized
    session.dynamics[0].stamp_index=newDynamics.stamp_index
    session.carry[0].reservoir_r=newCarry.reservoir_r
    session.carry[0].reservoir_g=newCarry.reservoir_g
    session.carry[0].reservoir_b=newCarry.reservoir_b
    session.carry[0].initialized=newCarry.initialized

    Native.lastUpload=bounds or {x=0,y=0,width=0,height=0}
    Native.lastUpload.pixels=pixels
    return true
end

-- Composes a straight-alpha RGBA layer onto output using the native engine.
-- Both ImageData instances remain owned by Lua during the call.
local function imagePointer(image,w,h)
    if not image then return nil end
    assert(image:getWidth()==w and image:getHeight()==h,
        "Dimensao de mascara ou camada-base invalida")
    assert(image:getFormat()=="rgba8","Camada auxiliar exige RGBA8")
    return ffi.cast("const uint8_t*",image:getFFIPointer())
end

-- options.mask, options.clip, options.clipMask are optional ImageData RGBA8.
-- Mask coverage lives in the RED channel; clip uses the base layer ALPHA.
-- Legacy calls without options retain precisely their old ABI behaviour.
function Native.blendLayer(output,source,opacity,mode,options)
    assert(Native.available(),"Compositor C++ nao encontrado: "..tostring(Native.error))
    local w,h=output:getDimensions()
    assert(source:getWidth()==w and source:getHeight()==h,"Dimensao de camada invalida")
    assert(output:getFormat()=="rgba8" and source:getFormat()=="rgba8",
        "Compositor requer RGBA8")
    local dst=ffi.cast("uint8_t*",output:getFFIPointer())
    local src=ffi.cast("const uint8_t*",source:getFFIPointer())
    local ok
    if options then
        local mask,clip,clipMask=options.mask,options.clip,options.clipMask
        local effects=ffi.new("InkoraLayerEffects[1]")
        local e=effects[0]
        e.mask_rgba=imagePointer(mask,w,h)
        e.mask_bytes=mask and mask:getSize() or 0
        e.mask_stride=mask and w*4 or 0
        e.clipping_enabled=options.clipping and 1 or 0
        e.clip_rgba=imagePointer(clip,w,h)
        e.clip_bytes=clip and clip:getSize() or 0
        e.clip_stride=clip and w*4 or 0
        e.clip_opacity=options.clipOpacity or 0
        e.clip_mask_rgba=imagePointer(clipMask,w,h)
        e.clip_mask_bytes=clipMask and clipMask:getSize() or 0
        e.clip_mask_stride=clipMask and w*4 or 0
        ok=Native.library.inkora_core_blend_layer_v7(
            dst,output:getSize(),w*4,src,source:getSize(),w*4,
            w,h,opacity,mode,effects)
    else
        ok=Native.library.inkora_core_blend_layer(
            dst,output:getSize(),w*4,src,source:getSize(),w*4,
            w,h,opacity,mode)
    end
    if ok~=1 then error("Compositor C++ recusou camada") end
    return output
end

return Native
