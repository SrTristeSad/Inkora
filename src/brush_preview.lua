-- Inkora brush previews are rasterized by the same C++ pipeline as the
-- actual canvas. Only the most recent live preview is retained.
local Brush=require("src.brush")
local Native=require("src.native")
local Preview={}
local cards={}
local live=nil
local WIDTH,HEIGHT=168,44

local function signature(style,mask,ink)
    -- String keys include EVERY parameter that affects rendered pixels.
    return table.concat({
        tostring(style.id or "live"), tostring(style.tip),
        tostring(style.size),tostring(style.hardness),
        tostring(style.spacing),tostring(style.opacity),
        tostring(style.flow),tostring(style.pressureOpacity),
        mask and tostring(mask.buffer) or "nomask",
        string.format("%.4f,%.4f,%.4f",
            ink[1] or 0,ink[2] or 0,ink[3] or 0)
    },"|")
end

local function render(style,mask,ink)
    local canvas=love.graphics.newCanvas(WIDTH,HEIGHT,{format="rgba8"})
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0,0,0,0)
    love.graphics.pop()
    Native.registerBlank(canvas)
    local session=Brush.beginStroke(canvas,{
        hardness=style.hardness,spacing=style.spacing,
        tip=style.tip,aspect=0.3,angle=style.tip==3 and 0 or 25,
        grain=0.85,seed=239,
        mask=style.tip==3 and mask or nil,
        flow=style.flow,pressureOpacity=style.pressureOpacity,
    })
    assert(session,"Motor C++ nao criou a previa de pincel")
    -- A scaled simulation makes small and big tips identifiable without
    -- clipping most of the preview on a 44px-tall thumbnail.
    local diameter=math.min(25,math.max(2,style.size*0.58))
    local points=23
    local x0,y0=9,24
    local pressure0=0.5
    Brush.segment(canvas,x0,y0,x0,y0,ink,diameter,
        style.opacity,false,session,pressure0,pressure0)
    for i=1,points do
        local t=i/points
        local x=9+148*t
        local y=22+math.sin(t*math.pi*2)*6
        local pressure=0.45+0.5*math.sin(t*math.pi)^2
        Brush.segment(canvas,x0,y0,x,y,ink,diameter,
            style.opacity,false,session,pressure0,pressure)
        x0,y0,pressure0=x,y,pressure
    end
    return canvas
end

-- Cached samples for saved brush presets.
function Preview.get(style,mask)
    if not style or (style.tip==3 and not mask) then return nil end
    if not Native.available() then return nil end
    local ink={0.28,0.73,0.93}
    local key=signature(style,mask,ink)
    if not cards[key] then
        cards[key]=render(style,mask,ink)
    end
    return cards[key]
end

-- The active editor settings, not the original preset values, are rendered.
-- Only one dynamic image is held at a time: sliding controls does not
-- continually allocate new retained canvases.
function Preview.getLive(app)
    if not Native.available() then return nil end
    local style={
        id="live",size=app.brushSize,hardness=app.brushHardness,
        spacing=app.brushSpacing,opacity=app.brushOpacity,
        flow=app.brushFlow,pressureOpacity=app.pressureOpacity,
        tip=app.brushTip,
    }
    local mask=style.tip==3 and app.tipMask or nil
    if style.tip==3 and not mask then return nil end
    local ink=app.color or {0.28,0.73,0.93}
    local key=signature(style,mask,ink)
    if live and live.key==key then return live.canvas end
    live={key=key,canvas=render(style,mask,ink)}
    return live.canvas
end

function Preview.invalidate(id)
    if id then
        for key in pairs(cards) do
            if key:sub(1,#id+1)==id.."|" then cards[key]=nil end
        end
    else
        cards={}
    end
    live=nil
end

function Preview.stats()
    local count=0
    for _ in pairs(cards) do count=count+1 end
    return {count=count,live=live and 1 or 0,width=WIDTH,height=HEIGHT}
end

return Preview
