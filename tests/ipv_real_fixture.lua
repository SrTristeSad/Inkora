-- Execute com um .ipv real baixado de uma fonte autorizada.
-- Referencia: fapotaa/ipv-format, templates/general-30-text-layers.ipv
-- A amostra foi gerada no ibisPaint X Android; nao e fixture do Windows.
package.path="./?.lua;./?/init.lua;"..package.path
local fixture=assert(arg and arg[1],"informe caminho da fixture IPV real")
local f=assert(io.open(fixture,"rb"))
local data=assert(f:read("*a"))
f:close()
local ipv=require("src.ibis_ipv")
local info=ipv.inspect(data)

-- Dimensoes documentadas pelo autor da fixture (720 x 16000).
assert(info.width==720 and info.height==16000,
    ("Dimensoes inesperadas: %d x %d"):format(info.width,info.height))
assert(info.records>10 and info.snapshots>=1,
    "Parser nao encontrou sessoes/snapshot da fixture real")
assert(info.recordTypes["0100/0100"] and info.recordTypes["0100/0500"],
    "Tipos principais do container estao ausentes")
assert(info.textRecords>=1,
    "Fixture declarada como contendo textos, mas parser nao viu registros")
print(("INKORA_PUBLIC_IPV_REAL_FIXTURE_OK: %d registros; %d textos; "
    .."%d listas; %d raster RPNG; ordem=%s"):format(
        info.records,info.textRecords,info.layerListRecords,
        #info.rasterLayers,info.layerOrderSource))
-- NAO afirma que o editor reconstitui um canvas de 16000 pixels;
-- esse tamanho excede o limite de importacao editavel atual (4096).
