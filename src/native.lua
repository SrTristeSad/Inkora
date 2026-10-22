-- Inkora LuaJIT FFI bridge, ABI v2.
-- Retains the old LÖVE-only brush as a fallback if the native library is absent.
-- C++ modifies one CPU-side RGBA8 buffer owned by ImageData; LÖVE receives
-- only the dirty rectangle on each mouse event, not a full-image upload.
local Native={library=nil,error=nil,attempted=false,lastUpload=nil}
local ffiOK,ffi=pcall(require,"ffi")
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
            local vok,v=pcall(function() return tonumber(lib.inkora_core_api_version()) end)
            if vok and v==2 then
                Native.library=lib
                Native.path=p
                Native.error=nil
                return true
            end
            Native.error="ABI C++ incompativel: requer versao 2"
        end
    end
    Native.error=Native.error or "inkora_core nao encontrado (modo Lua)"
    return false
end

function Native.beginStroke(canvas, settings)
    if not Native.available() then return nil end
    local data=canvas:newImageData()
    if data:getFormat()~="rgba8" then
        error("Ponte nativa exige ImageData rgba8")
    end
    local texture=love.graphics.newImage(data)
    texture:setFilter("nearest","nearest")
    return {
        canvas=canvas, data=data, texture=texture,
        state=ffi.new("InkoraStrokeState[1]"),
        settings=settings or {},
    }
end

local function uploadDirty(session,x,y,w,h)
    if w<=0 or h<=0 then
        Native.lastUpload={x=0,y=0,width=0,height=0,pixels=0}
        return
    end
    -- LÖVE ImageData:paste copies raw RGBA without blending.
    local tile=love.image.newImageData(w,h,"rgba8")
    tile:paste(session.data,0,0,x,y,w,h)
    -- Subrectangle upload to the existing texture.
    session.texture:replacePixels(tile,1,1,x,y)
    local tw,th=session.data:getDimensions()
    local quad=love.graphics.newQuad(x,y,w,h,tw,th)
    love.graphics.push("all")
    love.graphics.setCanvas(session.canvas)
    love.graphics.setBlendMode("replace","premultiplied")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(session.texture,quad,x,y)
    love.graphics.pop()
    Native.lastUpload={x=x,y=y,width=w,height=h,pixels=w*h}
end

function Native.segment(session,x0,y0,x1,y1,color,diameter,opacity,eraser,pressure0,pressure1)
    if not session or not Native.available() then return false end
    local w,h=session.data:getDimensions()
    local stroke=ffi.new("InkoraStroke[1]")
    local s=stroke[0]
    s.pixels=ffi.cast("uint8_t*",session.data:getFFIPointer())
    s.width=w;s.height=h;s.stride=w*4;s.buffer_bytes=session.data:getSize()
    s.x0=x0;s.y0=y0;s.x1=x1;s.y1=y1
    s.diameter=diameter
    s.hardness=session.settings.hardness or 0.82
    s.opacity=opacity
    s.spacing=session.settings.spacing or 0.18
    s.r=color[1];s.g=color[2];s.b=color[3]
    s.pressure0=pressure0 or 1;s.pressure1=pressure1 or 1
    s.eraser=eraser and 1 or 0
    local dirty=ffi.new("InkoraRect[1]")
    if Native.library.inkora_core_stroke_v2(stroke,session.state,dirty)~=1 then
        error("Motor C++ recusou segmento")
    end
    local r=dirty[0]
    uploadDirty(session,r.x,r.y,r.width,r.height)
    return true
end

return Native
