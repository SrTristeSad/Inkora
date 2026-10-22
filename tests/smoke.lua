package.path = "./?.lua;./?/init.lua;" .. package.path
local p = require("src.palette")
assert(type(p) == "table" and #p == 18, "Paleta incompleta")
for _, color in ipairs(p) do
    assert(#color == 3, "Cor RGB invalida")
    for i=1,3 do assert(color[i]>=0 and color[i]<=1, "Canal RGB fora de faixa") end
end
local brush = require("src.brush")
local document = require("src.document")
assert(type(brush.segment)=="function" and type(document.new)=="function", "Modulos indisponiveis")
print("Inkora: smoke test OK")
