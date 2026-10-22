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
return Preview
