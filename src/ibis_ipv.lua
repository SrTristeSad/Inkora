-- ibisPaint .ipv interoperability: independent, read-only container inspector.
--
-- Public technical reference (MIT-licensed research, no source copied):
-- https://github.com/fapotaa/ipv-format/blob/main/docs/FORMAT.md
-- The observed format is an append-only record log written by Android 14.0.11.
-- We only return the most recent complete flattened PNG snapshot.
-- Brush, native layer structure, text editability and Windows 14.1.2 parity
-- are NOT supported or claimed.
local IPV={}
local PNG=string.char(137).."PNG\r\n"..string.char(26).."\n"
local MAX_FILE=256*1024*1024
local MAX_IMAGE=64*1024*1024
local MAX_RECORDS=250000
local MAX_CANVAS=32768
local U32=4294967296

local function u16(bytes,p)
    local a,b=bytes:byte(p,p+1)
    assert(b,"IPV: campo de 16 bits truncado")
    return a*256+b
end

local function u32(bytes,p)
    local a,b,c,d=bytes:byte(p,p+3)
    assert(d,"IPV: campo de 32 bits truncado")
    return ((a*256+b)*256+c)*256+d
end

-- All public fields are big-endian. The trailer is the two's-complement
-- negative length of the 8-byte header plus payload.
function IPV.inspect(data)
    assert(type(data)=="string","IPV: bytes invalidos")
    assert(#data>=12,"IPV: cabecalho incompleto")
    assert(#data<=MAX_FILE,"IPV: arquivo excede 256 MiB")
    local pos=1
    local count=0
    local width,height=nil,nil
    local png=nil
    local snapshots=0
    local sawHeader=false
    while pos<=#data do
        count=count+1
        assert(count<=MAX_RECORDS,"IPV: registros demais")
        assert(pos+11<=#data,"IPV: registro incompleto")
        local major=u16(data,pos)
        local sub=u16(data,pos+2)
        local length=u32(data,pos+4)
        assert(length<2147483640,"IPV: comprimento invalido")
        local footer=pos+8+length
        assert(footer+3<=#data,"IPV: payload truncado")
        assert(u32(data,footer)==(U32-(length+8))%U32,
            "IPV: sentinela invalida")
        local payload=pos+8
        if major==0x0100 and sub==0x0100 then
            assert(length>=16,"IPV: cabecalho de canvas truncado")
            local w,h=u32(data,payload+8),u32(data,payload+12)
            assert(w>0 and h>0 and w<=MAX_CANVAS and h<=MAX_CANVAS,
                "IPV: dimensoes invalidas")
            width,height=w,h
            sawHeader=true
        elseif major==0x0100 and sub==0x0500 then
            assert(length>=22,"IPV: snapshot truncado")
            local layer=u32(data,payload+8)
            local flags=u32(data,payload+12)
            local imageLength=u32(data,payload+18)
            local blob=payload+22
            if layer==0xFFFFFFFF and flags==0 then
                assert(imageLength>=24 and imageLength<=MAX_IMAGE,
                    "IPV: tamanho PNG invalido")
                assert(imageLength<=length-22,"IPV: PNG truncado")
                assert(data:sub(blob,blob+7)==PNG,
                    "IPV: snapshot composto nao e PNG")
                assert(data:sub(blob+12,blob+15)=="IHDR",
                    "IPV: PNG sem cabecalho IHDR")
                -- PNG dimensions are in IHDR, immediately after the chunk type.
                local iw,ih=u32(data,blob+16),u32(data,blob+20)
                assert(iw>0 and ih>0 and iw<=MAX_CANVAS and ih<=MAX_CANVAS,
                    "IPV: dimensoes PNG invalidas")
                if width and height then
                    assert(iw==width and ih==height,
                        "IPV: dimensoes da imagem divergem do canvas")
                end
                png=data:sub(blob,blob+imageLength-1)
                snapshots=snapshots+1
            end
        end
        pos=footer+4
    end
    assert(sawHeader,"IPV: nao foi encontrado cabecalho 0100/0100")
    assert(png,"IPV: sem snapshot PNG composto reconhecido")
    assert(width and height,"IPV: canvas ausente")
    return {
        width=width,height=height,png=png,
        snapshots=snapshots,records=count,flattened=true,
    }
end

-- Disallow additional operations on the original IPV. A caller must
-- explicitly create a NEW Inkora document, preserving the source file.
function IPV.readFile(file)
    assert(file and type(file.read)=="function","IPV: arquivo invalido")
    if file.getSize then
        local size=file:getSize()
        if size then assert(size<=MAX_FILE,"IPV: arquivo excede 256 MiB") end
    end
    file:open("r")
    local ok,bytes=pcall(function()return file:read()end)
    file:close()
    assert(ok and type(bytes)=="string","IPV: nao foi possivel ler arquivo")
    return IPV.inspect(bytes)
end

return IPV
