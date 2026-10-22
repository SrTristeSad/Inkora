-- Ponte LuaJIT FFI -> motor C++ do Inkora.
-- Se o modulo nativo nao existe (ex.: abrir apenas o codigo-fonte),
-- devolve indisponivel; o Brush segue com o prototipo Lua antigo.
local Native={library=nil, error=nil, attempted=false}
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
    int32_t inkora_core_api_version(void);
    int32_t inkora_core_stroke(const InkoraStroke *stroke);
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
            local versionOK,version=pcall(function() return tonumber(lib.inkora_core_api_version()) end)
            if versionOK and version==1 then
                Native.library=lib
                Native.path=p
                Native.error=nil
                return true
            end
            Native.error="Motor nativo encontrado, mas API incompativel"
        end
    end
    Native.error=Native.error or "inkora_core nao encontrado (modo Lua)"
    return false
end

-- Uma unica leitura de GPU por traco, sem atualizar o canvas no meio do stroke
-- exceto por uploads para visualizacao. A fase futura fara upload apenas das tiles sujas.
function Native.beginStroke(canvas)
    if not Native.available() then return nil end
    local data=canvas:newImageData()
    if data:getFormat()~="rgba8" then
        error("Ponte nativa exige ImageData rgba8")
    end
    local texture=love.graphics.newImage(data)
    texture:setFilter("nearest","nearest")
    return {canvas=canvas,data=data,texture=texture}
end

function Native.segment(session,x0,y0,x1,y1,color,diameter,opacity,eraser,pressure0,pressure1)
    if not session or not Native.available() then return false end
    local w,h=session.data:getDimensions()
    local stroke=ffi.new("InkoraStroke[1]")
    local s=stroke[0]
    s.pixels=ffi.cast("uint8_t*",session.data:getFFIPointer())
    s.width=w
    s.height=h
    s.stride=w*4
    s.buffer_bytes=session.data:getSize()
    s.x0=x0; s.y0=y0; s.x1=x1; s.y1=y1
    s.diameter=diameter; s.hardness=0.82; s.opacity=opacity; s.spacing=0.18
    s.r=color[1]; s.g=color[2]; s.b=color[3]
    s.pressure0=pressure0 or 1; s.pressure1=pressure1 or 1
    s.eraser=eraser and 1 or 0
    if Native.library.inkora_core_stroke(stroke)~=1 then
        error("Motor Inkora C++ recusou segmento")
    end
    session.texture:replacePixels(session.data)
    love.graphics.push("all")
    love.graphics.setCanvas(session.canvas)
    love.graphics.setBlendMode("replace","premultiplied")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(session.texture)
    love.graphics.pop()
    return true
end

return Native
