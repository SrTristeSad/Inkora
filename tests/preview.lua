-- CI-only illustration to expose real Inkora panels in a screenshot.
-- The sample is drawn using the native brush through LuaJIT, not stock art.
local Brush=require("src.brush")

local function curve(canvas,color,size,hardness,flow,xstart,xend,fn)
    local session=Brush.beginStroke(canvas,{
        hardness=hardness,spacing=0.09,tip=0,flow=flow,
        pressureOpacity=0.0
    })
    assert(session,"Inkora UI preview needs the real C++ painting engine")
    local n=32
    local px,py=xstart,fn(0)
    Brush.segment(canvas,px,py,px,py,color,size,1,false,session)
    for i=1,n do
        local t=i/n
        local x=xstart+(xend-xstart)*t
        local y=fn(t)
        Brush.segment(canvas,px,py,x,y,color,size,1,false,session)
        px,py=x,y
    end
end

local Preview={}
function Preview.seed(app)
    app:newDocument(900,600)
    local doc=app.doc
    doc.name="Atelie Inkora"
    doc:checkpoint()
    local base=doc.layers[1].canvas
    curve(base,{0.12,0.23,0.38},64,0.72,0.88,115,800,
        function(t) return 325+math.sin(t*6.5)*112 end)
    curve(base,{0.28,0.72,0.84},41,0.9,0.76,98,760,
        function(t) return 350+math.sin(t*6.5)*112 end)
    curve(base,{0.93,0.52,0.42},27,0.95,0.83,135,760,
        function(t) return 210+math.sin(t*8.3+1.2)*52 end)

    assert(doc:addLayer("Detalhes em nanquim"))
    local details=doc.layers[2].canvas
    curve(details,{0.22,0.27,0.37},8,1,1,140,700,
        function(t) return 505-270*t+math.sin(t*9.0)*22 end)
    curve(details,{0.95,0.73,0.39},16,0.8,0.84,210,710,
        function(t) return 120+260*t+math.cos(t*11)*18 end)
    app:choosePreset("ink")
    doc.dirty=true
    app:fitView()
    app:statusMessage("Inkora Desktop | interface e pincel nativo C++")
end
-- Show the user an actual side-by-side v8 raster difference.
-- Both strokes are drawn through the real C++ nib pipeline.
function Preview.directional(app)
    app:newDocument(900,600)
    local doc=app.doc
    doc.name="Ponta fixa X ponta direcional - motor C++ v8"
    doc:checkpoint()
    local canvas=doc.layers[1].canvas
    local function drawLoop(cx,color,follows)
        local brush=Brush.beginStroke(canvas,{
            tip=1,aspect=0.16,angle=0,followPath=follows,
            hardness=1,spacing=0.07,flow=0.88,pressureOpacity=0
        })
        assert(brush,"Native C++ v8 tip unavailable")
        local radiusX,radiusY=135,100
        local samples=100
        local lx,ly=nil,nil
        for i=0,samples do
            local t=i/samples*2*math.pi
            local x=cx+math.cos(t)*radiusX
            local y=295+math.sin(t)*radiusY
            if not lx then lx,ly=x,y end
            Brush.segment(canvas,lx,ly,x,y,color,36,0.9,false,brush)
            lx,ly=x,y
        end
    end
    drawLoop(235,{0.85,0.38,0.30},false)
    drawLoop(665,{0.22,0.50,0.84},true)
    assert(doc:addLayer("Detalhes"))
    doc.dirty=true
    app:choosePreset("marker")
    app.brushTip=1
    app.brushAngle=0
    app.brushFollowPath=true
    app:fitView()
    app:statusMessage("Esquerda: ponta fixa | Direita: ponta acompanha o traco")
end

return Preview
