-- Diagnostico SOMENTE LEITURA para arquivos .ipv locais.
-- Nao altera o documento nem exige a instalacao do ibisPaint ou Ghidra.
package.path="./?.lua;./?/init.lua;"..package.path
local IPV=require("src.ibis_ipv")
local path=arg and arg[1]
if not path or path=="--help" then
    io.write("Uso: lua tools/inspect_ipv.lua caminho/do/desenho.ipv\n")
    os.exit(path and 0 or 2)
end

local file,err=io.open(path,"rb")
if not file then
    io.stderr:write("IPV: nao foi possivel abrir arquivo: ",tostring(err),"\n")
    os.exit(1)
end
local size=file:seek("end")
if not size or size>256*1024*1024 then
    file:close()
    io.stderr:write("IPV: arquivo excede limite de 256 MiB ou nao permite medir tamanho\n")
    os.exit(1)
end
file:seek("set",0)
local bytes=file:read("*a")
file:close()
if not bytes or #bytes~=size then
    io.stderr:write("IPV: leitura incompleta\n")
    os.exit(1)
end
local ok,info=pcall(IPV.inspect,bytes)
if not ok then
    io.stderr:write("IPV: falha na inspecao: ",tostring(info),"\n")
    os.exit(1)
end

print("Inkora - diagnostico IPV (somente leitura)")
print(("Arquivo: %s"):format(path))
print(("Canvas: %d x %d px"):format(info.width,info.height))
print(("Registros: %d | snapshots compostos: %d"):format(info.records,info.snapshots))
print(("Snapshots de camada: %d | RPNG encontrados na selecao atual: %d"):format(
    info.layerSnapshots,#info.rasterLayers))
print(("Operacoes de camada 0300/0600: %d | registros de texto: %d"):format(
    info.layerListRecords,info.textRecords))
print(("Origem da ordem: %s"):format(info.layerOrderSource))
print(("Raster incompleto/nao suportado: %s"):format(
    info.incompleteRaster and "sim" or "nao"))
print("Tipos de registro:")
local kinds={}
for name in pairs(info.recordTypes) do kinds[#kinds+1]=name end
table.sort(kinds)
for _,name in ipairs(kinds) do
    print(("  %s  %d"):format(name,info.recordTypes[name]))
end
print("Observacao: resultados sao experimentais; nao comprovam compatibilidade")
print("com arquivos Windows 14.1.2 nem reconstrucao de historico, texto ou blend.")
