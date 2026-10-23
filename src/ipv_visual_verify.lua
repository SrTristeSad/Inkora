-- Independent, bounded visual check for ibisPaint RPNG imports.
-- This is NOT a reverse-engineered importer for blend/visibility metadata:
-- it tests whether straight-alpha Normal layers reproduce the flattened PNG.
local Verify={}

local function samplePoints(width,height,rasters)
    local points,seen={},{}
    local function add(x,y)
        x=math.floor(x)
        y=math.floor(y)
        if x<0 or y<0 or x>=width or y>=height then return end
        local key=y*width+x
        if seen[key] then return end
        seen[key]=true
        points[#points+1]={x,y}
    end
    if width*height<=4096 then
        for y=0,height-1 do
            for x=0,width-1 do add(x,y) end
        end
    else
        -- Deterministic 32x32 grid plus samples inside EVERY raster bound.
        -- A small stroke outside the grid may still be missed.
        local gw,gh=math.min(32,width),math.min(32,height)
        for yi=0,gh-1 do
            for xi=0,gw-1 do
                add(math.floor((xi+0.5)*width/gw),
                    math.floor((yi+0.5)*height/gh))
            end
        end
        for _,r in ipairs(rasters) do
            local img=r.imageData
            if img then
                local w,h=img:getDimensions()
                local gx=math.max(1,math.min(w,12))
                local gy=math.max(1,math.min(h,12))
                for yi=0,gy-1 do
                    for xi=0,gx-1 do
                        add(r.x+math.floor((xi+0.5)*w/gx),
                            r.y+math.floor((yi+0.5)*h/gy))
                    end
                end
                add(r.x,r.y)
                add(r.x+w-1,r.y+h-1)
            end
        end
    end
    return points
end

local function evaluate(rasters,flat,points,reversed)
    local maxError,totalError,observed=0,0,0
    local opaqueOrVisible=0
    for _,pos in ipairs(points) do
        local x,y=pos[1],pos[2]
        local pr,pg,pb,pa=0,0,0,0
        for n=1,#rasters do
            local item=rasters[reversed and (#rasters-n+1) or n]
            local img=item.imageData
            if img then
                local px,py=x-item.x,y-item.y
                local w,h=img:getDimensions()
                if px>=0 and py>=0 and px<w and py<h then
                    local r,g,b,a=img:getPixel(px,py)
                    local remain=1-a
                    -- Premultiplied accumulation, input image pixels straight.
                    pr=r*a+pr*remain
                    pg=g*a+pg*remain
                    pb=b*a+pb*remain
                    pa=a+pa*remain
                end
            end
        end
        local r,g,b,a=flat:getPixel(x,y)
        local dr=math.abs(pr-r*a)
        local dg=math.abs(pg-g*a)
        local db=math.abs(pb-b*a)
        local da=math.abs(pa-a)
        local deviation=math.max(dr,dg,db,da)
        if deviation>maxError then maxError=deviation end
        totalError=totalError+dr+dg+db+da
        observed=observed+1
        if a>1/255 or pa>1/255 then opaqueOrVisible=opaqueOrVisible+1 end
    end
    local tolerance=4/255
    return {
        direction=reversed and "reverse" or "normal",
        checked=observed,
        informative=opaqueOrVisible,
        maxError=maxError,
        meanError=totalError/(math.max(1,observed)*4),
        -- A blank sampled region does not prove that sparse layers match.
        matches=maxError<=tolerance and opaqueOrVisible>0,
    }
end

-- Takes an already decoded reference ImageData, to avoid a second PNG decode.
-- Candidate order starts bottom-to-top, like Inkora's layer array.
-- Only reverse if the evidence is clearly better and actually matches.
function Verify.assess(rasters,flat)
    assert(type(rasters)=="table" and #rasters>=1,
        "IPV: nenhuma camada para verificacao")
    local width,height=flat:getDimensions()
    assert(width>0 and height>0 and width<=4096 and height<=4096,
        "IPV: tamanho da referencia fora do limite")
    local points=samplePoints(width,height,rasters)
    local normal=evaluate(rasters,flat,points,false)
    if normal.matches then
        normal.status="match"
        return normal
    end
    if #rasters>1 then
        local reverse=evaluate(rasters,flat,points,true)
        if reverse.matches then
            reverse.status="reversed-match"
            return reverse
        end
        normal.alternativeError=reverse.maxError
    end
    normal.status="mismatch"
    return normal
end

return Verify
