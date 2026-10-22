-- Inkora brush previews are rasterized by the same C++ pipeline as the
-- actual canvas. Only the most recent live preview is retained.
local Brush=require("src.brush")
local Native=require("src.native")
local Stabilizer=require("src.stabilizer")
local Preview={}
local cards={}
local live=nil
local dryComparison=nil
local localWetComparison=nil
local WIDTH,HEIGHT=168,44

local function signature(style,mask,ink)
    -- String keys include EVERY parameter that affects rendered pixels.
    return table.concat({
        tostring(style.id or "live"), tostring(style.tip),
        tostring(style.size),tostring(style.hardness),
        tostring(style.spacing),tostring(style.opacity),
        tostring(style.flow),tostring(style.pressureOpacity),
        tostring(style.stabilization or 0),
        tostring(style.angle or 0),tostring(style.followPath or false),
        tostring(style.texture or 0),tostring(style.scatter or 0),
        tostring(style.sizeJitter or 0),
        tostring(style.wetness or 0),tostring(style.pigmentLoad or 1),
        tostring(style.pigmentPickup or 0),
        tostring(style.pigmentRetention or 0),
        tostring(style.demoWet or false),
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
    if style.demoWet then
        -- A colored underpainting makes wet blending visibly distinct
        -- from ordinary dry compositing; all pixels come from C++ strokes.
        for i=1,2 do
            local coat=Brush.beginStroke(canvas,{
                hardness=1,spacing=0.12,tip=0,flow=1,
                pressureOpacity=0,wetness=0,pigmentLoad=1,
            })
            local under=i==1 and {0.94,0.28,0.34} or {0.23,0.40,0.96}
            local ax=i==1 and 8 or 84
            Brush.segment(canvas,ax,22,ax+76,22,under,
                36,1,false,coat,1,1)
        end
    end
    local session=Brush.beginStroke(canvas,{
        hardness=style.hardness,spacing=style.spacing,
        tip=style.tip,aspect=0.3,angle=style.angle or 0,
        followPath=style.followPath or false,
        grain=0.85,seed=239,
        mask=style.tip==3 and mask or nil,
        flow=style.flow,pressureOpacity=style.pressureOpacity,
        texture=style.texture or 0,scatter=style.scatter or 0,
        sizeJitter=style.sizeJitter or 0,
        wetness=style.wetness or 0,pigmentLoad=style.pigmentLoad or 1,
        pigmentPickup=style.pigmentPickup or 0,
        pigmentRetention=style.pigmentRetention or 0,
    })
    assert(session,"Motor C++ nao criou a previa de pincel")
    -- A scaled simulation makes small and big tips identifiable without
    -- clipping most of the preview on a 44px-tall thumbnail.
    local diameter=math.min(25,math.max(2,style.size*0.58))
    local points=45
    local x0,y0=9,24
    local smoother=Stabilizer.new(x0,y0,style.stabilization or 0)
    local pressure0=0.5
    Brush.segment(canvas,x0,y0,x0,y0,ink,diameter,
        style.opacity,false,session,pressure0,pressure0)
    for i=1,points do
        local t=i/points
        local targetX=9+148*t
        -- The high-frequency movement is deliberate: increasing the
        -- stabilizer strength smooths it in this native C++ preview.
        local targetY=22+math.sin(t*math.pi*2)*7
            +math.sin(t*math.pi*24)*3
        local pressure=0.45+0.5*math.sin(t*math.pi)^2
        local x,y=smoother:push(targetX,targetY,1/90)
        Brush.segment(canvas,x0,y0,x,y,ink,diameter,
            style.opacity,false,session,pressure0,pressure)
        x0,y0,pressure0=x,y,pressure
    end
    local tail=smoother:finishPath(157,22,diameter)
    for _,point in ipairs(tail) do
        Brush.segment(canvas,x0,y0,point[1],point[2],ink,diameter,
            style.opacity,false,session,pressure0,pressure0)
        x0,y0=point[1],point[2]
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
local function liveStyle(app,demo)
    return {
        id="live",size=app.brushSize,hardness=app.brushHardness,
        spacing=app.brushSpacing,opacity=app.brushOpacity,
        flow=app.brushFlow,pressureOpacity=app.pressureOpacity,
        stabilization=app.stabilization,
        tip=app.brushTip,angle=app.brushAngle,
        followPath=app.brushFollowPath,
        texture=app.brushTexture,scatter=app.brushScatter,
        sizeJitter=app.brushSizeJitter,
        wetness=app.brushWetness,pigmentLoad=app.brushPigmentLoad,
        pigmentPickup=app.brushPigmentPickup,
        pigmentRetention=app.brushPigmentRetention,
        demoWet=not not demo,
    }
end

function Preview.getLive(app,demo)
    if not Native.available() then return nil end
    local style=liveStyle(app,demo)
    local mask=style.tip==3 and app.tipMask or nil
    if style.tip==3 and not mask then return nil end
    local ink=app.color or {0.28,0.73,0.93}
    local key=signature(style,mask,ink)
    if live and live.key==key then return live.canvas end
    live={key=key,canvas=render(style,mask,ink)}
    return live.canvas
end

function Preview.getLocalWetComparison(app)
    if not Native.available() then return nil end
    local style=liveStyle(app,true)
    style.pigmentPickup=0
    style.pigmentRetention=0
    local mask=style.tip==3 and app.tipMask or nil
    if style.tip==3 and not mask then return nil end
    local ink=app.color or {0.28,0.73,0.93}
    local key=signature(style,mask,ink)
    if not localWetComparison or localWetComparison.key~=key then
        localWetComparison={key=key,canvas=render(style,mask,ink)}
    end
    return localWetComparison.canvas
end

function Preview.getDryComparison(app)
    if not Native.available() then return nil end
    local style=liveStyle(app,true)
    style.wetness=0
    local mask=style.tip==3 and app.tipMask or nil
    if style.tip==3 and not mask then return nil end
    local ink=app.color or {0.28,0.73,0.93}
    local key=signature(style,mask,ink)
    if not dryComparison or dryComparison.key~=key then
        dryComparison={key=key,canvas=render(style,mask,ink)}
    end
    return dryComparison.canvas
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
    dryComparison=nil
    localWetComparison=nil
end

function Preview.stats()
    local count=0
    for _ in pairs(cards) do count=count+1 end
    return {count=count,live=live and 1 or 0,width=WIDTH,height=HEIGHT}
end

return Preview
