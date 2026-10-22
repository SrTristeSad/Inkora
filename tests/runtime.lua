-- Executado com INKORA_TEST=1 dentro do LÖVE em um display virtual.
-- Exercita caminhos reais de GPU, IO, interface e serializacao.
local Doc=require("src.document")
local Brush=require("src.brush")
local Fill=require("src.fill")
local Native=require("src.native")

local function close(a,b,tolerance)
    return math.abs(a-b) <= (tolerance or 0.18)
end

local function run()
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
    print("INKORA_GPU_SMOKE_OK")
end

return {run=run}
