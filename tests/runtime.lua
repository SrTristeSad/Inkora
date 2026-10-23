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
        -- C++ native bucket integration: selection crosses both 128px
        -- seams, uploads only changed pixels, and undo is region-based.
        local bucket=Doc.new(384,384,"Balde nativo regional")
        assert(bucket:setSelection(123,124,137,137))
        local fillBuffer=bucket.layers[1].canvas:newImageData()
        local changed,bounds=Fill.apply(fillBuffer,126,126,{0.1,0.7,0.9},0,{
            selection=bucket.selection
        })
        assert(changed and bounds.x==123 and bounds.y==124 and
            bounds.width==15 and bounds.height==14,
            "Balde nativo perdeu os limites da selecao")
        assert(bucket:applyFillRegion(1,fillBuffer,bounds))
        local history=bucket:historyStats()
        assert(history.strokeCount==1 and history.fullCount==0 and
            history.tiles==4 and history.bytes==4*128*128*4,
            "Balde deveria capturar somente quatro blocos de undo")
        local painted=bucket.layers[1].canvas:newImageData()
        local _,green,blue,alpha=painted:getPixel(127,127)
        local _,_,_,outsideAlpha=painted:getPixel(138,127)
        assert(green>0.6 and blue>0.8 and alpha>0.9 and outsideAlpha==0,
            "Upload parcial nao respeitou selecao/transparencia")
        assert(bucket:undo())
        local undone=bucket.layers[1].canvas:newImageData()
        local _,_,_,undoneA=undone:getPixel(127,127)
        assert(undoneA==0,"Undo do balde nao removeu tinta")
        assert(bucket:redo())
        local redone=bucket.layers[1].canvas:newImageData()
        local _,_,_,redoA=redone:getPixel(127,127)
        assert(redoA>0.9,"Redo do balde nao restaurou tinta")
        assert(bucket:setLayerAlphaLock(1,true))
        local before=bucket.layers[1].canvas
        local recolor=before:newImageData()
        local recolored,recolorBounds=Fill.apply(recolor,126,126,{1,0,0},0,{
            selection=bucket.selection,alphaLock=true
        })
        assert(recolored and recolorBounds.width==15)
        bucket:applyFillRegion(1,recolor,recolorBounds)
        assert(bucket.layers[1].canvas~=before,
            "Balde nao separou pixels compartilhados no COW")
        local _,_,_,oldA=before:newImageData(1,1,127,127,1,1):getPixel(0,0)
        local red,_,_,newA=bucket.layers[1].canvas:
            newImageData(1,1,127,127,1,1):getPixel(0,0)
        assert(oldA>0.9 and red>0.95 and newA==oldA,
            "Balde com Alpha Lock alterou a camada original")
        assert(bucket:undo())
        local _,oldGreen=bucket.layers[1].canvas:
            newImageData(1,1,127,127,1,1):getPixel(0,0)
        assert(oldGreen>0.6,"Undo do balde com COW nao restaurou cor")
        assert(bucket:redo())
        print("INKORA_NATIVE_FILL_REGION_UNDO_GPU_OK")

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

    if requireNative then
        -- Incremental compositor re-renders the native blend, mask and
        -- clipping only in the 128x128 tile touched by a brush stroke.
        local mosaic=Doc.new(384,256,"Compositor parcial C++")
        local first=mosaic.layers[1].canvas
        Brush.segment(first,79.5,72.5,79.5,72.5,
            {0.98,0.08,0.06},104,1,false,Brush.beginStroke(first))
        assert(mosaic:addLayer("Camada com efeitos"))
        local top=mosaic.layers[2].canvas
        Brush.segment(top,81.5,71.5,81.5,71.5,
            {0.08,0.10,0.99},104,1,false,Brush.beginStroke(top))
        assert(mosaic:setLayerBlend(2,2))
        assert(mosaic:setClipping(2,true))
        assert(mosaic:setSelection(0,0,194,255))
        assert(mosaic:createLayerMask(2))
        mosaic:clearSelection()
        local composed=mosaic:compositedCanvas()
        local startMetrics=mosaic:compositorStats()
        assert(startMetrics.fullBuilds==1 and
            startMetrics.partialBuilds==0 and
            startMetrics.lastPixels==384*256,
            "Primeiro pass nativo deveria compor o documento completo")
        local snapshot=composed:newImageData()
        local farR,farG,farB=snapshot:getPixel(280,192)
        assert(farR>0.99 and farG>0.99 and farB>0.99)
        mosaic:checkpoint(true)
        local detail=Brush.beginStroke(top,{
            hardness=1,tip=0,spacing=0.10,flow=1
        })
        Brush.segment(top,85.5,76.5,86.5,76.5,
            {0.91,0.35,0.08},12,1,false,detail)
        assert(Native.lastUpload and Native.lastUpload.width>0,
            "Motor de pincel nao retornou regiao suja")
        mosaic:markCompositeDirty(Native.lastUpload)
        assert(composed==mosaic:compositedCanvas(),
            "Compositor parcial recriou o objeto Canvas")
        local updated=mosaic:compositorStats()
        assert(updated.fullBuilds==1 and updated.partialBuilds==1
            and updated.lastTiles==1 and updated.lastPixels==128*128,
            "Pincel pequeno recompos mais que um tile")
        local changed=composed:newImageData()
        local p0,q0,r0=changed:getPixel(85,76)
        local p1,q1,r1=snapshot:getPixel(85,76)
        assert(math.abs(p0-p1)+math.abs(q0-q1)+math.abs(r0-r1)>0.03,
            "Tile recomposto nao exibiu a pincelada nova")
        local fr,fg,fb=changed:getPixel(280,192)
        assert(fr==farR and fg==farG and fb==farB,
            "Compositor parcial modificou area distante")
        local sampled=mosaic:sampleColor(85,76)
        assert(sampled and sampled[1] and sampled[2] and sampled[3],
            "Amostra do compositor parcial falhou")
        local path=mosaic:exportPNG()
        assert(path and path:match("%.png$"),"Exportacao parcial falhou")
        -- A complete recomposition must produce byte-identical RGBA8 at
        -- tile seams and sampled interior points, even with two effects.
        mosaic:markCompositeDirty()
        local full=mosaic:compositedCanvas():newImageData()
        assert(mosaic:compositorStats().fullBuilds==2)
        for y=0,255,7 do
            for x=0,383,7 do
                local a,b,c,d=changed:getPixel(x,y)
                local e,f,g,h=full:getPixel(x,y)
                assert(math.abs(a-e)<0.005 and math.abs(b-f)<0.005
                    and math.abs(c-g)<0.005 and math.abs(d-h)<0.005,
                    ("Borda ou cor divergiu no compositor parcial %d,%d")
                        :format(x,y))
            end
        end
        for _,x in ipairs({0,126,127,128,129,254,255,256,257,383}) do
            local a,b,c,d=changed:getPixel(x,76)
            local e,f,g,h=full:getPixel(x,76)
            assert(math.abs(a-e)<0.005 and math.abs(b-f)<0.005
                and math.abs(c-g)<0.005 and math.abs(d-h)<0.005,
                "Seam no tile compositor: "..x)
        end
        assert(mosaic:setLayerBlend(2,1))
        mosaic:compositedCanvas()
        assert(mosaic:compositorStats().fullBuilds==3,
            "Trocar blending deve invalidar todos os tiles")
        assert(mosaic:undo())
        mosaic:compositedCanvas()
        assert(mosaic:compositorStats().fullBuilds==4,
            "Undo deve invalidar toda a imagem composta")
        -- The first/structural composition is now streamed into bounded
        -- 512x512 C++ batches instead of reading every full-size layer.
        local large=Doc.new(768,640,"Composicao inicial regional")
        local base=large.layers[1].canvas
        local paint0=Brush.beginStroke(base)
        Brush.segment(base,428.5,321.5,611.5,321.5,
            {0.97,0.13,0.18},88,1,false,paint0)
        assert(large:addLayer("Screen / clipped"))
        local upper=large.layers[2].canvas
        local paint1=Brush.beginStroke(upper)
        Brush.segment(upper,450.5,321.5,601.5,321.5,
            {0.04,0.12,0.95},72,1,false,paint1)
        assert(large:setLayerBlend(2,2))
        assert(large:setClipping(2,true))
        assert(large:setSelection(477,260,590,395))
        assert(large:createLayerMask(2))
        large:clearSelection()
        local tiledCanvas=large:compositedCanvas()
        local tileStats=large:compositorStats()
        assert(tileStats.fullBuilds==1 and tileStats.lastBatches==4,
            "Composicao inicial deveria usar quatro blocos de 512px")
        assert(tileStats.peakRegionPixels<=512*512 and
            tileStats.buildTileSize==512,
            "Buffer temporario excedeu limite declarado")
        assert(tileStats.lastPixels==768*640 and tileStats.lastTiles==30,
            "Metricas iniciais de composicao divergentes")
        local tiled=tiledCanvas:newImageData()
        -- Independent reference: original non-tiled full-frame C++ routine.
        -- This is only used by the test, never the production compositor.
        local whole=love.graphics.newCanvas(768,640,{format="rgba8"})
        love.graphics.push("all")
        love.graphics.setCanvas(whole)
        love.graphics.clear(1,1,1,1)
        love.graphics.pop()
        local reference=whole:newImageData()
        for index,layer in ipairs(large.layers) do
            if layer.visible and layer.opacity>0 then
                local opt={mask=layer.mask,clipping=layer.clipping}
                if layer.clipping then
                    local previous=large.layers[index-1]
                    if previous and previous.visible then
                        opt.clip=previous.canvas:newImageData()
                        opt.clipMask=previous.mask
                        opt.clipOpacity=previous.opacity
                    end
                end
                Native.blendLayer(reference,layer.canvas:newImageData(),
                    layer.opacity,layer.blendMode or 0,opt)
            end
        end
        for y=0,639,23 do
            for x=0,767,19 do
                local a,b,c,d=tiled:getPixel(x,y)
                local e,f,g,h=reference:getPixel(x,y)
                assert(math.abs(a-e)<0.005 and math.abs(b-f)<0.005
                    and math.abs(c-g)<0.005 and math.abs(d-h)<0.005,
                    ("Inicial em blocos divergiu do compositor inteiro: %d,%d")
                        :format(x,y))
            end
        end
        for x=507,518 do
            for y=311,333,2 do
                local a,b,c,d=tiled:getPixel(x,y)
                local e,f,g,h=reference:getPixel(x,y)
                assert(math.abs(a-e)<0.005 and math.abs(b-f)<0.005
                    and math.abs(c-g)<0.005 and math.abs(d-h)<0.005,
                    ("Emenda na borda 512: %d,%d"):format(x,y))
            end
        end
        assert(large:setLayerBlend(2,4))
        local updatedWhole=large:compositedCanvas()
        assert(updatedWhole==tiledCanvas and
            large:compositorStats().fullBuilds==2 and
            large:compositorStats().lastBatches==4,
            "Mudanca estrutural nao regenerou tiles sem buffer completo")
        -- Brush undo history captures only tiles intersected by the
        -- actual stroke (including eraser / alpha at block boundaries).
        local undoDoc=Doc.new(384,384,"Historico regional de pincel")
        local layerCanvas=undoDoc.layers[1].canvas
        local saveBefore=layerCanvas:newImageData()
        assert(undoDoc:beginStrokeHistory())
        local drawStroke=Brush.beginStroke(layerCanvas,{
            tip=0,hardness=1,spacing=0.12,flow=1
        })
        assert(undoDoc:captureStrokeRegion(95.5,125.5,95.5,125.5,20,0))
        Brush.segment(layerCanvas,95.5,125.5,95.5,125.5,
            {0.98,0.14,0.18},20,1,false,drawStroke)
        assert(undoDoc:captureStrokeRegion(95.5,125.5,276.5,125.5,20,0))
        Brush.segment(layerCanvas,95.5,125.5,276.5,125.5,
            {0.98,0.14,0.18},20,1,false,drawStroke)
        local memory=undoDoc:historyStats()
        assert(memory.steps==1 and memory.strokeCount==1
            and memory.fullCount==0 and memory.tiles==6,
            "Uma pincelada cruzando tiles deve salvar 6 tiles apenas")
        assert(memory.bytes==6*128*128*4 and
            memory.bytes<384*384*4,
            "Historico de pincel salvou mais que uma camada inteira")
        local saveAfter=layerCanvas:newImageData()
        assert(undoDoc:undo(),"Desfazer regionais falhou")
        for _,coord in ipairs({
            {100,124},{126,125},{129,125},{257,124},{275,125},
            {50,50},{300,200}
        }) do
            local x,y=coord[1],coord[2]
            for channel=1,4 do
                local before={saveBefore:getPixel(x,y)}
                local undone={undoDoc.layers[1].canvas:newImageData(1,1,x,y,1,1):getPixel(0,0)}
                assert(math.abs(undone[channel]-before[channel])<0.005,
                    "Undo regional nao restaurou pixel original")
            end
        end
        assert(undoDoc:historyStats().redo==1 and
            undoDoc:historyStats().fullCount==0)
        assert(undoDoc:redo(),"Refazer regional falhou")
        local redoImage=undoDoc.layers[1].canvas:newImageData()
        for y=0,383,13 do for x=0,383,11 do
            local a,b,c,d=redoImage:getPixel(x,y)
            local e,f,g,h=saveAfter:getPixel(x,y)
            assert(math.abs(a-e)<0.005 and math.abs(b-f)<0.005
                and math.abs(c-g)<0.005 and math.abs(d-h)<0.005,
                ("Refazer regional divergiu em %d,%d"):format(x,y))
        end end
        -- Structural operation still uses old full snapshot and mixes with
        -- regional records in both directions of the history stack.
        assert(undoDoc:addLayer("Camada adicional"))
        assert(undoDoc:historyStats().fullCount==1)
        assert(undoDoc:undo() and #undoDoc.layers==1)
        assert(undoDoc:undo())
        assert(undoDoc:redo() and undoDoc:redo())
        assert(#undoDoc.layers==2 and
            undoDoc.layers[1].canvas:newImageData(1,1,200,125,1,1):getPixel(0,0)>0.5,
            "Historico misto de tinta/camada divergiu")
        assert(undoDoc:undo())
        undoDoc:beginStrokeHistory()
        assert(undoDoc:historyStats().redo==0,
            "Nova pincelada nao limpou historico de refazer")
        -- Structural history must share unchanged canvases/masks,
        -- detaching only on later pixel edits (copy-on-write).
        local cow=Doc.new(384,384,"Historico estrutural COW")
        local original=cow.layers[1].canvas
        local firstInk=Brush.beginStroke(original)
        Brush.segment(original,84.5,82.5,84.5,82.5,
            {0.94,0.12,0.08},24,1,false,firstInk)
        local oldR,oldG,oldB=original:newImageData(1,1,84,82,1,1):getPixel(0,0)
        cow:toggleLayer(1)
        cow:toggleLayer(1)
        assert(#cow.history==2 and
            cow.history[1].layers[1].canvas==original and
            cow.history[2].layers[1].canvas==original,
            "Snapshot de visibilidade duplicou camadas indevidamente")
        assert(cow:historyStats().bytes==0,
            "Mudancas puramente estruturais nao deveriam copiar pixels")
        cow:beginStrokeHistory()
        assert(cow:ensureLayerWritable(1))
        local detached=cow.layers[1].canvas
        assert(detached~=original and
            cow.history[2].layers[1].canvas==original,
            "Primeiro pixel modificado nao separou a imagem compartilhada")
        cow:captureStrokeRegion(84.5,82.5,84.5,82.5,24,0)
        local secondInk=Brush.beginStroke(detached)
        Brush.segment(detached,84.5,82.5,84.5,82.5,
            {0.03,0.09,0.99},24,1,false,secondInk)
        local nR,nG,nB=detached:newImageData(1,1,84,82,1,1):getPixel(0,0)
        assert(nB>nR and nB>nG,
            "Pincel apos copy-on-write nao atualizou a tela")
        local sameR,sameG,sameB=original:newImageData(1,1,84,82,1,1):getPixel(0,0)
        assert(math.abs(sameR-oldR)<0.005 and
            math.abs(sameG-oldG)<0.005 and
            math.abs(sameB-oldB)<0.005,
            "Edição sobrescreveu o canvas guardado no snapshot")
        assert(cow:historyStats().strokeCount==1 and
            cow:historyStats().fullCount==2)
        assert(cow:undo() and cow:undo() and cow:undo())
        assert(cow.layers[1].visible==true and cow.layers[1].canvas==original)
        local undoR=cow.layers[1].canvas:newImageData(1,1,84,82,1,1):getPixel(0,0)
        assert(math.abs(undoR-oldR)<0.005)
        assert(cow:redo() and cow:redo() and cow:redo())
        local doneR,doneG,doneB=cow.layers[1].canvas:
            newImageData(1,1,84,82,1,1):getPixel(0,0)
        assert(doneB>doneR and doneB>doneG,
            "Redo misto estrutural/brush nao recuperou pintura")
        assert(cow:setSelection(60,60,120,120))
        assert(cow:createLayerMask(1))
        local previousMask=cow.layers[1].mask
        local mr=previousMask:getPixel(20,20)
        assert(cow:invertLayerMask(1))
        assert(cow.layers[1].mask~=previousMask and
            cow.layers[1].mask:getPixel(20,20)>0.9 and mr<0.1,
            "Inversao de mascara alterou o buffer de historico compartilhado")
        assert(cow:undo() and cow.layers[1].mask==previousMask,
            "Undo nao recuperou a mascara intacta")
        assert(cow:redo() and cow.layers[1].mask~=previousMask,
            "Redo nao recuperou a mascara invertida")
        -- Regression: the real UI entrypoint must paint the detached Canvas
        -- after a structural checkpoint; a stale layer alias draws invisibly
        -- into the snapshot and breaks both the document and undo/redo.
        local appDoc=Doc.new(256,256,"Pincel via interface apos COW")
        local oldCanvas=appDoc.layers[1].canvas
        appDoc:toggleLayer(1)
        appDoc:toggleLayer(1)
        local uiStroke=setmetatable({
            doc=appDoc,tool="brush",zoom=1,offsetX=0,offsetY=0,
            rotation=0,brushSize=24,brushOpacity=1,stabilization=0,
            color={0.96,0.18,0.06}
        },{__index=app})
        uiStroke:strokeStart(73.5,73.5,1)
        assert(uiStroke.dragging and uiStroke.dragging.kind=="draw")
        uiStroke:strokeEnd(73.5,73.5,1)
        local newCanvas=appDoc.layers[1].canvas
        assert(newCanvas~=oldCanvas,
            "Pincel via UI nao separou Canvas guardado no historico")
        local _,_,_,paintedAlpha=newCanvas:newImageData(1,1,73,73,1,1):getPixel(0,0)
        local _,_,_,historyAlpha=oldCanvas:newImageData(1,1,73,73,1,1):getPixel(0,0)
        assert(paintedAlpha>0.5 and historyAlpha<0.01,
            "Inicio de pincelada escreveu no Canvas antigo")
        assert(appDoc:undo())
        local _,_,_,undoneAlpha=appDoc.layers[1].canvas:
            newImageData(1,1,73,73,1,1):getPixel(0,0)
        assert(undoneAlpha<0.01,"Undo da pincelada de UI falhou")
        assert(appDoc:redo())
        local _,_,_,redoneAlpha=appDoc.layers[1].canvas:
            newImageData(1,1,73,73,1,1):getPixel(0,0)
        assert(redoneAlpha>0.5,"Redo da pincelada de UI falhou")
        print("INKORA_UI_COW_BRUSH_UNDO_REDO_GPU_OK")
        -- A byte budget trims old strokes while keeping most recent undo.
        local bounded=Doc.new(384,384,"Limite logico de historico")
        bounded.historyBudgetBytes=2*128*128*4
        for pass=1,4 do
            assert(bounded:beginStrokeHistory())
            assert(bounded:captureStrokeRegion(45.5,45.5,45.5,45.5,8,0))
            local paint=Brush.beginStroke(bounded.layers[1].canvas)
            Brush.segment(bounded.layers[1].canvas,45.5,45.5,45.5,45.5,
                {pass/4,0.1,0.8},8,1,false,paint)
            bounded:trimHistory()
        end
        local boundedStats=bounded:historyStats()
        assert(boundedStats.steps==2 and boundedStats.tiles==2 and
            boundedStats.bytes==bounded.historyBudgetBytes and
            not boundedStats.overBudget,
            "Limite logico nao descartou pinceladas antigas")
        assert(bounded:undo() and bounded:undo() and not bounded:undo(),
            "Historico compactado permitiu desfazer operacao descartada")
        assert(bounded:redo() and bounded:redo() and not bounded:redo(),
            "Redo apos compactar historico perdeu a sequencia")
        local over=Doc.new(384,384,"Unica operacao grande")
        over.historyBudgetBytes=128*128*4
        over:beginStrokeHistory()
        assert(over:captureStrokeRegion(126.5,126.5,126.5,126.5,24,0))
        over:trimHistory()
        assert(over:historyStats().steps==1 and
            over:historyStats().overBudget and #over.history[1].tiles==4,
            "Unica operacao superior ao limite deve continuar desfazivel")
        local structuralBudget=Doc.new(384,384,"Orcamento para snapshots")
        structuralBudget.historyBudgetBytes=384*384*4+16
        local blankPixels=love.image.newImageData(384,384,"rgba8")
        for n=1,3 do structuralBudget:replaceLayerData(1,blankPixels) end
        assert(structuralBudget:historyStats().steps==1 and
            structuralBudget:historyStats().bytes==384*384*4,
            "Limite logico nao removeu snapshots estruturais antigos")
        print("INKORA_HISTORY_LOGICAL_BUDGET_GPU_OK")
        print("INKORA_STRUCTURAL_COPY_ON_WRITE_GPU_OK")
        print("INKORA_REGIONAL_BRUSH_UNDO_REDO_GPU_OK")
        print("INKORA_BOUNDED_INITIAL_COMPOSITOR_GPU_OK")
        print("INKORA_PARTIAL_COMPOSITOR_MASK_CLIP_GPU_OK")
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
        -- Per-dab pigment samples must be generated by C++ using the
        -- exact active spacing phase; source readbacks are from cached tiles.
        local native=require("src.native")
        native.resetStats()
        local pickupBefore=app.brushPigmentPickup
        local retentionBefore=app.brushPigmentRetention
        local pigmentDoc=Doc.new(192,96,"Per-dab pigment color test")
        local pigmentLayer=pigmentDoc.layers[1].canvas
        -- Paint base red then blue islands using normal C++ brushes.
        for _,paint in ipairs({
            {x0=9,x1=69,color={0.99,0.05,0.05}},
            {x0=70,x1=130,color={0.05,0.05,0.99}},
        }) do
            local primer=Brush.beginStroke(pigmentLayer,{
                tip=0,hardness=1,spacing=0.08,flow=1,
                wetness=0,pigmentLoad=1,
            })
            Brush.segment(pigmentLayer,paint.x0,45,paint.x1,45,
                paint.color,27,1,false,primer)
        end
        local painter=Brush.beginStroke(pigmentLayer,{
            tip=0,hardness=1,spacing=0.11,flow=1,
            wetness=0.95,pigmentLoad=0.65,
            pigmentPickup=0.95,pigmentRetention=0.95,
        })
        assert(painter and painter.carry,
            "Motor C++ v12 sem estado de pigmento")
        -- One large gesture spans multiple colors and crosses a tile.
        Brush.segment(pigmentLayer,12,45,180,45,{0.05,0.87,0.10},
            12,0.95,false,painter)
        assert(native.stats().pigmentSamples>50,
            "Captação nao amostrou pigmento em cada carimbo")
        local finalPixels=pigmentLayer:newImageData()
        local tailRed,tailGreen,tailBlue=finalPixels:getPixel(169,45)
        assert(tailBlue>tailRed and tailBlue>tailGreen*0.25,
            "Pincel nao transportou azul do fundo ao fim do traco")
        local carryB=tonumber(painter.carry[0].reservoir_b)
        assert(carryB>0.5,
            "Reservatorio do C++ nao conservou pigmento azul")
        app.brushPigmentPickup=pickupBefore
        app.brushPigmentRetention=retentionBefore
        print("INKORA_PER_DAB_GPU_PIGMENT_OK")
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

    -- Title -> gallery -> new canvas -> paint -> gallery -> reopen.
    local function clickStartup(kind)
        love.draw()
        for _,hit in ipairs(app.startup.hits) do
            if hit.kind==kind then
                assert(app.startup:click(hit.x+hit.w/2,hit.y+hit.h/2),
                    "Botao nao clicavel: "..kind)
                return
            end
        end
        error("Botao nao encontrado: "..kind)
    end
    app.screen="home"
    app.startup:refreshGallery()
    clickStartup("open-gallery")
    assert(app.screen=="gallery","Inicio nao abriu galeria")
    clickStartup("tool-plus")
    assert(app.screen=="gallery" and
        app.startup.galleryModal.kind=="new",
        "Novo Canvas deveria ser um painel sobre a galeria")
    clickStartup("preset-11")
    assert(app.startup.draft.width=="256" and
        app.startup.draft.height=="256","Preset pixel art falhou")
    assert(app.screen=="editor" and app.doc.width==256 and app.doc.height==256,
        "Nao entrou no editor apos criar o primeiro desenho")
    local key=app.doc.projectKey
    assert(key and love.filesystem.getInfo(
        "projects/"..key.."/manifest.txt","file"),
        "Nova obra nao foi persistida")
    assert(love.filesystem.getInfo("projects/"..key.."/preview.png","file"),
        "Miniatura da obra nao foi criada")
    local squarePreview=love.image.newImageData(
        "projects/"..key.."/preview.png")
    assert(squarePreview:getWidth()==squarePreview:getHeight(),
        "A miniatura quadrada nao preservou a proporcao 1:1")
    local px,py=app:documentToScreen(128,128)
    app:strokeStart(px,py,1)
    assert(app.dragging and app.dragging.kind=="draw")
    app:strokeEnd(px,py,1)
    app.dragging=nil
    assert(app:returnToGallery(),"Volta para galeria nao salvou")
    assert(app.screen=="gallery" and #app.startup.projects>=1)
    local found=false
    for _,item in ipairs(app.startup.projects) do
        if item.key==key then
            found=true
            assert(item.width==256 and item.height==256 and item.preview)
        end
    end
    assert(found,"Projeto criado desapareceu da galeria")
    assert(app:openArtwork(key),"Projeto nao reabriu")
    assert(app.screen=="editor" and app.doc.projectKey==key)
    local _,_,_,a=app.doc.layers[1].canvas:
        newImageData(1,1,128,128,1,1):getPixel(0,0)
    assert(a>0.2,"Pintura nao persistiu entre galeria e editor")
    print("INKORA_HOME_GALLERY_CREATE_REOPEN_GPU_OK")

    -- Gallery parity: thumbnail opens a detail first; Edit reopens the
    -- native canvas. Metadata, duplication and trash retain raster bytes.
    local savedDoc=require("src.document")
    assert(app:returnToGallery())
    love.draw()
    local galleryHit=nil
    for _,hit in ipairs(app.startup.hits) do
        if hit.kind:match("^gallery%-art%-") then
            galleryHit=hit
            break
        end
    end
    assert(galleryHit,"Galeria nao desenhou miniaturas clicaveis")
    assert(app.startup:click(galleryHit.x+galleryHit.w/2,
        galleryHit.y+galleryHit.h/2))
    assert(app.startup.galleryDetailKey,
        "Miniatura deveria abrir visualizacao ampliada antes de editar")
    love.draw()
    clickStartup("gallery-edit")
    assert(app.screen=="editor","Botao Editar nao abriu o motor de pintura")
    assert(app:returnToGallery())
    app.startup.galleryDetailKey=key

    -- % must survive Lua gsub replacement; renaming cannot alter layers.
    app.startup:galleryRename()
    assert(app.startup.galleryModal.kind=="rename")
    app.startup.galleryModal.value="Arte 100% original"
    app.startup:galleryConfirmRename()
    assert(not app.startup.galleryModal)
    assert(app.startup:galleryProject(key).name=="Arte 100% original")
    local renamed=savedDoc.load(key)
    assert(renamed.name=="Arte 100% original")
    local _,_,_,renamedAlpha=renamed.layers[1].canvas:
        newImageData(1,1,128,128,1,1):getPixel(0,0)
    assert(renamedAlpha>0.2,"Renomear modificou pixels")

    app.startup:galleryDuplicate()
    local copied=app.startup.galleryDetailKey
    assert(copied and copied~=key and
        love.filesystem.getInfo("projects/"..copied.."/manifest.txt","file"),
        "Duplicar nao preservou projeto original")
    local copyDoc=savedDoc.load(copied)
    assert(copyDoc.width==256 and copyDoc.height==256)
    local _,_,_,copyAlpha=copyDoc.layers[1].canvas:
        newImageData(1,1,128,128,1,1):getPixel(0,0)
    assert(copyAlpha>0.2,"Duplicar perdeu a pintura")
    assert(love.filesystem.getInfo("projects/"..key.."/manifest.txt","file"),
        "Duplicar apagou o original")

    app.startup:galleryAskTrash()
    assert(app.startup.galleryModal.kind=="trash",
        "Lixeira nao pediu confirmacao")
    love.draw()
    clickStartup("modal-cancel")
    assert(love.filesystem.getInfo("projects/"..copied.."/manifest.txt","file"),
        "Cancelar remocao alterou arquivos")
    app.startup:galleryAskTrash()
    app.startup:galleryTrashConfirmed()
    assert(not love.filesystem.getInfo("projects/"..copied),
        "Obra excluida permaneceu ativa")
    assert(love.filesystem.getInfo("deleted/"..copied.."/manifest.txt","file"),
        "A copia de seguranca da lixeira nao existe")
    app.startup:galleryRestore()
    assert(love.filesystem.getInfo("projects/"..copied.."/manifest.txt","file"),
        "Restaurar lixeira nao recuperou obra")

    app.startup.galleryDetailKey=nil
    app.startup:galleryToggleSelection()
    assert(app.startup.gallerySelecting)
    app.startup:galleryOpenDetail(key)
    assert(app.startup.gallerySelected[key],
        "Selecionar nao marcou miniatura")
    love.draw()
    clickStartup("gallery-select")
    assert(not app.startup.gallerySelecting)
    assert(not app.startup.gallerySelected[key])
    print("INKORA_GALLERY_DETAIL_RENAME_DUPLICATE_TRASH_RESTORE_GPU_OK")

    -- End-to-end group management: + -> New Folder, nested folder,
    -- pointer drag into a group, persisted memberships, move out.
    clickStartup("tool-plus")
    clickStartup("new-folder")
    assert(app.startup.galleryModal==nil,
        "Criacao de pasta nao deveria exigir nome antes")
    local allFolders=app.startup.folders:children("")
    local group=allFolders[#allFolders].id
    assert(group and app.startup.folders:name(group):match("^Nova Pasta"),
        "Pasta nao ganhou nome automatico")
    app.startup:galleryOpenFolder(group)
    app.startup:galleryAskRenameFolder()
    app.startup.galleryModal.value="Minhas artes"
    assert(app.startup:galleryRenameFolder())
    app.startup.galleryFolder=""
    app.startup:refreshGallery()
    love.draw()
    local folderHit,artHit
    for _,hit in ipairs(app.startup.hits) do
        if hit.kind:match("^gallery%-folder%-") then folderHit=hit end
        if hit.kind:match("^gallery%-art%-") then artHit=hit end
    end
    assert(folderHit and artHit,
        "Grupo e desenho precisam aparecer juntos na galeria")
    assert(app.startup:pointerPressed(artHit.x+artHit.w/2,artHit.y+artHit.h/2))
    assert(app.startup.galleryDrag and not app.startup.galleryDrag.active)
    app.startup.galleryDrag.started=love.timer.getTime()-0.6
    app.startup:pointerMoved(folderHit.x+folderHit.w/2,folderHit.y+folderHit.h/2)
    app.startup:pointerReleased(folderHit.x+folderHit.w/2,folderHit.y+folderHit.h/2)
    local groupedCount=0
    for _,p in ipairs(app.startup.projects) do
        if app.startup.folders:location(p.key)==group then
            groupedCount=groupedCount+1
        end
    end
    assert(groupedCount==1,"Arrastar desenho nao inseriu no grupo")
    assert(app.startup:galleryOpenFolder(group))
    app.startup:galleryAskFolder()
    local children=app.startup.folders:children(group)
    local child=children[#children].id
    assert(app.startup.folders:parent(child)==group,
        "Criacao de subpastas nao funciona")
    app.startup:galleryAskRenameFolder()
    app.startup.galleryModal.value="Arte final"
    assert(app.startup:galleryRenameFolder())
    assert(app.startup.folders:name(group)=="Arte final")
    local savedGroup=require("src.gallery_folders").new()
    assert(savedGroup:name(group)=="Arte final" and
        savedGroup:parent(child)==group,
        "Grupos nao persistiram entre sessoes")
    app.startup.folders:moveProjects({key},child)
    assert(app.startup.folders:location(key)==child)
    local insideCopy=savedDoc.load(key)
    assert(insideCopy.width==256 and insideCopy.height==256,
        "Mover para pasta alterou arquivo de pintura")
    app.startup.folders:moveProjects({key},"")
    assert(app.startup.folders:location(key)=="",
        "Nao foi possivel tirar a obra do grupo")
    app.startup:galleryOpenFolder(child)
    clickStartup("tool-plus")
    assert(app.startup.galleryModal and app.startup.galleryModal.kind=="new")
    clickStartup("new-focus-width")
    app.startup.draft.width="320"
    clickStartup("new-focus-height")
    app.startup.draft.height="480"
    clickStartup("create-artwork")
    assert(app.screen=="editor" and app.doc.width==320 and app.doc.height==480,
        "Dimensoes personalizadas nao criaram o canvas esperado")
    local insideKey=app.doc.projectKey
    assert(app.startup.folders:location(insideKey)==child,
        "Novo desenho nao foi criado dentro do grupo aberto")
    assert(app:returnToGallery())
    assert(app.startup.galleryFolder==child,
        "Retorno ao editor perdeu o grupo de origem")
    app.startup.galleryFolder=""
    app.startup:refreshGallery()
    print("INKORA_GALLERY_CREATE_NEST_MOVE_DRAG_OK")

    -- Real New overlay: edit custom resolution, adjust quality and create.
    app.startup:openGallery(app)
    clickStartup("tool-plus")
    assert(app.startup.galleryModal.kind=="new")
    clickStartup("new-quality-9")
    assert(app.startup.galleryModal.quality>0.8)
    love.draw()
    local sliderHit
    for _,hit in ipairs(app.startup.hits) do
        if hit.kind=="new-slider-width-5" then sliderHit=hit;break end
    end
    assert(sliderHit,"Slider continuo de largura nao localizado")
    local sx=sliderHit.x+sliderHit.w/2
    local sy=sliderHit.y+sliderHit.h/2
    assert(app.startup:pointerPressed(sx,sy))
    local before=tonumber(app.startup.draft.width)
    app.startup:pointerMoved(sx+65,sy)
    app.startup:pointerReleased(sx+65,sy)
    assert(tonumber(app.startup.draft.width)>before and
        not app.startup.newSliderDrag,
        "Arrastar slider nao alterou a largura continuamente")
    clickStartup("new-focus-width")
    love.textinput("768")
    assert(app.startup.draft.width=="768",
        "Tocar largura deveria substituir o valor existente")
    clickStartup("new-focus-height")
    love.textinput("900")
    assert(app.startup.draft.height=="900",
        "Tocar altura deveria substituir o valor existente")
    clickStartup("create-artwork")
    assert(app.screen=="editor" and app.doc.width==768 and
        app.doc.height==900,"Campos L/A e OK nao definiram o canvas")
    assert(app:returnToGallery())
    print("INKORA_NEW_CANVAS_CUSTOM_RESOLUTION_QUALITY_OK")

    -- Gallery PNG drag/drop must create a native editable artwork, not a
    -- mere image preview or replace existing documents.
    local data=love.image.newImageData(64,64)
    data:setPixel(12,12,0.92,0.1,0.21,1)
    local bytes=data:encode("png"):getString()
    local virtualPNG={
        getFilename=function()return "C:"..string.char(92).."artes"..
            string.char(92).."importada.png" end,
        open=function()end,read=function()return bytes end,close=function()end
    }
    assert(app:importGalleryPNG(virtualPNG),"PNG nao entrou na galeria")
    assert(app.screen=="editor" and app.doc.width==64 and app.doc.height==64)
    assert(app.doc.projectKey and app.doc.layers[2],
        "PNG nao foi preservado como camada editavel")
    assert(app:returnToGallery())
    -- The imported original was a square. Its gallery preview must be too.
    local squareImport=love.image.newImageData(
        "projects/"..app.doc.projectKey.."/preview.png")
    assert(squareImport:getWidth()==squareImport:getHeight(),
        "Miniatura da importacao 1:1 foi distorcida")
    -- Portrait preview: rendered content should fill a portrait PNG,
    -- rather than the old hard-coded 320x208 landscape card.
    local previewDoc=savedDoc.new(400,550,"Teste vertical")
    previewDoc:save("Teste vertical")
    local portraitPreview=love.image.newImageData(
        "projects/"..previewDoc.projectKey.."/preview.png")
    assert(portraitPreview:getHeight()>portraitPreview:getWidth(),
        "Miniatura vertical foi exportada em formato horizontal")
    assert(math.abs(portraitPreview:getWidth()/
        portraitPreview:getHeight()-400/550)<0.015,
        "Proporcao da miniatura vertical diverge da obra")
    -- Upgrade an existing user's old postcard preview transparently, while
    -- retaining the original painted layers / native project file.
    local legacyCanvas=love.graphics.newCanvas(320,208,{format="rgba8"})
    local legacyPNG=legacyCanvas:newImageData():encode("png"):getString()
    assert(love.filesystem.write(
        "projects/"..previewDoc.projectKey.."/preview.png",legacyPNG))
    app.startup:refreshGallery()
    local legacyEntry=app.startup:galleryProject(previewDoc.projectKey)
    local migrated=app.startup:thumbnail(legacyEntry)
    assert(migrated and migrated:getHeight()>migrated:getWidth(),
        "Miniatura antiga nao foi atualizada automaticamente")
    local preserved=savedDoc.load(previewDoc.projectKey)
    assert(preserved.width==400 and preserved.height==550,
        "Atualizar preview alterou o projeto original")
    print("INKORA_LEGACY_GALLERY_PREVIEW_MIGRATION_GPU_OK")
    print("INKORA_ASPECT_CORRECT_GALLERY_PREVIEWS_GPU_OK")
    print("INKORA_GALLERY_PNG_IMPORT_NATIVE_DOCUMENT_OK")

    -- Mock a valid IPV log containing a REAL PNG composited snapshot.
    -- Verify the gallery can read the format without copying any original
    -- ibisPaint code or falsely reconstructing text/layer history.
    local function be16(v)
        return string.char(math.floor(v/256)%256,v%256)
    end
    local function be32(v)
        return string.char(math.floor(v/16777216)%256,
            math.floor(v/65536)%256,math.floor(v/256)%256,v%256)
    end
    local function record(major,minor,payload)
        return be16(major)..be16(minor)..be32(#payload)..payload..
            be32((4294967296-(#payload+8))%4294967296)
    end
    local head=record(0x100,0x100,
        string.rep("\0",8)..be32(64)..be32(64))
    local snap=record(0x100,0x500,
        string.rep("\0",8)..be32(0xffffffff)..be32(0)..
        be16(0)..be32(#bytes)..bytes)
    local ipvBytes=head..snap
    local mockIPV={
        getFilename=function()
            return "C:"..string.char(92).."desenhos"..
                string.char(92).."estudo.ipv"
        end,
        getSize=function()return #ipvBytes end,
        open=function()end,
        read=function()return ipvBytes end,
        close=function()end,
    }
    assert(app:importGalleryIPV(mockIPV),"IPV valido nao importou")
    assert(app.screen=="editor" and app.doc.width==64 and
        app.doc.height==64 and app.doc.name=="estudo",
        "Imagem composta nao foi convertida em obra Inkora")
    assert(#app.doc.layers==2,"IPV nao deveria inventar camadas nativas")
    local originalKey=app.doc.projectKey
    local corrupted=ipvBytes:sub(1,-2)
    local badIPV={
        getFilename=mockIPV.getFilename,
        getSize=function()return #corrupted end,
        open=function()end,
        read=function()return corrupted end,
        close=function()end,
    }
    assert(not app:importGalleryIPV(badIPV),"IPV truncado foi aceito")
    assert(app.doc.projectKey==originalKey,
        "Falha IPV nao deve substituir o desenho aberto")
    assert(app:returnToGallery())
    print("INKORA_IPV_FLATTENED_IMPORT_AND_CORRUPTION_REJECTED_GPU_OK")

    -- The RPNG mask is sparse and bottom-up. A three-pixel 2x2 dirty
    -- rectangle at (10, screen y=42) should map exactly as follows:
    -- top row: green, blue; bottom row: red, transparent.
    local packed=love.image.newImageData(16,1)
    packed:setPixel(0,0,1,0,0,1)
    packed:setPixel(1,0,0,1,0,1)
    packed:setPixel(2,0,0,0,1,1)
    local packedPNG=packed:encode("png"):getString()
    local spans=be16(0)..be16(1)..be16(1)..be16(2)
    local rpng="RPNG"..be32(45)..be32(0)..
        be32(1)..be32(1)..string.char(0)..
        be32(2)..be32(2)..be32(10)..be32(20)..
        be32(16)..be32(1)..be32(13)..be32(0)..
        be32(#spans)..spans..be32(#packedPNG)..packedPNG
    local raster=record(0x100,0x500,
        string.rep("\0",8)..be32(7)..be32(1)..
        be16(0)..be32(#rpng)..rpng)
    -- IPV appends 0300/0600 layer-list operations; the second ID group
    -- is the active "after" set, not the old IDs or a numeric ID sort.
    -- These are SYNTHETIC fixtures; Windows 14.1.2 remains unverified.
    local function groupOfIds(ids)
        local chunks={}
        for _,id in ipairs(ids) do
            chunks[#chunks+1]=record(0x0300,0x0603,be32(id))
        end
        chunks[#chunks+1]=record(0x0300,0x0603,be32(0xffffffff))
        return be32(#chunks)..table.concat(chunks)
    end
    local rasterSecond=record(0x100,0x500,
        string.rep("\0",8)..be32(2)..be32(1)..
        be16(0)..be32(#rpng)..rpng)
    local layerOrder=record(0x0300,0x0600,
        string.rep("\0",12)..groupOfIds({7,2})..
        groupOfIds({2,7})..be32(0))
    local IPVReader=require("src.ibis_ipv")
    local orderedInfo=IPVReader.inspect(
        head..raster..rasterSecond..layerOrder..snap)
    assert(orderedInfo.layerOrderSource=="layer-list" and
        #orderedInfo.rasterLayers==2 and
        orderedInfo.rasterLayers[1].id==2 and
        orderedInfo.rasterLayers[2].id==7 and
        not orderedInfo.incompleteRaster,
        "A ultima lista IPV nao ordenou as camadas ativas")
    local deletion=record(0x0300,0x0600,
        string.rep("\0",12)..groupOfIds({2,7})..
        groupOfIds({7})..be32(0))
    local afterDelete=IPVReader.inspect(
        head..raster..rasterSecond..layerOrder..deletion..snap)
    assert(#afterDelete.rasterLayers==1 and
        afterDelete.rasterLayers[1].id==7 and
        not afterDelete.incompleteRaster,
        "Camada removida foi ressuscitada por snapshot antigo")
    local missingActive=record(0x0300,0x0600,
        string.rep("\0",12)..groupOfIds({7})..
        groupOfIds({7,9})..be32(0))
    local missingInfo=IPVReader.inspect(
        head..raster..missingActive..snap)
    assert(missingInfo.incompleteRaster,
        "Lista de camada sem snapshot deveria ativar fallback achatado")
    local unknownList=record(0x0300,0x0600,
        string.rep("\0",12)..be32(1000)..string.rep("\0",8))
    local fallbackOrder=IPVReader.inspect(
        head..raster..rasterSecond..unknownList..snap)
    assert(fallbackOrder.layerOrderSource=="id-estimate" and
        #fallbackOrder.rasterLayers==2 and
        fallbackOrder.rasterLayers[1].id==2,
        "Registro de ordem desconhecido deveria preservar fallback")
    print("INKORA_IPV_LAYER_LIST_ORDER_AND_DELETION_SYNTHETIC_OK")

    -- The flattened snapshot must match the RPNG sample when normal-alpha
    -- layers are imported. The old synthetic 'snap' had unrelated pixels.
    local compositePixels=love.image.newImageData(64,64,"rgba8")
    compositePixels:setPixel(10,42,0,1,0,1)
    compositePixels:setPixel(11,42,0,0,1,1)
    compositePixels:setPixel(10,43,1,0,0,1)
    local compositePNG=compositePixels:encode("png"):getString()
    local matchedSnap=record(0x100,0x500,
        string.rep("\0",8)..be32(0xffffffff)..be32(0)..
        be16(0)..be32(#compositePNG)..compositePNG)

    local visual=require("src.ipv_visual_verify")
    local pixelRed=love.image.newImageData(1,1,"rgba8")
    pixelRed:setPixel(0,0,1,0,0,1)
    local pixelBlue=love.image.newImageData(1,1,"rgba8")
    pixelBlue:setPixel(0,0,0,0,1,1)
    local referenceBlue=love.image.newImageData(2,2,"rgba8")
    referenceBlue:setPixel(0,0,0,0,1,1)
    local overlapping={
        {id=1,imageData=pixelRed,x=0,y=0},
        {id=2,imageData=pixelBlue,x=0,y=0},
    }
    local normalResult=visual.assess(overlapping,referenceBlue)
    assert(normalResult.matches and normalResult.direction=="normal" and
        normalResult.checked==4 and normalResult.informative==1,
        "Composicao normal deveria coincidir com a referencia azul")
    local referenceRed=love.image.newImageData(2,2,"rgba8")
    referenceRed:setPixel(0,0,1,0,0,1)
    local reverseResult=visual.assess(overlapping,referenceRed)
    assert(reverseResult.matches and reverseResult.direction=="reverse",
        "Inversao somente deve ocorrer quando a ordem oposta bate com PNG")
    local referenceGreen=love.image.newImageData(2,2,"rgba8")
    referenceGreen:setPixel(0,0,0,1,0,1)
    local mismatch=visual.assess(overlapping,referenceGreen)
    assert(not mismatch.matches and mismatch.status=="mismatch",
        "Blend ou camadas invalidas devem ser detectados")
    print("INKORA_IPV_VISUAL_NORMAL_REVERSE_MISMATCH_GPU_OK")

    local rpngBytes=head..raster..matchedSnap
    local rasterIPV={
        getFilename=function()return "C:"..string.char(92).."camadas.ipv" end,
        getSize=function()return #rpngBytes end,
        open=function()end,
        read=function()return rpngBytes end,
        close=function()end,
    }
    local loaded=app:importGalleryIPV(rasterIPV)
    assert(loaded and app.doc.name=="camadas",
        "Projeto IPV RPNG nao importou")
    assert(#app.doc.layers==2,
        "Uma camada raster deve coexistir com referencia composta oculta")
    assert(not app.doc.layers[1].visible and app.doc.layers[2].visible,
        "Referencia deve ficar oculta e camada RPNG editavel")
    local native=app.doc.layers[2].canvas
    local function pixelAt(x,y)
        return {native:newImageData(1,1,x,y,1,1):getPixel(0,0)}
    end
    local red=pixelAt(10,43)
    local green=pixelAt(10,42)
    local blue=pixelAt(11,42)
    local clear=pixelAt(11,43)
    assert(red[1]>0.9 and red[2]<0.1 and red[4]>0.95,
        "Pixel vermelho RPNG saiu da linha de baixo")
    assert(green[2]>0.9 and green[1]<0.1 and green[4]>0.95,
        "Pixel verde RPNG saiu da linha de cima")
    assert(blue[3]>0.9 and blue[1]<0.1 and blue[4]>0.95,
        "Pixel azul RPNG foi invertido")
    assert(clear[4]<0.05,"Mascara RPNG perdeu o buraco transparente")
    local importedKey=app.doc.projectKey
    assert(app:returnToGallery())
    local restored=savedDoc.load(importedKey)
    assert(#restored.layers==2 and not restored.layers[1].visible)
    local persisted=restored.layers[2].canvas:
        newImageData(1,1,10,42,1,1)
    local _,greenValue= persisted:getPixel(0,0)
    assert(greenValue>0.9,"Camada raster nao sobreviveu ao salvamento")
    print("INKORA_IPV_SPARSE_RPNG_BOTTOM_UP_IMPORT_GPU_OK")

    -- Deliberately inconsistent flattened PNG must import ONLY that PNG,
    -- not silently expose pixels that ibisPaint did not render.
    local mismatchedBytes=head..raster..snap
    local mismatchedIPV={
        getFilename=rasterIPV.getFilename,
        getSize=function()return #mismatchedBytes end,
        open=function()end,read=function()return mismatchedBytes end,
        close=function()end,
    }
    assert(app:importGalleryIPV(mismatchedIPV))
    assert(#app.doc.layers==2 and app.doc.layers[1].visible,
        "IPV visualmente divergente deveria abrir so PNG achatado")
    assert(app:returnToGallery())
    print("INKORA_IPV_VISUAL_MISMATCH_SAFE_FALLBACK_GPU_OK")

    -- An invalid span table must not become a fake raster layer. It is
    -- acceptable to fall back to the proven flattened composite instead.
    local broken=rpng:sub(1,58)..be16(6)..rpng:sub(61)
    local badRaster=record(0x100,0x500,
        string.rep("\0",8)..be32(7)..be32(1)..
        be16(0)..be32(#broken)..broken)
    local fallbackBytes=head..badRaster..matchedSnap
    local fallbackIPV={
        getFilename=rasterIPV.getFilename,
        getSize=function()return #fallbackBytes end,
        open=function()end,read=function()return fallbackBytes end,
        close=function()end,
    }
    assert(app:importGalleryIPV(fallbackIPV))
    assert(#app.doc.layers==2 and app.doc.layers[1].visible,
        "RPNG invalido deveria usar apenas composicao achatada")
    assert(app:returnToGallery())
    print("INKORA_IPV_BAD_RPNG_SAFE_FLATTENED_FALLBACK_GPU_OK")

    -- Folder information must be a bottom sheet with editable title.
    assert(app.startup:galleryOpenFolder(group))
    assert(app.startup:galleryFolderInfo())
    assert(app.startup.galleryModal.kind=="folder-info")
    app.startup.galleryModal.value="Pasta de estudos"
    assert(app.startup:galleryConfirmFolderInfo())
    assert(app.startup.folders:name(group)=="Pasta de estudos")
    app.startup.galleryFolder=""
    print("INKORA_FOLDER_INFO_RENAME_OK")
    print("INKORA_GPU_SMOKE_OK")
end

return {run=run}
