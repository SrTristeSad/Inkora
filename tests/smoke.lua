package.path = "./?.lua;./?/init.lua;" .. package.path
local p = require("src.palette")
assert(type(p)=="table" and #p==18, "Paleta incompleta")
for _,c in ipairs(p) do
    assert(#c==3, "Cor RGB invalida")
    for i=1,3 do assert(c[i]>=0 and c[i]<=1, "Canal RGB fora de faixa") end
end
local brush=require("src.brush")
local doc=require("src.document")
local smoother=require("src.stabilizer")
local fill=require("src.fill")
assert(type(brush.shape)=="function" and type(brush.segment)=="function")
assert(type(doc.new)=="function" and type(fill.apply)=="function")

local s=smoother.new(0,0,0)
local x,y=s:push(100,20)
assert(x==100 and y==20, "Estabilizador zero deveria ser direto")
s=smoother.new(0,0,1)
x,y=s:push(100,20)
assert(x>0 and x<100 and y>0 and y<20, "Estabilizacao nao funcionou")
x,y=s:finish(100,20)
assert(x==100 and y==20, "Final da linha deveria alcançar cursor")

local function fakeImage(lines)
    local h,w=#lines,#lines[1]
    local p={}
    for iy=0,h-1 do
        p[iy]={}
        for ix=0,w-1 do
            local c=lines[iy+1]:sub(ix+1,ix+1)
            p[iy][ix]={0,0,0,c=="#" and 1 or 0}
        end
    end
    return {
        getDimensions=function() return w,h end,
        getPixel=function(_,x,y) return unpack(p[y][x]) end,
        setPixel=function(_,x,y,r,g,b,a) p[y][x]={r,g,b,a} end,
        pixel=function(_,x,y) return p[y][x] end,
    }
end
local img=fakeImage({"......",".###..",".#.#..",".###..","......"})
assert(fill.apply(img,2,2,{1,0,0},0), "Interior deveria ser preenchido")
assert(img:pixel(2,2)[1]==1, "Interior nao ficou vermelho")
assert(img:pixel(0,0)[4]==0, "Flood fill vazou do contorno")
assert(img:pixel(1,1)[4]==1, "Contorno deveria continuar opaco")
assert(not fill.apply(img,-1,2,{0,1,0},0), "Fora da imagem deveria ser ignorado")
local img2=fakeImage({".....","....."})
assert(fill.apply(img2,0,0,{0,1,0},0), "Preencher area transparente falhou")
for y=0,1 do
    for x=0,4 do assert(img2:pixel(x,y)[2]==1, "Area aberta incompleta") end
end
assert(not fill.apply(img2,1,1,{0,1,0},0), "Mesma cor deve ser no-op")
print("Inkora: tests de modulos OK")
