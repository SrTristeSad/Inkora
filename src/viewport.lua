-- Viewport transforms used by painting, selections, mouse input and zoom.
-- All angles in radians; offsets describe unrotated canvas top-left.
-- Rotation is around the document centre and is display-only.
local Viewport={}
local sin,cos=math.sin,math.cos

function Viewport.toScreen(x,y,w,h,zoom,offsetX,offsetY,angle)
    local cx=offsetX+w*zoom/2
    local cy=offsetY+h*zoom/2
    local a=(x-w/2)*zoom
    local b=(y-h/2)*zoom
    local c,s=cos(angle),sin(angle)
    return cx+a*c-b*s,cy+a*s+b*c
end

function Viewport.toDocument(x,y,w,h,zoom,offsetX,offsetY,angle)
    assert(zoom>0,"Zoom must be positive")
    local cx=offsetX+w*zoom/2
    local cy=offsetY+h*zoom/2
    local a=x-cx
    local b=y-cy
    local c,s=cos(angle),sin(angle)
    return w/2+(a*c+b*s)/zoom,h/2+(-a*s+b*c)/zoom
end

function Viewport.bounds(w,h,angle)
    local c,s=math.abs(cos(angle)),math.abs(sin(angle))
    return w*c+h*s,w*s+h*c
end

function Viewport.reanchor(docX,docY,screenX,screenY,w,h,zoom,angle)
    local originX,originY=Viewport.toScreen(
        docX,docY,w,h,zoom,0,0,angle)
    return screenX-originX,screenY-originY
end

return Viewport
