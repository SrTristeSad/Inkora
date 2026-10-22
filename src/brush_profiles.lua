-- Saved, editable Inkora brush presets (separate from factory defaults).
-- Tab-separated numeric values; invalid or unknown values are ignored.
local Presets=require("src.presets")
local Profiles={}
local FILE="brush-profiles-v1.txt"
local FIELDS={
    {"size",1,120,1},
    {"hardness",0,1},
    {"spacing",0.03,0.5},
    {"opacity",0.03,1},
    {"flow",0.01,1},
    {"stabilization",0,1},
    {"tip",0,3,1},
    {"pressureOpacity",0,1},
}

local function checkValue(raw,field)
    local n=tonumber(raw)
    if not n or n~=n or n==math.huge or n==-math.huge then return nil end
    if n<field[2] or n>field[3] then return nil end
    if field[4]==1 and n%1~=0 then return nil end
    return n
end

function Profiles.capture(app)
    return {
        size=app.brushSize,hardness=app.brushHardness,
        spacing=app.brushSpacing,opacity=app.brushOpacity,
        flow=app.brushFlow,stabilization=app.stabilization,
        tip=app.brushTip,pressureOpacity=app.pressureOpacity,
    }
end

function Profiles.merge(defaults,saved)
    local result={}
    for k,v in pairs(defaults) do result[k]=v end
    if saved then
        for _,field in ipairs(FIELDS) do
            local value=checkValue(saved[field[1]],field)
            if value then result[field[1]]=value end
        end
    end
    return result
end

function Profiles.apply(app,style)
    app.brushSize=style.size
    app.brushHardness=style.hardness
    app.brushSpacing=style.spacing
    app.brushOpacity=style.opacity
    app.brushFlow=style.flow
    app.stabilization=style.stabilization
    app.brushTip=style.tip
    app.pressureOpacity=style.pressureOpacity
end

function Profiles.read()
    local out={}
    local bytes=love.filesystem.read(FILE)
    if not bytes then return out end
    for line in bytes:gmatch("[^\r\n]+") do
        local fields={}
        for entry in (line.."\t"):gmatch("(.-)\t") do
            fields[#fields+1]=entry
        end
        local id=fields[1]
        if id and Presets.find(id) and #fields==#FIELDS+1 then
            local profile={}
            local valid=true
            for i,field in ipairs(FIELDS) do
                local n=checkValue(fields[i+1],field)
                if not n then valid=false;break end
                profile[field[1]]=n
            end
            if valid then out[id]=profile end
        end
    end
    return out
end

function Profiles.write(profiles)
    local lines={}
    for _,preset in ipairs(Presets) do
        local data=profiles[preset.id]
        if data then
            local fields={preset.id}
            for _,field in ipairs(FIELDS) do
                local n=checkValue(data[field[1]],field)
                if not n then return false,"Parametro invalido: "..field[1] end
                fields[#fields+1]=tostring(n)
            end
            lines[#lines+1]=table.concat(fields,"\t")
        end
    end
    return love.filesystem.write(FILE,table.concat(lines,"\n"))
end

return Profiles
