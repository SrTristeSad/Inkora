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

-- A raster layer's RPNG stores coverage runs in bottom-up rectangle order.
-- The embedded PNG has the packed rows flipped vertically a second time.
-- This parser only accepts complete bounded data; no uncertain data is used
-- as editable raster layers (the flattened fallback remains available).
local function parseRasterHeader(blob,canvasW,canvasH)
    assert(blob:sub(1,4)=="RPNG","IPV: nao e RPNG")
    assert(#blob>=20,"IPV: RPNG truncado")
    local version=u32(blob,5)
    assert(version==45,"IPV: versao RPNG desconhecida")
    if #blob<=49 then
        return {empty=true}
    end
    assert(#blob>=61,"IPV: cabecalho RPNG truncado")
    local w,h,x,y=u32(blob,22),u32(blob,26),u32(blob,30),u32(blob,34)
    local pw,ph,pad=u32(blob,38),u32(blob,42),u32(blob,46)
    local spans=u32(blob,54)
    if w==0 or h==0 then return {empty=true} end
    assert(w<=canvasW and h<=canvasH and x<=canvasW-w and y<=canvasH-h,
        "IPV: retangulo RPNG fora do canvas")
    assert(w*h<=4096*4096,"IPV: camada RPNG grande demais")
    assert(pw>0 and ph>0 and pw*ph<=4096*4096,
        "IPV: dimensoes PNG RPNG invalidas")
    assert(pad<=pw*ph,"IPV: preenchimento RPNG invalido")
    assert(spans>0 and spans%2==0 and spans<=w*h*4+12,
        "IPV: spans RPNG invalidos")
    local first=58
    local last=first+spans-1
    assert(last+4<=#blob,"IPV: tabela RPNG truncada")
    local pngLength=u32(blob,last+1)
    assert(pngLength>=24 and pngLength<=MAX_IMAGE and
        last+4+pngLength<=#blob,"IPV: PNG da camada RPNG truncado")
    local png=blob:sub(last+5,last+4+pngLength)
    assert(png:sub(1,8)==PNG and png:sub(13,16)=="IHDR",
        "IPV: assinatura PNG RPNG invalida")
    assert(u32(png,17)==pw and u32(png,21)==ph,
        "IPV: dimensoes do PNG RPNG divergentes")
    local runEnds={}
    local cursor,covered=0,false
    local painted=0
    for p=first,last,2 do
        local count=u16(blob,p)
        assert(cursor+count<=w*h,"IPV: mascara RPNG ultrapassa retangulo")
        if covered and count>0 then
            painted=painted+count
            runEnds[#runEnds+1]={offset=cursor,length=count}
        end
        cursor=cursor+count
        covered=not covered
    end
    assert(cursor==w*h,"IPV: mascara RPNG incompleta")
    assert(painted+pad==pw*ph,
        "IPV: mascara e preenchimento RPNG inconsistentes")
    return {
        width=w,height=h,x=x,screenY=canvasH-y-h,
        pw=pw,ph=ph,png=png,spans=runEnds,covered=painted,
    }
end


-- The public IPV research describes a 0300/0600 layer-set operation.
-- Its first two nested 0300/0603 groups contain IDs before and after
-- the edit. Parsing is intentionally conservative: unknown arrangements
-- do not alter the existing ID-based fallback.
local function readLayerIdGroup(bytes,pos,last)
    if pos+3>last then return nil end
    local count=u32(bytes,pos)
    if count<1 or count>64 then return nil end
    local ids,seen={},{}
    local ended=false
    pos=pos+4
    for index=1,count do
        if pos+15>last or
            u16(bytes,pos)~=0x0300 or
            u16(bytes,pos+2)~=0x0603 or
            u32(bytes,pos+4)~=4 or
            u32(bytes,pos+12)~=U32-12 then
            return nil
        end
        local id=u32(bytes,pos+8)
        if id==0xFFFFFFFF then
            if index~=count then return nil end
            ended=true
        else
            if seen[id] or id>65535 then return nil end
            seen[id]=true
            ids[#ids+1]=id
        end
        pos=pos+16
    end
    if not ended then return nil end
    return ids,pos
end

local function readLayerSetAfter(bytes,start,length)
    if length<16 then return nil end
    local first=start+12
    local last=start+length-1
    local scanEnd=math.min(last-15,first+4096)
    local pos=first
    local groups=0
    while pos<=scanEnd do
        local ids,nextPos=readLayerIdGroup(bytes,pos,last)
        if ids then
            groups=groups+1
            if groups==2 then return ids end
            pos=nextPos
        else
            -- Scalars between groups are 32-bit. Never search inside a
            -- nested group or accept an unvalidated record as evidence.
            pos=pos+4
        end
    end
    return nil
end

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
    local latest={}
    local layerSnapshots=0
    local unrecognizedLayers=false
    local layerSet=nil
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
        elseif major==0x0300 and sub==0x0600 then
            -- Only the latest layer-set operation describes the final order.
            layerSet=readLayerSetAfter(data,payload,length)
        elseif major==0x0100 and sub==0x0500 then
            assert(length>=22,"IPV: snapshot truncado")
            local layer=u32(data,payload+8)
            local flags=u32(data,payload+12)
            local imageLength=u32(data,payload+18)
            local blobStart=payload+22
            assert(imageLength<=length-22,
                "IPV: comprimento de snapshot invalido")
            if layer==0xFFFFFFFF and flags==0 then
                assert(imageLength>=24 and imageLength<=MAX_IMAGE,
                    "IPV: tamanho PNG invalido")
                assert(data:sub(blobStart,blobStart+7)==PNG,
                    "IPV: snapshot composto nao e PNG")
                assert(data:sub(blobStart+12,blobStart+15)=="IHDR",
                    "IPV: PNG sem cabecalho IHDR")
                local iw,ih=u32(data,blobStart+16),u32(data,blobStart+20)
                assert(iw>0 and ih>0 and iw<=MAX_CANVAS and ih<=MAX_CANVAS,
                    "IPV: dimensoes PNG invalidas")
                png=data:sub(blobStart,blobStart+imageLength-1)
                snapshots=snapshots+1
            elseif layer~=0xFFFFFFFF and layer<=65535 then
                -- Keep only the latest snapshot per layer id.
                layerSnapshots=layerSnapshots+1
                if flags==1 and imageLength>=20 and imageLength<=MAX_IMAGE
                    and data:sub(blobStart,blobStart+3)=="RPNG" then
                    latest[layer]=data:sub(blobStart,blobStart+imageLength-1)
                else
                    latest[layer]=false
                end
            end
        end
        pos=footer+4
    end
    assert(sawHeader,"IPV: nao foi encontrado cabecalho 0100/0100")
    assert(png,"IPV: sem snapshot PNG composto reconhecido")
    assert(width and height,"IPV: canvas ausente")
    local iw,ih=u32(png,17),u32(png,21)
    assert(iw==width and ih==height,
        "IPV: dimensoes da imagem divergem do canvas")
    local layers={}
    if layerSet then
        -- A removed layer may still have a historical snapshot. Use the
        -- latest explicit "after" set instead of resurrecting those layers.
        -- A missing or unsupported ACTIVE snapshot triggers flattened fallback.
        for _,id in ipairs(layerSet) do
            local blob=latest[id]
            if type(blob)=="string" then
                layers[#layers+1]={id=id,blob=blob}
            else
                unrecognizedLayers=true
            end
        end
    else
        -- Older/unknown logs keep the existing conservative ID estimate.
        for id,blob in pairs(latest) do
            if blob then layers[#layers+1]={id=id,blob=blob}
            else unrecognizedLayers=true end
        end
        table.sort(layers,function(a,b)return a.id<b.id end)
    end
    return {
        width=width,height=height,png=png,
        snapshots=snapshots,records=count,flattened=true,
        rasterLayers=layers,layerSnapshots=layerSnapshots,
        incompleteRaster=unrecognizedLayers,
        layerOrderSource=layerSet and "layer-list" or "id-estimate",
    }
end

-- Converts each RPNG into a transparent rect ImageData with pixels
-- oriented to the top-left coordinate system used by LÖVE and Inkora.
-- ImageData is created only after the whole structure validates.
function IPV.decodeRasterLayers(info)
    assert(type(info)=="table" and info.width and info.height,
        "IPV: falta inspeção de canvas")
    assert(info.width<=4096 and info.height<=4096,
        "IPV: canvas excede limite Inkora")
    assert(#info.rasterLayers>0,"IPV: nenhuma camada RPNG")
    assert(#info.rasterLayers<=15,"IPV: mais de 15 camadas RPNG")
    assert(not info.incompleteRaster,"IPV: existem camadas desconhecidas")
    local decoded={}
    for _,item in ipairs(info.rasterLayers) do
        local h=parseRasterHeader(item.blob,info.width,info.height)
        local dest
        if not h.empty then
            local source=love.image.newImageData(love.filesystem.newFileData(
                h.png,"ibis-layer.png"))
            assert(source:getWidth()==h.pw and source:getHeight()==h.ph,
                "IPV: PNG RPNG tem dimensoes incorretas")
            dest=love.image.newImageData(h.width,h.height,"rgba8")
            local index=0
            for _,span in ipairs(h.spans) do
                for cursor=span.offset,span.offset+span.length-1 do
                    local px=index%h.pw
                    local py=h.ph-1-math.floor(index/h.pw)
                    local r,g,b,a=source:getPixel(px,py)
                    local dx=cursor%h.width
                    local dy=h.height-1-math.floor(cursor/h.width)
                    dest:setPixel(dx,dy,r,g,b,a)
                    index=index+1
                end
            end
            assert(index==h.covered,"IPV: contagem raster divergente")
        end
        decoded[#decoded+1]={
            id=item.id,imageData=dest,
            x=h.x or 0,y=h.screenY or 0,
        }
    end
    return decoded
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
