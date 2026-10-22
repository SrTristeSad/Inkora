local Brush = {}

-- Rasterização inicial sem dependências nativas. O motor profissional
-- e a pressão da mesa digitalizadora serão módulos independentes.
function Brush.segment(canvas, x1, y1, x2, y2, color, diameter, opacity, eraser)
    local radius = math.max(0.5, diameter / 2)
    local distance = math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
    local spacing = math.max(0.65, radius * 0.32)
    local steps = math.max(1, math.ceil(distance / spacing))
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    if eraser then
        love.graphics.setBlendMode("replace", "premultiplied")
        love.graphics.setColor(0, 0, 0, 0)
    else
        love.graphics.setBlendMode("alpha", "alphamultiply")
        love.graphics.setColor(color[1], color[2], color[3], opacity)
    end
    for i = 0, steps do
        local t = i / steps
        love.graphics.circle("fill",
            x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, radius)
    end
    love.graphics.pop()
end

return Brush
