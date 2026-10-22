function love.conf(t)
    t.identity = "Inkora"
    t.version = "11.5"
    t.console = false
    t.window.title = "Inkora — Editor de Pintura"
    t.window.width = 1360
    t.window.height = 820
    t.window.minwidth = 930
    t.window.minheight = 760
    t.window.resizable = true
    t.window.highdpi = true
    t.modules.physics = false
    t.modules.joystick = false
end
