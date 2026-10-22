-- Executado com INKORA_TEST=1 dentro do LÖVE em um display virtual.
-- Exercita caminhos reais de GPU, IO, interface e serializacao.
local Doc=require("src.document")
local Brush=require("src.brush")
local Fill=require("src.fill")
local Native=require("src.native")

local function close(a,b,tolerance)
    return math.abs(a-b) <= (tolerance or 0.18)
end

local function run(app)
    local requireNative=os.getenv("INKORA_REQUIRE_NATIVE")=="1"
    if requireNative then
        assert(Native.available(),"Motor C++ deveria estar carregado: "..tostring(Native.error))
    end
    local d=Doc.new(96,64,"Teste GPU")
    Native.resetStats()
    local stroke=Brush.beginStroke(d.layers[1].canvas)
    if requireNative then assert(stroke,"Ponte Lua/C++ nao iniciou stroke") end
    Brush.segment(d.layers[1].canvas,10.5,52.5,60.5,52.5,{0,0.2,1},7,1,false,stroke)
    local first=d.layers[1].canvas:newImageData()
    local _,_,bb,aa=first:getPixel(30,52)
    assert(bb>0.5 and aa>0.5,"Stroke Lua/C++ nao apareceu no canvas")
    if stroke then
        assert(Native.lastUpload and Native.lastUpload.pixels>0,"Nenhum pixel atualizado")
        assert(Native.lastUpload.pixels<96*64/2,
            "Transferencia completa desnecessaria (dirty rect)")
        assert(Native.lastUpload.width<=60 and Native.lastUpload.height<=12,
            "Retangulo de atualizacao maior que o segmento")
        local initial=Native.stats()
        assert(initial.readbacks==0,"Camada transparente nao precisa ser lida da GPU")
        assert(initial.zeroTiles>=1,"Bloco vazio deveria iniciar sem readback")
        local secondStroke=Brush.beginStroke(d.layers[1].canvas)
        Brush.segment(d.layers[1].canvas,15.5,49.5,32.5,49.5,
            {1,0,0},4,1,false,secondStroke)
        local repeated=Native.stats()
        assert(repeated.readbacks==0,"Pincelada seguinte releu camada vazia")
        assert(repeated.cacheHits>=1,"Tile nao foi reutilizado")
        assert(repeated.uploadedPixels<96*64,"Transferencia parcial esperada")
        print("INKORA_TILE_CACHE_OK")
        print("INKORA_DIRTY_REGION_UPLOAD_OK")
    end
    -- Mesmo com uma segunda amostra estacionaria, o motor nao pode
    -- duplicar a opacidade na mesma coordenada.
    if stroke then
        local before=d.layers[1].canvas:newImageData():getPixel(10,52)
        Brush.segment(d.layers[1].canvas,60.5,52.5,60.5,52.5,
            {0,0.2,1},7,1,false,stroke)
        local after=d.layers[1].canvas:newImageData():getPixel(10,52)
        assert(math.abs(before-after)<0.005,"Segmento nulo mudou o stroke")
        assert(Native.lastUpload.pixels==0,"Segmento vazio fez upload")
    end
    if stroke then print("INKORA_LUA_CPP_BRIDGE_OK") end
    if stroke then
        local nibDoc=Doc.new(96,64,"Nib GPU")
        local flat=Brush.beginStroke(nibDoc.layers[1].canvas,{tip=1,aspect=0.2,angle=0})
        Brush.segment(nibDoc.layers[1].canvas,25.5,22.5,25.5,22.5,
            {1,0,0},22,1,false,flat)
        local flatPixels=nibDoc.layers[1].canvas:newImageData()
        local _,_,_,axisA=flatPixels:getPixel(33,22)
        local _,_,_,thinA=flatPixels:getPixel(25,30)
        assert(axisA>0.5 and thinA<0.05,"Ponta chata nao gerou elipse")
        local grainDoc=Doc.new(96,64,"Chalk GPU")
        local grainStroke=Brush.beginStroke(grainDoc.layers[1].canvas,{tip=2,grain=1,seed=239})
        Brush.segment(grainDoc.layers[1].canvas,45.5,30.5,45.5,30.5,
            {0,0,1},24,1,false,grainStroke)
        local grainPixels=grainDoc.layers[1].canvas:newImageData()
        local dark,light=0,0
        for yy=22,38 do for xx=37,53 do
            local _,_,_,alpha=grainPixels:getPixel(xx,yy)
            if alpha>0.6 then dark=dark+1
            elseif alpha>0 and alpha<0.08 then light=light+1 end
        end end
        assert(dark>0 and light>0,"Textura nativa sem variacao de alpha")
        print("INKORA_CPP_TIP_PRESETS_OK")
    end
    if stroke then
        -- Testa importacao de ponta PNG em memoria, fluxo e pressao via LuaJIT.
        local alphaArt=love.image.newImageData(4,4,"rgba8")
        for y=0,3 do for x=0,1 do
            alphaArt:setPixel(x,y,1,1,1,1)
        end end
        local customMask=Native.createMask(alphaArt)
        assert(customMask.width==4 and customMask.height==4,"Mascara PNG invalida")
        local customDoc=Doc.new(96,64,"Imported mask GPU")
        local customStroke=Brush.beginStroke(customDoc.layers[1].canvas,{
            tip=3,angle=0,mask=customMask,flow=0.5,pressureOpacity=0
        })
        Brush.segment(customDoc.layers[1].canvas,47.5,31.5,47.5,31.5,
            {1,0,0},20,1,false,customStroke,1,1)
        local bitmap=customDoc.layers[1].canvas:newImageData()
        local _,_,_,left=bitmap:getPixel(43,31)
        local _,_,_,right=bitmap:getPixel(53,31)
        assert(left>0.40 and left<0.60 and right<0.02,
            "Mascara personalizada/fluxo nao respeitados")
        local pressureDoc=Doc.new(96,64,"Pressure opacity GPU")
        local pressureStroke=Brush.beginStroke(pressureDoc.layers[1].canvas,{
            tip=0,flow=1,pressureOpacity=1
        })
        Brush.segment(pressureDoc.layers[1].canvas,40.5,28.5,40.5,28.5,
            {0,0,1},20,1,false,pressureStroke,0,0)
        assert(Native.lastUpload.pixels==0,"Pressao zero deveria suprimir tinta")
        local alphaAtZero=pressureDoc.layers[1].canvas:newImageData()
        local _,_,_,zero=alphaAtZero:getPixel(40,28)
        assert(zero==0,"Pressao zero modificou camada")
        local pressureStroke2=Brush.beginStroke(pressureDoc.layers[1].canvas,{
            tip=0,flow=1,pressureOpacity=1
        })
        Brush.segment(pressureDoc.layers[1].canvas,40.5,28.5,40.5,28.5,
            {0,0,1},20,1,false,pressureStroke2,1,1)
        local full=pressureDoc.layers[1].canvas:newImageData()
        local _,_,_,fullAlpha=full:getPixel(40,28)
        assert(fullAlpha>0.95,"Pressao maxima nao depositou tinta")
        -- PNG totalmente opaco: máscara por luminancia invertida.
        local opaqueArt=love.image.newImageData(2,1,"rgba8")
        opaqueArt:setPixel(0,0,0,0,0,1)
        opaqueArt:setPixel(1,0,1,1,1,1)
        local opaqueMask=Native.createMask(opaqueArt)
        assert(opaqueMask.buffer[0]==255 and opaqueMask.buffer[1]==0,
            "Ponta opaca precisa ler preto sobre branco")
        print("INKORA_BITMAP_MASK_FLOW_PRESSURE_OK")
    end

    -- Alteracao direta do Canvas invalida os tiles de C++.
    Brush.shape(d.layers[1].canvas,"line",60,5,60,27,{0,1,0},3,1)
    if stroke then
        local prior=Native.stats()
        local again=Brush.beginStroke(d.layers[1].canvas)
        Brush.segment(d.layers[1].canvas,57.5,16.5,60.5,16.5,
            {0,0,1},3,1,false,again)
        assert(Native.stats().readbacks>prior.readbacks,
            "Forma Lua deveria invalidar cache nativo")
    end
    Brush.segment(d.layers[1].canvas,12,12,38,12,{1,0,0},9,1,false)
    Brush.shape(d.layers[1].canvas,"line",8,40,50,40,{0,1,0},3,1)
    Brush.shape(d.layers[1].canvas,"rectangle",10,18,38,30,{0,0,1},2,1)
    Brush.shape(d.layers[1].canvas,"ellipse",50,10,86,39,{0,0,0},2,1)
    local red=d:sampleColor(12,12)
    assert(red and red[1]>0.65 and red[2]<0.5, "Amostra do pincel falhou")

    local img=d.layers[1].canvas:newImageData()
    assert(Fill.apply(img,92,59,{0,0,1},0),"Balde nao modificou area")
    d:replaceLayerData(1,img)
    local blue=d:sampleColor(92,59)
    assert(blue and blue[3]>0.75 and blue[1]<0.3,"Balde nao apareceu na camada")
    assert(d:undo(),"Undo falhou")
    local white=d:sampleColor(92,59)
    assert(white and close(white[1],1) and close(white[2],1),"Undo nao restaurou")
    assert(d:redo(),"Redo falhou")

    -- Testa compositor C++ v5 integrado ao documento (camadas, modo, undo,
    -- amostragem, exportacao e round-trip do formato existente).
    if requireNative then
        local layered=Doc.new(64,64,"Layer C++")
        Brush.segment(layered.layers[1].canvas,32.5,32.5,32.5,32.5,
            {1,0,0},55,1,false,Brush.beginStroke(layered.layers[1].canvas))
        assert(layered:addLayer("Tinta azul"))
        Brush.segment(layered.layers[2].canvas,32.5,32.5,32.5,32.5,
            {0,0,1},55,1,false,Brush.beginStroke(layered.layers[2].canvas))
        assert(layered:setLayerBlend(2,1),"Modo Multiply nao definido")
        local multiplied=layered:sampleColor(32,32)
        assert(multiplied[1]<0.08 and multiplied[2]<0.08 and multiplied[3]<0.08,
            "Camadas Multiply nao produziram preto")
        local cached=layered:compositedCanvas()
        assert(cached==layered:compositedCanvas(),"Composicao nao reutilizada")
        layered:draw(0,0,1)
        assert(layered:setLayerBlend(2,2),"Modo Screen nao definido")
        local screened=layered:sampleColor(32,32)
        assert(screened[1]>0.9 and screened[2]<0.1 and screened[3]>0.9,
            "Modo Screen deveria produzir magenta")
        assert(layered:undo(),"Undo do modo de camada falhou")
        assert(layered.layers[2].blendMode==1,"Undo nao restaurou Multiply")
        assert(layered:redo(),"Redo do modo de camada falhou")
        assert(layered.layers[2].blendMode==2,"Redo nao restaurou Screen")
        local pngPath=layered:exportPNG()
        assert(pngPath and pngPath:match("%.png$"),"Exportacao com blend falhou")
        local key=layered.projectKey
        layered:save("Layer C++")
        local loaded=Doc.load(layered.projectKey)
        assert(loaded.layers[2].blendMode==2,"Manifesto perdeu o modo Screen")
        local restored=loaded:sampleColor(32,32)
        assert(restored[1]>0.9 and restored[3]>0.9,
            "Projeto reaberto perdeu composicao C++")
        assert(loaded:setLayerBlend(2,0),"Modo normal nao restaurado")
        print("INKORA_NATIVE_LAYER_COMPOSITOR_OK")
    end

    if requireNative then
        -- End-to-end of rectangular selection and alpha-lock over a real Canvas.
        local isolated=Doc.new(64,64,"Selection / Alpha Lock")
        local layer=isolated.layers[1]
        local start=Brush.beginStroke(layer.canvas,{tip=0})
        Brush.segment(layer.canvas,32.5,32.5,32.5,32.5,
            {1,0,0},38,1,false,start)
        assert(isolated:setSelection(29,29,35,35))
        assert(isolated:setLayerAlphaLock(1,true))
        local locked=Brush.beginStroke(layer.canvas,{
            tip=0,alphaLock=true,selection=isolated.selection
        })
        Brush.segment(layer.canvas,32.5,32.5,32.5,32.5,
            {0,0,1},40,1,false,locked)
        local pixels=layer.canvas:newImageData()
        local r,g,b,a=pixels:getPixel(32,32)
        assert(b>0.9 and r<0.1 and a>0.9,"Alpha Lock nao recoloriu centro")
        local outR,outG,outB=pixels:getPixel(28,32)
        assert(outR>0.9 and outB<0.1,"Pincel vazou da selecao")
        local _,_,_,farAlpha=pixels:getPixel(55,32)
        assert(farAlpha==0,"Pincel criou pixels fora da area pintada")
        isolated:save("Selection / Alpha Lock")
        local loaded=Doc.load(isolated.projectKey)
        assert(loaded.layers[1].alphaLock,"Projeto perdeu Alpha Lock")
        assert(loaded.selection==nil,"Selecao temporaria nao deve persistir")
        assert(isolated:undo(),"Undo Alpha Lock falhou")
        assert(not isolated.layers[1].alphaLock,"Undo nao reverteu Alpha Lock")
        assert(isolated:redo(),"Redo Alpha Lock falhou")
        assert(isolated.layers[1].alphaLock,"Redo nao restaurou Alpha Lock")

        -- The fill tool respects both selection and existing pixel alpha.
        local filled=love.image.newImageData(8,8,"rgba8")
        for yy=1,6 do for xx=1,6 do
            filled:setPixel(xx,yy,1,0,0,0.5)
        end end
        local selection={x0=3,y0=3,x1=5,y1=5}
        assert(Fill.apply(filled,3,3,{0,1,0},0,
            {selection=selection,alphaLock=true}))
        local fr,fg,fb,fa=filled:getPixel(3,3)
        assert(fg>0.99 and fr<0.01 and math.abs(fa-0.5)<0.01,
            "Balde com Alpha Lock alterou transparencia")
        local outsideRed,outsideGreen=filled:getPixel(2,3)
        assert(outsideRed>0.99 and outsideGreen==0,
            "Balde ignorou a selecao")
        assert(not Fill.apply(filled,0,0,{0,0,1},0,{alphaLock=true}),
            "Balde deveria ignorar area transparente travada")
        print("INKORA_SELECTION_ALPHA_LOCK_GPU_OK")
    end

    if requireNative then
        -- Real GPU <-> LuaJIT <-> C++ clipping and bitmap mask integration.
        local effects=Doc.new(64,64,"Mask & clipping")
        local bottom=effects.layers[1]
        Brush.segment(bottom.canvas,18.5,30.5,18.5,30.5,
            {0,0,1},34,1,false,Brush.beginStroke(bottom.canvas))
        assert(effects:addLayer("Tinta vermelha"))
        local upper=effects.layers[2]
        Brush.segment(upper.canvas,32.5,30.5,32.5,30.5,
            {1,0,0},60,1,false,Brush.beginStroke(upper.canvas))
        assert(effects:setClipping(2,true),"Clipping nao foi ativado")
        local left=effects:sampleColor(18,30)
        local outside=effects:sampleColor(48,30)
        assert(left[1]>0.90 and left[3]<0.10,
            "Clipping deveria mostrar vermelho sobre base")
        assert(outside[1]>0.95 and outside[2]>0.95 and outside[3]>0.95,
            "Clipping vazou onde a base e transparente")

        -- Mask built from selection, inverted, and undone/redone.
        assert(effects:setSelection(16,20,22,40))
        assert(effects:createLayerMask(2),"Falha ao criar mascara da selecao")
        local restricted=effects:sampleColor(18,30)
        local unmasked=effects:sampleColor(26,30)
        assert(restricted[1]>0.9 and restricted[3]<0.10,
            "Mascara excluiu pixel selecionado")
        assert(unmasked[3]>0.9 and unmasked[1]<0.10,
            "Mascara nao ocultou camada superior")

        assert(effects:invertLayerMask(2),"Inversao de mascara falhou")
        local reversed=effects:sampleColor(18,30)
        assert(reversed[3]>0.9 and reversed[1]<0.10,
            "Inversao nao ocultou pixel antes visivel")
        assert(effects:undo(),"Undo da mascara invertida falhou")
        local restored=effects:sampleColor(18,30)
        assert(restored[1]>0.9 and restored[3]<0.10,
            "Undo nao restaurou a mascara original")
        assert(effects:redo(),"Redo da mascara invertida falhou")
        local afterRedo=effects:sampleColor(18,30)
        assert(afterRedo[3]>0.9 and afterRedo[1]<0.10,
            "Redo nao recuperou a mascara invertida")

        -- The lower layer's mask must also constrain clipping.
        assert(effects:createLayerMask(1),"Mascara-base ausente")
        local baseMask=effects.layers[1].mask
        assert(baseMask:getFormat()=="rgba8")
        effects:clearSelection()
        assert(effects:invertLayerMask(1),"Nao foi possivel inverter mascara-base")
        local noBase=effects:sampleColor(18,30)
        assert(noBase[1]>0.95 and noBase[2]>0.95 and noBase[3]>0.95,
            "Mascara da base nao limitou clipping corretamente")
        assert(effects:undo(),"Undo da mascara-base falhou")

        local path=effects:exportPNG()
        assert(path and path:match("%.png$"),"Exportacao de mascara falhou")
        effects:save("Mask & clipping")
        local copy=Doc.load(effects.projectKey)
        assert(copy.layers[2].clipping==true,"Clipping perdido no manifesto")
        assert(copy.layers[2].mask~=nil and copy.layers[1].mask~=nil,
            "Mascara perdida no projeto salvo")
        local loadedColor=copy:sampleColor(18,30)
        assert(loadedColor[3]>0.9 and loadedColor[1]<0.1,
            "Mascara restaurada nao reproduziu a mesma imagem")
        assert(copy:removeLayerMask(2),"Remover mascara falhou")
        assert(copy.layers[2].mask==nil,"Remocao nao aplicou")
        assert(copy:undo(),"Undo ao remover mascara falhou")
        assert(copy.layers[2].mask~=nil,"Undo nao restaurou mascara")
        assert(copy:setClipping(2,false),"Desativar clipping falhou")
        assert(copy:undo(),"Undo do clipping falhou")
        assert(copy.layers[2].clipping,"Undo nao restaurou clipping")
        print("INKORA_MASK_CLIPPING_GPU_OK")
    end

    -- Teste de atravessar 3 tiles: nao pode haver costura nas fronteiras.
    local wide=Doc.new(320,192,"Tile boundary")
    Native.resetStats()
    local wideStroke=Brush.beginStroke(wide.layers[1].canvas)
    if requireNative then assert(wideStroke,"Tile renderer nao iniciou") end
    Brush.segment(wide.layers[1].canvas,112.5,120.5,265.5,120.5,
        {0,1,0},15,1,false,wideStroke)
    local wideImage=wide.layers[1].canvas:newImageData()
    for _,x in ipairs({115,126,127,128,129,200,254,255,256,257,263}) do
        local r,g,b,a=wideImage:getPixel(x,120)
        assert(g>0.6 and a>0.6,"Linha falhou perto da borda do tile: "..x)
    end
    local boundaryStats=Native.stats()
    if wideStroke then
        assert(boundaryStats.zeroTiles>=3,"Esperadas inicializacoes em multiplos tiles")
        assert(boundaryStats.readbackPixels==0,"Tile novo deveria dispensar GPU readback")
        assert(boundaryStats.uploadedPixels<320*192,"Traco usou transferencias grandes")
        print("INKORA_CROSS_TILE_STROKE_OK")
    end

    -- LRU limitado: ao expulsar tiles ja pintados, o canvas ainda contem
    -- a cor anterior, e recarregar o tile precisa usar readback (nao zero).
    if stroke then
        local stress=Doc.new(512,512,"Stress LRU")
        Native.resetStats()
        for gy=0,3 do
            for gx=0,3 do
                local sx=gx*128+36.5
                local sy=gy*128+36.5
                local pass=Brush.beginStroke(stress.layers[1].canvas)
                Brush.segment(stress.layers[1].canvas,sx,sy,sx,sy,
                    {1,0,0},12,1,false,pass)
            end
        end
        assert(Native.cacheSize(stress.layers[1].canvas)<=Native.tileLimit(),
            "Cache de tiles ultrapassou limite")
        if Native.tileLimit()<16 then
            local before=Native.stats()
            assert(before.evictions>0,"Cache nao removeu tiles antigos")
            local revisit=Brush.beginStroke(stress.layers[1].canvas)
            Brush.segment(stress.layers[1].canvas,50.5,36.5,50.5,36.5,
                {0,0,1},12,1,false,revisit)
            local after=Native.stats()
            assert(after.readbacks>before.readbacks,
                "Tile pintado e expulso deveria ser relido")
            local pixels=stress.layers[1].canvas:newImageData()
            local rr,gg,bb,aa=pixels:getPixel(36,36)
            assert(rr>0.8 and bb<0.2 and aa>0.8,
                "Tile expulso perdeu pixels antigos")
            local r2,g2,b2,a2=pixels:getPixel(50,36)
            assert(b2>0.8 and r2<0.2 and a2>0.8,
                "Tile recarregado nao recebeu novo traco")
        end
        print("INKORA_TILE_LRU_OK")
    end
    assert(d:addLayer("Teste adicional"),"Criacao de camada falhou")
    assert(d:moveLayer(-1),"Movimentacao de camada falhou")
    assert(d:toggleLayer(1)==nil,"Alternancia de visibilidade invalida")
    d:toggleLayer(1)
    d.selected=2
    local path=d:save("Teste GPU")
    assert(path and not d.dirty,"Salvamento nao concluiu")
    local copy=Doc.load(d.projectKey)
    assert(copy.width==96 and copy.height==64 and #copy.layers==2,"Projeto reaberto incorreto")
    assert(copy:exportPNG(),"Falha ao exportar PNG")
    local projects=Doc.listProjects()
    assert(#projects>=1,"Projeto nao listado")
    -- UI overhaul must change real brush parameters and allow real hits.
    if app then
        local UI=app.ui
        assert(app:choosePreset("chalk"),"Preset de giz nao encontrado")
        assert(app.brushTip==2 and app.brushSize==29 and
            app.brushFlow==0.75,"Preset mudou so a aparencia")
        assert(not app:choosePreset("missing"),"Preset inexistente aceito")
        assert(not app:choosePreset("custom") or app.tipMask,
            "Ponta PNG sem imagem foi selecionada")
        local width=love.graphics.getWidth()
        local px=width-316+18
        UI.tab="brush"
        love.draw()
        assert(UI:click(px+32,325),"Cartao de preset nao clicavel")
        assert(app.presetId=="marker" and app.brushTip==1 and
            app.brushSize==28,"Biblioteca visual nao aplica o preset")
        UI.tab="settings"
        love.draw()
        assert(UI:click(px+215,230),"Controle de tamanho nao clicavel")
        assert(app.brushSize>50,"Slider de pincel nao alterou o tamanho")
        UI:mousereleased()

        -- The live panel must show edited (not factory) parameters
        -- and reuse the same C++ texture until a real value changes.
        local BrushPreview=require("src.brush_preview")
        local liveBefore=BrushPreview.getLive(app)
        assert(liveBefore and liveBefore==BrushPreview.getLive(app),
            "Previa ao vivo nao foi mantida em cache")
        app.brushFlow=0.06
        local liveAfter=BrushPreview.getLive(app)
        assert(liveAfter and liveAfter~=liveBefore,
            "Fluxo alterado nao renovou a previa C++")
        assert(BrushPreview.stats().live==1,
            "Ajustes deveriam reter apenas uma previa dinamica")
        local imgBefore,imgAfter=liveBefore:newImageData(),liveAfter:newImageData()
        local alphaBefore,alphaAfter=0,0
        for yy=0,43,3 do for xx=0,167,3 do
            local _,_,_,a=imgBefore:getPixel(xx,yy)
            local _,_,_,b=imgAfter:getPixel(xx,yy)
            alphaBefore=alphaBefore+a
            alphaAfter=alphaAfter+b
        end end
        assert(alphaBefore>alphaAfter+4,
            "A previa nao respondeu visualmente ao fluxo de tinta")
        app.brushFlow=0.31
        app.brushSize=43
        local Profiles=require("src.brush_profiles")
        -- Exercise actual UI action, persistence, reload and factory reset.
        love.draw()
        assert(UI:click(px+58,671),"Salvar preset nao clicavel")
        local saved=Profiles.read()
        assert(saved.marker and saved.marker.size==43 and
            math.abs(saved.marker.flow-0.31)<0.001,
            "Preset nao persistiu os ajustes editados")
        app.brushSize=3
        app.brushFlow=0.99
        assert(app:choosePreset("marker") and app.brushSize==43 and
            math.abs(app.brushFlow-0.31)<0.001,
            "Reabrir pincel ignorou configuracao salva")
        UI.tab="settings"
        love.draw()
        assert(UI:click(px+201,671),"Restaurar preset nao clicavel")
        assert(not app.profiles.marker and app.brushSize==28,
            "Restaurar nao recuperou preset de fabrica")
        local restored=Profiles.read()
        assert(not restored.marker,"Restauracao nao removeu perfil salvo")
        -- Profiles retain nib angle and direction follow mode per brush.
        app:choosePreset("marker")
        app.brushAngle=67
        app.brushFollowPath=false
        assert(app:saveBrushProfile())
        local persisted=Profiles.read()
        assert(persisted.marker.angle==67 and persisted.marker.followPath==0,
            "Modo direcional nao foi persistido no preset")
        app.brushAngle=1
        app.brushFollowPath=true
        assert(app:choosePreset("marker"))
        assert(app.brushAngle==67 and not app.brushFollowPath,
            "Configuracao direcional perdida ao selecionar pincel")
        assert(app:resetBrushProfile())
        assert(app.brushAngle==0 and app.brushFollowPath,
            "Restaurar nao recuperou orientacao inicial do marcador")

        -- Distinct pixels are generated by fixed vs tangent-following nibs.
        local nibFlat=Doc.new(96,96,"Inkora directional nib")
        local fixedCanvas=nibFlat.layers[1].canvas
        local strokeFixed=Brush.beginStroke(fixedCanvas,{
            tip=1,aspect=0.18,angle=0,followPath=false,
            hardness=1,spacing=1,flow=1,pressureOpacity=0
        })
        Brush.segment(fixedCanvas,48.5,48.5,48.5,49.5,
            {1,0,0},24,1,false,strokeFixed)
        local fixedPixels=fixedCanvas:newImageData()
        local _,_,_,fixedRight=fixedPixels:getPixel(56,48)
        local _,_,_,fixedBottom=fixedPixels:getPixel(48,56)
        assert(fixedRight>0.9 and fixedBottom<0.1,
            "Ponta chata fixa nao preservou angulo")
        local followingDoc=Doc.new(96,96,"Inkora following nib")
        local followingCanvas=followingDoc.layers[1].canvas
        local strokeFollowing=Brush.beginStroke(followingCanvas,{
            tip=1,aspect=0.18,angle=0,followPath=true,
            hardness=1,spacing=1,flow=1,pressureOpacity=0
        })
        Brush.segment(followingCanvas,48.5,48.5,48.5,49.5,
            {1,0,0},24,1,false,strokeFollowing)
        local turnPixels=followingCanvas:newImageData()
        local _,_,_,turnRight=turnPixels:getPixel(56,48)
        local _,_,_,turnBottom=turnPixels:getPixel(48,56)
        assert(turnRight<0.1 and turnBottom>0.9,
            "Ponta chata nao seguiu a trajetoria do cursor")
        assert(strokeFollowing.direction[0].initialized==1 and
            math.abs(tonumber(strokeFollowing.direction[0].angle_degrees)-90)<0.1,
            "Ponte Lua/C++ nao manteve angulo da direcao")

        -- Active-preview cache respects angle and direction switches.
        app:choosePreset("marker")
        UI.tab="settings"
        love.draw()
        local oldDirection=BrushPreview.getLive(app)
        app.brushFollowPath=false
        local newDirection=BrushPreview.getLive(app)
        assert(oldDirection~=newDirection,
            "Previa nao atualizou apos mudar modo direcional")
        app.brushAngle=60
        assert(BrushPreview.getLive(app)~=newDirection,
            "Previa nao atualizou apos mudar angulo")
        app.brushAngle=0
        app.brushFollowPath=true
        print("INKORA_DIRECTIONAL_BRUSH_LUA_CPP_OK")
        -- Tablet input is optional on Linux CI: inject pressure samples
        -- into the same path used by Windows WinTab polling.
        local Tablet=require("src.tablet")
        local initialCurve=app.pressureCurve
        local currentTime=love.timer.getTime()
        Tablet._injectForTest(0.5,currentTime)
        assert(math.abs(app:pressureFromTablet()-0.5)<0.01,
            "Pressao de caneta nao entrou no caminho do mouse")
        assert(math.abs(app.sampledPressure-0.5)<0.01)
        UI.tab="settings"
        love.draw()
        assert(UI:click(px+65,706),"Botao de curva de pressao nao clicavel")
        assert(app.pressureCurve=="Firme",
            "Curva de pressao nao alterou a resposta")
        local newCurve=love.filesystem.read("pen-pressure-curve.txt")
        assert(newCurve=="Firme","Curva de pressao nao foi salva")
        Tablet._injectForTest(0.5,love.timer.getTime())
        assert(app:pressureFromTablet()<0.5,
            "Curva firme nao diminuiu a sensibilidade")
        Tablet._injectForTest(0,love.timer.getTime())
        assert(app:pressureFromTablet()==1,
            "Mouse sem pressão de caneta nao voltou ao padrao")
        assert(app:setPressureCurve(initialCurve))
        Tablet.shutdown()
        print("INKORA_WINTAB_PRESSURE_INPUT_FALLBACK_OK")
        print("INKORA_LIVE_PREVIEW_SAVED_PRESET_OK")

        UI.tab="color"
        love.draw()
        local oldColor={app.color[1],app.color[2],app.color[3]}
        assert(UI:click(px+140,340),"Seletor HSV nao clicavel")
        assert(app.colorIndex==nil and (
            math.abs(app.color[1]-oldColor[1])>0.01 or
            math.abs(app.color[2]-oldColor[2])>0.01 or
            math.abs(app.color[3]-oldColor[3])>0.01),
            "Seletor HSV nao modificou a cor")
        assert(app.doc:addLayer("Miniatura"))
        UI.tab="layers"
        love.draw()
        assert(UI:click(px+86,274),"Miniatura de camada nao clicavel")
        assert(app.doc.selected==2,"Painel nao selecionou a camada superior")
        -- All panels should render in a real graphics context, including
        -- minimum supported window dimensions.
        UI.tab="brush"
        love.draw()

        -- Favorites must persist in LÖVE's writable preference directory.
        local chalkWasFavorite=not not app.favorites.chalk
        assert(app:toggleFavorite("chalk"),"Pincel favorito nao alternou")
        local changed=not not app.favorites.chalk
        assert(changed~=chalkWasFavorite)
        app:loadFavorites()
        assert((not not app.favorites.chalk)==changed,
            "Favoritos nao sobreviveram a recarga")
        assert(app:toggleFavorite("chalk"))
        app:loadFavorites()
        assert((not not app.favorites.chalk)==chalkWasFavorite)
        UI.favoriteOnly=true
        UI.tab="brush"
        love.draw()
        assert(UI:click(px+25,262),"Filtro de favoritos nao mostrou pinceis")
        assert(app.presetId=="ink","Filtro escolheu preset errado")
        UI.favoriteOnly=false

        -- Category navigation filters actual presets, not only the caption.
        UI.brushCategory=2 -- Tinta
        UI.favoriteOnly=false
        UI.tab="brush"
        love.draw()
        local inkGroup=UI:visibleBrushes(app)
        assert(#inkGroup==2,"Categoria Tinta nao filtrou a biblioteca")
        for _,preset in ipairs(inkGroup) do
            assert(preset.family=="Tinta")
        end
        assert(UI:click(px+175,217),"Botao de categoria nao clicavel")
        local sketchGroup=UI:visibleBrushes(app)
        assert(#sketchGroup==1 and sketchGroup[1].id=="pencil",
            "Categoria Esboco nao corresponde ao grupo de presets")
        UI.brushCategory=1
        love.draw()

        -- Every thumbnail is generated by the real C++ brush, not UI strokes.
        local BrushPreview=require("src.brush_preview")
        local Presets=require("src.presets")
        local realOne=BrushPreview.get(Presets.find("ink"))
        local realTwo=BrushPreview.get(Presets.find("chalk"))
        if requireNative then
            assert(realOne and realTwo and realOne~=realTwo,
                "Previews C++ nao foram criados")
            assert(realOne==BrushPreview.get(Presets.find("ink")),
                "Preview renderizada novamente sem necessidade")
            local first=realOne:newImageData()
            local second=realTwo:newImageData()
            local sum1,sum2,difference=0,0,0
            for yy=0,43,2 do for xx=0,167,2 do
                local _,_,_,a=first:getPixel(xx,yy)
                local _,_,_,b=second:getPixel(xx,yy)
                sum1=sum1+a
                sum2=sum2+b
                difference=difference+math.abs(a-b)
            end end
            assert(sum1>1 and sum2>1 and difference>5,
                "Pinceis de pontas diferentes produzem a mesma miniatura")
            assert(BrushPreview.stats().count>=2)
        end
        -- Dedicated texture inspector updates the actual C++ stroke and
        -- saves the 3 new parameters in an editable brush profile.
        assert(app:choosePreset("ink"))
        UI.tab="texture"
        love.draw()
        local basePreview=BrushPreview.getLive(app)
        assert(basePreview~=nil)
        assert(UI:click(px+211,259),"Slider de textura nao clicavel")
        UI:mousereleased()
        assert(app.brushTexture>0.6,"Slider nao alterou textura real")
        assert(UI:click(px+196,347),"Slider de dispersao nao clicavel")
        UI:mousereleased()
        assert(app.brushScatter>0.5,"Slider nao alterou dispersao")
        assert(UI:click(px+218,435),"Slider de variacao nao clicavel")
        UI:mousereleased()
        assert(app.brushSizeJitter>0.6,"Slider nao alterou tamanho variavel")
        local changedPreview=BrushPreview.getLive(app)
        assert(changedPreview and changedPreview~=basePreview,
            "Previa nao mudou ao alterar dinamica do pincel")
        assert(BrushPreview.getLive(app)==changedPreview)
        local oldData,newData=basePreview:newImageData(),
            changedPreview:newImageData()
        local difference=0
        for yy=0,43,2 do for xx=0,167,2 do
            local _,_,_,o=oldData:getPixel(xx,yy)
            local _,_,_,n=newData:getPixel(xx,yy)
            difference=difference+math.abs(n-o)
        end end
        assert(difference>10,"Textura e dispersao nao alteraram pixels")
        love.draw()
        assert(UI:click(px+40,661),"Salvar preset texturizado nao clicavel")
        local Profiles=require("src.brush_profiles")
        local savedTexture=Profiles.read().ink
        assert(savedTexture and savedTexture.texture>0.6 and
            savedTexture.scatter>0.5 and savedTexture.sizeJitter>0.6,
            "Novo preset nao persistiu dados de textura")
        assert(app:choosePreset("marker"))
        assert(app:choosePreset("ink"))
        assert(app.brushTexture>0.6 and app.brushScatter>0.5,
            "Troca de pincel perdeu configuracao texturizada")
        UI.tab="texture"
        love.draw()
        assert(UI:click(px+200,661),"Restaurar textura nao clicavel")
        assert(app.brushTexture==0 and app.brushScatter==0 and
            app.brushSizeJitter==0,"Reset nao restaurou pincel padrao")
        UI.tab="brush"
        love.draw()
        -- True wet color blending on existing paint, preview comparison,
        -- editable presets, and normal brush retention.
        assert(app:choosePreset("watercolor"))
        assert(app.brushWetness>0.5 and app.brushPigmentLoad<0.5)
        local priorColor=app.color
        app.color={0.95,0.92,0.12}
        UI.tab="wet"
        love.draw()
        local BrushPreview=require("src.brush_preview")
        local beforeWet=BrushPreview.getLive(app,true)
        local dryComparison=BrushPreview.getDryComparison(app)
        assert(beforeWet and dryComparison and beforeWet~=dryComparison,
            "Comparacao de tinta nao criou duas imagens C++")
        local beforePixels=beforeWet:newImageData()
        local dryPixels=dryComparison:newImageData()
        local diff=0
        for y=7,36,3 do for x=10,156,3 do
            local r1,g1,b1=beforePixels:getPixel(x,y)
            local r2,g2,b2=dryPixels:getPixel(x,y)
            diff=diff+math.abs(r1-r2)+math.abs(g1-g2)+math.abs(b1-b2)
        end end
        assert(diff>3,"Tinta umida e seca produziram as mesmas cores")
        assert(UI:click(px+214,256),"Slider de umidade nao clicavel")
        UI:mousereleased()
        assert(app.brushWetness>0.60)
        assert(UI:click(px+60,314),"Slider de carga nao clicavel")
        UI:mousereleased()
        assert(app.brushPigmentLoad<0.40)
        assert(UI:click(px+222,372),"Slider de captacao nao clicavel")
        UI:mousereleased()
        assert(app.brushPigmentPickup>0.7)
        assert(UI:click(px+222,430),"Slider de retencao nao clicavel")
        UI:mousereleased()
        assert(app.brushPigmentRetention>0.7)
        local localWet=BrushPreview.getLocalWetComparison(app)
        local carryWet=BrushPreview.getLive(app,true)
        assert(localWet and carryWet and localWet~=carryWet,
            "Comparacao local x arraste nao foi criada")
        local left=localWet:newImageData()
        local right=carryWet:newImageData()
        local pigmentDiff=0
        for yy=8,36,3 do for xx=10,157,3 do
            local lr,lg,lb=left:getPixel(xx,yy)
            local rr,rg,rb=right:getPixel(xx,yy)
            pigmentDiff=pigmentDiff+math.abs(lr-rr)+math.abs(lg-rg)+math.abs(lb-rb)
        end end
        assert(pigmentDiff>1,"Arraste nao alterou as cores na previa")
        local afterWet=BrushPreview.getLive(app,true)
        assert(afterWet~=beforeWet,"Umidade nao renovou a previa")
        love.draw()
        assert(UI:click(px+41,713),"Salvar tinta umida nao clicavel")
        local wetProfile=require("src.brush_profiles").read().watercolor
        assert(wetProfile and wetProfile.wetness>0.6 and
            wetProfile.pigmentLoad<0.4 and wetProfile.pigmentPickup>0.7
            and wetProfile.pigmentRetention>0.7,
            "Config de pigmento e reservatorio nao foi salva")
        assert(app:choosePreset("ink"))
        assert(app.brushWetness==0 and app.brushPigmentLoad==1,
            "Pincel seco foi afetado pelos controles de tinta")
        assert(app:choosePreset("watercolor"))
        assert(app.brushWetness>0.6 and app.brushPigmentLoad<0.4,
            "Configuracao de tinta umida nao foi restaurada")
        UI.tab="wet"
        love.draw()
        assert(UI:click(px+200,713),"Restaurar tinta nao clicavel")
        assert(math.abs(app.brushWetness-0.78)<0.001 and
            math.abs(app.brushPigmentLoad-0.38)<0.001 and
            math.abs(app.brushPigmentPickup-0.70)<0.001 and
            math.abs(app.brushPigmentRetention-0.78)<0.001,
            "Restaurar nao recuperou o preset Aquarela")
        app.color=priorColor
        -- Later cursor-placement smoke checks require an opaque solid nib:
        -- they must not inherit the semi-transparent watercolor preset.
        assert(app:choosePreset("ink"))
        UI.tab="brush"
        love.draw()
        print("INKORA_PIGMENT_CARRY_LUA_CPP_OK")
        print("INKORA_WET_PAINT_PREVIEW_PROFILES_OK")

        print("INKORA_TEXTURE_EDITABLE_PREVIEW_GPU_OK")
        print("INKORA_NATIVE_BRUSH_PREVIEWS_OK")

        -- Splitter can resize the inspector without resetting zoom/rotation.
        UI.tab="brush"
        love.draw()
        local beforeWidth=UI.inspectorWidth
        local originalOffset=app.offsetX
        local splitterX=width-beforeWidth
        assert(UI:click(splitterX,175),"Divisoria nao clicavel")
        assert(UI.draggingPanel)
        assert(UI:mousemoved(splitterX-68,175))
        assert(UI.inspectorWidth>beforeWidth,
            "Arrastar divisoria nao aumentou painel")
        assert(math.abs(app.offsetX-originalOffset+
            (UI.inspectorWidth-beforeWidth)/2)<0.01,
            "Painel moveu o canvas inesperadamente")
        UI:mousereleased()
        assert(not UI.draggingPanel)
        UI.inspectorWidth=beforeWidth
        app.offsetX=originalOffset
        love.draw()
        print("INKORA_CATEGORIES_RESIZABLE_INSPECTOR_OK")

        -- Rotated canvas: cursor->document mapping remains stable at every
        -- angle and zoom; a native C++ dab must land under the rotated cursor.
        app:fitView()
        local oldZoom=app.zoom
        local anchorX,anchorY=app:documentToScreen(
            app.doc.width/2,app.doc.height/2)
        app:rotateAt(37,anchorX,anchorY)
        assert(math.abs(math.deg(app.rotation)-37)<0.001)
        local px2,py2=app:documentToScreen(
            app.doc.width/2,app.doc.height/2)
        assert(math.abs(px2-anchorX)<0.01 and math.abs(py2-anchorY)<0.01,
            "Rotacao deslocou o ponto pivot")
        app:zoomAt(1.4,anchorX,anchorY)
        local rx,ry=app:screenToDocument(anchorX,anchorY)
        assert(math.abs(rx-app.doc.width/2)<0.01
            and math.abs(ry-app.doc.height/2)<0.01,
            "Zoom em tela rotacionada perdeu a coordenada do desenho")
        app.tool="brush"
        app:strokeStart(anchorX,anchorY)
        assert(app.dragging and app.dragging.kind=="draw")
        app:strokeEnd(anchorX,anchorY)
        app.dragging=nil
        local active=app.doc.layers[app.doc.selected]
        local img=active.canvas:newImageData()
        local _,_,_,alpha=img:getPixel(
            math.floor(app.doc.width/2),math.floor(app.doc.height/2))
        assert(alpha>0.7,"Pincel nao pintou abaixo do cursor rotacionado")
        love.draw()
        app:resetRotation()
        assert(app.rotation==0,"Reset do giro falhou")
        local fixedX,fixedY=app:documentToScreen(
            app.doc.width/2,app.doc.height/2)
        assert(math.abs(fixedX-anchorX)<0.01
            and math.abs(fixedY-anchorY)<0.01,
            "Reset de giro deslocou o centro")
        app:fitView()
        assert(math.abs(app.zoom-oldZoom)<0.001)
        UI.tab="brush"
        love.draw()
        -- Native C++ paint remains continuous with new adaptive
        -- stabilization at a simulated 60Hz and the tail lands on release.
        app:choosePreset("ink") -- Solid nib: grain must not randomize endpoint assertion.
        app.stabilization=0.97
        local startDocX,startDocY=app.doc.width/2,app.doc.height/2-70
        local startX,startY=app:documentToScreen(startDocX,startDocY)
        assert(app:strokeStart(startX,startY) == nil)
        local eX,eY=startX,startY
        for i=1,22 do
            eX,eY=app:documentToScreen(
                startDocX+i*2,startDocY+math.sin(i*2.6)*2)
            app:strokeMove(eX,eY,1,1/60)
        end
        local pending=app.dragging.smoother
        assert(pending.samples==22,
            "Estabilizador nao recebeu os eventos de movimento")
        local filteredX=app.dragging.x
        assert(filteredX<startDocX+44,
            "Estabilizacao forte nao suavizou o acompanhamento do cursor")
        app:strokeEnd(eX,eY,1)
        local endX,endY=app:screenToDocument(eX,eY)
        assert(math.abs(app.dragging.smoother.x-endX)<0.001 and
            math.abs(app.dragging.smoother.y-endY)<0.001,
            "Final do traco estabilizado nao chegou ao cursor")
        local pixels=app.doc.layers[app.doc.selected].canvas:newImageData()
        local _,_,_,alpha=pixels:getPixel(
            math.floor(endX),math.floor(endY))
        assert(alpha>0.10,
            "Cauda do traco estabilizado nao foi pintada pelo C++")
        app.dragging=nil
        app.stabilization=0.4
        print("INKORA_ADAPTIVE_STABILIZER_CPP_BRIDGE_OK")

        print("INKORA_ROTATION_FAVORITES_OK")
        print("INKORA_DESKTOP_UI_BRUSH_LIBRARY_OK")
    end

    print("INKORA_GPU_SMOKE_OK")
end

return {run=run}
