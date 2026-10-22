local Brush = {}
local Native = require("src.native")

function Brush.nativeAvailable() return Native.available() end
function Brush.nativeError() return Native.error end
function Brush.beginStroke(canvas,settings) return Native.beginStroke(canvas,settings) end

local function style(color, diameter, opacity, eraser)
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineJoin("bevel")
    love.graphics.setLineWidth(math.max(1, diameter))
    if eraser then
        -- Borracha 100%: substitui o RGBA por transparente.
        love.graphics.setBlendMode("replace", "premultiplied")
        love.graphics.setColor(0, 0, 0, 0)
    else
        love.graphics.setBlendMode("alpha", "alphamultiply")
        love.graphics.setColor(color[1], color[2], color[3], opacity)
    end
end

-- Interpolacao de discos evita falhas quando o mouse se move rapidamente.
function Brush.segment(canvas, x1, y1, x2, y2, color, diameter, opacity, eraser, session, pressure0, pressure1)
    if session then
        Native.segment(session,x1,y1,x2,y2,color,diameter,opacity,eraser,pressure0,pressure1)
        return
    end
    Native.invalidate(canvas) -- Prototipo Lua alterou o canvas diretamente.
    local radius = math.max(0.5, diameter/2)
    local distance = math.sqrt((x2-x1)^2 + (y2-y1)^2)
    local steps = math.max(1, math.ceil(distance / math.max(0.75,radius*0.45)))
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    style(color,diameter,opacity,eraser)
    for i=0,steps do
        local t=i/steps
        love.graphics.circle("fill", x1+(x2-x1)*t, y1+(y2-y1)*t, radius)
    end
    love.graphics.pop()
end

local function geometry(kind,x1,y1,x2,y2)
    if kind=="line" then
        love.graphics.line(x1,y1,x2,y2)
    elseif kind=="rectangle" then
        local x,y=math.min(x1,x2), math.min(y1,y2)
        love.graphics.rectangle("line",x,y,math.abs(x2-x1),math.abs(y2-y1))
    elseif kind=="ellipse" then
        local cx,cy=(x1+x2)/2,(y1+y2)/2
        local rx,ry=math.abs(x2-x1)/2,math.abs(y2-y1)/2
        if rx<0.5 or ry<0.5 then
            love.graphics.circle("fill",cx,cy,0.5)
            return
        end
        local segments=math.max(24,math.min(180,math.ceil((rx+ry)*0.20)))
        local pts={}
        for i=0,segments do
            local angle=math.pi*2*i/segments
            pts[#pts+1]=cx+rx*math.cos(angle)
            pts[#pts+1]=cy+ry*math.sin(angle)
        end
        love.graphics.line(pts)
    end
end

function Brush.shape(canvas,kind,x1,y1,x2,y2,color,diameter,opacity)
    if canvas then Native.invalidate(canvas) end
    love.graphics.push("all")
    if canvas then love.graphics.setCanvas(canvas) end
    style(color,diameter,opacity,false)
    geometry(kind,x1,y1,x2,y2)
    love.graphics.pop()
end

return Brush
