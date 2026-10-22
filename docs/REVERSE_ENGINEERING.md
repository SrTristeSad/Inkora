# Inkora — auditoria de engenharia reversa funcional (etapa 1)

> **Metodo:** examinar **comportamento documentado publicamente** do ibisPaint e **codigo aberto** dos projetos ReveriePaint e Klecks. Esta fase **nao** envolveu inspecao de binario, trafego privado ou instrumentacao do ibisPaint. Nao extrapolar observacoes para alegacoes de paridade.

## Fontes verificadas

1. ibisPaint, [Details of Brush Parameters](https://ibispaint.com/lecture/index.jsp?lang=en&no=118): espessura, opacidade, brush pattern, spacing, opacity saturation, fade, dinamica por pressao/velocidade, textura e modos de mesclagem. **Evidencia: documentacao oficial.**
2. ibisPaint, [Stabilizer](https://ibispaint.com/lecture/index.jsp?lang=en&no=50): modos de correcao em tempo real e apos levantar a caneta; pode ser especifico por pincel. **Evidencia: documentacao oficial.**
3. ibisPaint, [Layer Window Details](https://ibispaint.com/lecture/index.jsp?no=156): clipping, alpha lock, opacidade, pastas/transformacao, exportar camada PNG. **Evidencia: documentacao oficial.**
4. [ReveriePaint/CMakeLists.txt](https://github.com/LanRhyme/ReveriePaint/blob/main/app/src/main/cpp/CMakeLists.txt): compilacao nativa C++17 com Krita/Qt, JNI.
5. [ReveriePaint/ReverieCoreStroke.cpp](https://github.com/LanRhyme/ReveriePaint/blob/main/app/src/main/cpp/ReverieCoreStroke.cpp): eventos touch start/move/end, pressao, stroke batching/undo e integracao Krita.
6. [ReveriePaint/reverie_jni_brush.cpp](https://github.com/LanRhyme/ReveriePaint/blob/main/app/src/main/cpp/reverie_jni_brush.cpp) e [ReverieCoreBridge.kt](https://github.com/LanRhyme/ReveriePaint/blob/main/app/src/main/java/com/reverie/paint/core/ReverieCoreBridge.kt): ponte Kotlin/JNI/C++.
7. [Klecks/pen-brush.ts](https://github.com/bitbof/klecks/blob/main/src/app/script/klecks/brushes/pen-brush.ts): parametrizacao de brush alpha, spacing, input por pressao, selecao e historico.
8. [Klecks/layer-compositor.ts](https://github.com/bitbof/klecks/blob/main/src/app/script/klecks/canvas/layer-compositor.ts): composicao em Canvas2D com opacidade, mix mode e grupos.
9. [LÖVE Data:getFFIPointer](https://love2d.org/wiki/Data:getFFIPointer): ponte segura apenas sob contrato correto de posse e formato; suportada desde LÖVE 11.3.

## Matriz de equivalencia (ainda **nao** validada visualmente)

| Requisito | Comportamento publicamente documentado | Implementado no Inkora | Teste comparativo pendente |
|---|---|---|---|
| Traco solido | Espessura, opacidade e padrao do pincel | **Motor C++ v1:** dabs circulares RGBA8, blend straight-alpha | Trajetoria, cobertura de borda, opacidade e velocidade |
| Brush spacing | Intervalo proporcional a espessura | **C++ v1:** spacing interno (0.18) | Repetibilidade em curvas, zoom e baixa velocidade |
| Pressure dynamics | Espessura/opacidade/blur configuraveis por pressao | **API C++ aceita pressao** e interpola espessura; entrada real da caneta nao integrada | Curvas de tablet, jitter, fade |
| Hardness/softness | Parametros de ponta/formato | **C++ v1:** dureza/antialias de ponta circular em API | Dureza percetiva, mascaras/brush shapes |
| Estabilizador | Tempo real / apos o traco | **Lua:** suavizacao simples em tempo real | Comparacao real de trajetoria e temporizacao |
| Camadas | Opacidade, clipping, alpha lock, blending | **Lua:** camadas com opacidade basica | Clipping, grupos, masking, blend modes |
| Eraser | Ferramenta de apagar | **C++ v1:** reducao de alpha por cobertura | Precisao da borracha, soft edge, undo |
| Selecao | Selecao de area/camada | Nao implementado | Selecoes raster/alpha, bordas |
| Historico | Undo/redo de operacoes | **Lua:** snapshots do documento | Memoria, granularidade, estabilidade |
| Salvar arquivos | Exportacao e projetos nativos | **Lua:** PNG e manifesto editavel proprietario | formatos, cores, transparencia e round-trip |

### Limites honestos

- O motor nativo **nao reutiliza codigo nem assets** do ibisPaint, ReveriePaint ou Klecks. Algoritmos iniciais independentes. Licenca GPL-3.0 do ReveriePaint/Krita e MIT do Klecks devem ser avaliadas antes de copiar/integrar qualquer linha de codigo externo.
- C++ recebe buffers **RGBA8 straight alpha** e pinta sobre a camada ativa. LuaJIT FFI fornece o ponteiro para a memoria do `ImageData`. O LÖVE e responsavel pelo upload para Canvas GPU. O buffer nunca pode ser realocado enquanto a funcao nativa executa.
- Inkora v5: composição de camadas em C++ via Porter-Duff RGBA8, modos Normal, Multiply, Screen, Add e Overlay, salvamento de modos no manifesto existente e exportação da imagem composta. **Limitação documentada:** uma alteração com modos especiais força leitura integral das camadas visíveis na recomposição CPU. Ainda faltam grupos, máscaras, clipping e alpha lock. A equivalência visual com ibisPaint ainda não foi medida.
- O Inkora v4 acrescenta **máscara de ponta PNG** (8 bits), fluxo multiplicativo por aplicação de ponta e pressão sobre a opacidade. A máscara pertence ao LuaJIT, é referenciada com ponteiro e permanece viva durante o traço. A importação aceita transparência ou luminância invertida quando a imagem é inteiramente opaca. Não equivale aos motores úmidos, de aquarela ou aos formatos nativos do ibisPaint. A entrada de pressão de toque depende do aparelho e não é integração WinTab/Windows Ink.
- O Inkora v3 introduz **pontas proceduralmente desenhadas** (circular, chata orientada e granulado em coordenadas de pixel), sem reaproveitar código ou pincéis proprietários das referências. Não há ainda importação de bitmap de ponta ou equivalência medida com o ibisPaint.
- **Inkora atual:** o núcleo C++ v3 retorna dirty rectangles, e o gerenciador LuaJIT divide as camadas em blocos de 128×128 pixels. Ele lê apenas os blocos necessários, mantém-nos entre traços e envia pequenos recortes modificados para GPU. Blocos de camadas recém-criadas e transparentes começam sem readback. Operações Lua fora do C++ invalidam o cache para preservar o conteúdo. Cada tile recebe o mesmo estado inicial de espaçamento por segmento e o estado global avança uma única vez. **Limites:** CPU ainda não fornece um compositor nativo, pressão física de mesa e medição de latência. O cache agora tem limite de 96 tiles por camada (configurável para testes), e tiles pintados expulsos são relidos da GPU ao voltar a ser usados. Ainda faltam limites globais, medição de RAM/VRAM e descarte de recursos.
- API nativa: `inkora_core_api_version() == 1`; `inkora_core_stroke(InkoraStroke*)`; valida tamanho/stride/bytes, finitude e intervalo de coordenadas. Sem chamadores nao confiaveis e sem cache de ponteiros em C++.
- **Nao foi feita engenharia reversa de codigo proprietario** nem comparacao lado a lado com o ibisPaint instalado; a matriz e um plano baseado em material publico e nos repositorios citados.

## Arquitetura de implementacao

```text
Lua / LÖVE: UI, gestos, camadas, documentos
    |
    +--> src/brush.lua
            |
            +--> src/native.lua (LuaJIT FFI) --> inkora_core.dll / .so (C++ RGBA8)
            |                                      |
            |                                      +--> stamps / alpha / pressure
            +--> antigo pincel Lua se DLL nao estiver presente
```

**Próximo experimento técnico mensurável:** benchmark e orçamento de memória para 1280×800 e 4096×4096, limite/LRU de tiles, histórico de pressões, teste da ponte Windows 64 bits, pressão real de mesa digitalizadora e undo/redo. O LÖVE já recebe o retângulo mínimo envolvente da área marcada como suja e os controles de dureza/espaçamento são expostos na UI.
