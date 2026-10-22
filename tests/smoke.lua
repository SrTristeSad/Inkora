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

-- Time-normalized stabilization: slow hand tremor is filtered, faster
-- intended movement remains responsive. Tests are deterministic by dt.
local function trace(strength,dt,frequency)
    local filter=smoother.new(0,0,strength)
    local points={}
    local steps=math.floor(1/dt+0.5)
    for i=1,steps do
        local t=i*dt
        local tx=300*t
        local ty=50+3*math.sin(t*frequency*2*math.pi)
        local fx,fy=filter:push(tx,ty,dt)
        points[#points+1]={fx,fy}
    end
    return filter,points
end
local fast,highRate=trace(0.8,1/120,12)
local slow,lowRate=trace(0.8,1/30,12)
assert(math.abs(fast.x-slow.x)<12,
    "Estabilizador varia exageradamente por frequencia de eventos")
assert(math.abs(fast.y-slow.y)<12,
    "Estabilizador altera demais a posicao com frequencias distintas")

local flat=smoother.new(100,50,0)
for i=1,60 do
    local xx,yy=flat:push(100+i*2,50+math.sin(i)*2,1/60)
    assert(xx==100+i*2 and yy==50+math.sin(i)*2,
        "Forca zero deve retornar posicao exata")
end
local sFiltered=smoother.new(100,50,1)
local rawVariation,filteredVariation=0,0
local py,pf=50,50
for i=1,120 do
    local y=50+2.2*math.sin(i*2.6)
    local _,fy=sFiltered:push(100+i*0.2,y,1/120)
    rawVariation=rawVariation+math.abs(y-py)
    filteredVariation=filteredVariation+math.abs(fy-pf)
    py,pf=y,fy
end
assert(filteredVariation<rawVariation*0.25,
    "Filtro nao reduziu o tremor na trajetoria")
local tail=sFiltered:finishPath(150,60,10)
assert(#tail>1 and #tail<=64,"Cauda do traco nao foi amostrada")
for i,point in ipairs(tail) do
    assert(point[1]==point[1] and point[2]==point[2])
    if i>1 then assert(point[1]>=tail[i-1][1]) end
end
assert(math.abs(tail[#tail][1]-150)<1e-8 and
    math.abs(tail[#tail][2]-60)<1e-8,
    "Finalizacao nao alcançou ponteiro")
print("INKORA_ADAPTIVE_STABILIZER_OK")
-- WinTab math is platform-neutral; verify without a tablet or DLL.
local Tablet=require("src.tablet")
assert(Tablet.normalize(512,0,1024)==0.5)
assert(Tablet.normalize(700,-100,1500)==0.5)
assert(Tablet.normalize(-7,0,2048)==0)
assert(Tablet.normalize(4096,0,2048)==1)
assert(Tablet.normalize(1,1,1)==nil)
assert(Tablet.normalize(0/0,0,100)==nil)
assert(math.abs(Tablet.applyCurve(0.5,"Linear")-0.5)<0.0001)
assert(Tablet.applyCurve(0.5,"Leve")>0.5)
assert(Tablet.applyCurve(0.5,"Firme")<0.5)
Tablet._injectForTest(0.45,12)
assert(Tablet.pressure(12.08)==0.45)
assert(Tablet.pressure(12.20)==nil)
Tablet._injectForTest(0,20)
assert(Tablet.pressure(20)==nil)
Tablet.shutdown()
print("INKORA_TABLET_PRESSURE_MATH_OK")



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

-- Viewport coordinates must remain reversible under rotations, all zooms
-- and arbitrary screen offsets (pure Lua, no GPU required).
local vp=require("src.viewport")
local function near(a,b) return math.abs(a-b)<0.00001 end
for _,angle in ipairs({0,math.pi/6,math.pi/2,math.pi,5.4}) do
    for _,zoom in ipairs({0.08,0.75,1,8}) do
        for _,xy in ipairs({{0,0},{640,400},{1279.5,799.5},{210,567}}) do
            local sx,sy=vp.toScreen(xy[1],xy[2],1280,800,zoom,140,-79,angle)
            local dx,dy=vp.toDocument(sx,sy,1280,800,zoom,140,-79,angle)
            assert(near(dx,xy[1]) and near(dy,xy[2]),
                "Viewport inverso falhou em zoom/rotacao")
            local ox,oy=vp.reanchor(xy[1],xy[2],503,206,
                1280,800,zoom,angle)
            local ax,ay=vp.toScreen(xy[1],xy[2],1280,800,zoom,ox,oy,angle)
            assert(near(ax,503) and near(ay,206),
                "Zoom/giro deslocou o ponto de ancoragem")
        end
    end
end
local w,h=vp.bounds(1280,800,math.pi/2)
assert(near(w,800) and near(h,1280),"BBox de canvas rotacionado incorreto")
local presets=require("src.presets")
assert(#presets==9 and presets.find("ink").tip==0 and
    presets.find("marker").tip==1 and presets.find("watercolor").wetness>0.7)
print("INKORA_VIEWPORT_PRESETS_OK")

print("Inkora: tests de modulos OK")
