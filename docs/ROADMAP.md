# Inkora — Plano de desenvolvimento vinculante

> **Objetivo:** equivalencia funcional progressiva com o ibisPaint, por estudo do comportamento observavel; Lua + C++ nativo, Windows primeiro, Android depois. Consulte [AGENTS.md](../AGENTS.md).

## Estado verificado do repositorio

| Componente | Estado atual |
| --- | --- |
| Protótipo desktop Lua/LÖVE (canvas e UI) | Biblioteca visual, prévia dinâmica C++, perfis de pincel editáveis persistentes, HSV, miniaturas, favoritos e canvas rotacionável; teste manual Windows pendente |
| Pincel, borracha, formas, balde, camadas e projeto básico | Protótipos Lua; não equivalem ao ibisPaint |
| Engenharia reversa funcional documentada do ibisPaint | **Matriz inicial baseada em documentação pública; medição lado a lado pendente** |
| Auditoria detalhada de ReveriePaint e Klecks | **Auditoria inicial dos arquivos C++/JNI e TS de pincel/camadas; aprofundar ainda** |
| Motor gráfico Inkora em C++ | **C++ ABI v8: orientação de pontas chatas/PNG pela tangente da trajetória; validar CI** |
| Ponte Lua ↔ C++ com testes | **LuaJIT FFI ABI v8, estado direcional por segmento, blend, máscaras e clipping** |
| Build Windows integrando C++ e Lua | **CI configurado para DLL C++ + LÖVE; build automático. Execução/mesa real Windows ainda sem validação** |
| Entrada de caneta Windows | **Ponte WinTab experimental via LuaJIT FFI, sem interceptar SDL, com curvas de pressão e fallback; teste com driver físico pendente** |
| Android sobre o mesmo núcleo | **Futuro** |

## Ordem de execução

### Fase 1 — Fundacao correta (proxima prioridade)
- [x] Criar **docs/REVERSE_ENGINEERING.md**, matriz de equivalencia observada do ibisPaint: gestos, desenho, resposta, layer blend e casos extremos, com evidencia e nivel de confianca.
- [x] Auditar inicialmente arquivos e APIs reais de **ReveriePaint** (C++/Krita/GPL-3.0) e **Klecks** (MIT/TypeScript) e registrar integracao possivel versus reimplementacao.
- [x] Definir uma API versionada **Lua ↔ C++** para rasterizacao em imagens RGBA, sem dependencias de Android na logica.
- [ ] Compilar modulo C++ no CI Windows e testar ponte em LÖVE/Linux (CI deve confirmar execução).
- [x] Mover **um pincel real** do prototipo Lua para C++ com trajetoria, espessura, espacamento, alpha e testes visuais/regressao. Nao remover o caminho Lua antigo antes de passar testes.

### Fase 2 — Motor de pintura
- [ ] Pincéis profissionais: interpolação avançada, textura contínua, tinta úmida, estabilização profissional completa e suporte Windows Ink/WinTab comprovado.
- [x] Ponte de leitura de pressão WinTab opcional por polling, sem substituir os eventos de posição SDL. Normalização conforme eixo do driver, curvas Leve/Linear/Firme, preferência persistida e fallback em caso de ausência de caneta.
- [ ] Testar a ponte com modelos reais de mesa no Windows, incluindo pressionar/soltar, perda de foco, duplicidade de eventos, latência e inclinação.
- [x] Primeiro estabilizador adaptativo à taxa de eventos e à velocidade do cursor (filtro de baixa passagem variável), com conclusão amostrada do traço e cursor/traço suavizado visível.
- [x] C++ v8: orientação dinâmica da ponta chata e PNG ao seguir o traço, ângulo fixo configurável e estado preservado entre tiles/eventos.
- [x] Salvar e restaurar ângulo e modo de direção em presets, mantendo leitura de configurações antigas.
- [x] A prévia em C++ também simula estabilização; teste puro Lua para variação de taxa/tremor e teste gráfico integrado ao C++.
- [x] Ponta personalizada por PNG até 512×512, máscara alfa (ou luminância invertida), com armazenamento local.
- [x] Fluxo básico por carimbo e dinâmica linear de opacidade conforme pressão, via C++ ABI v4.
- [x] Três pontas nativas iniciais (redonda, chata, granulada procedural), com API C++ v3 e testes.
- [x] Cache de tiles 128×128 com leituras regionais sob demanda, inicialização transparente e invalidação em operações Lua.
- [x] Limite de tiles em cache por camada, com LRU e recarregamento seguro após expulsão.
- [ ] Benchmark real, uso máximo de VRAM/CPU e teste prolongado com canvas grandes, incluindo blend modes que usam readbacks completos.
- [x] Compositor C++ v5 e cinco modos iniciais: Normal, Multiply, Screen, Add, Overlay; integrados à interface, undo, exportação PNG e manifesto.
- [x] Alpha Lock por camada, preservado em undo/redo e no manifesto do projeto (retrocompatível).
- [x] Seleção retangular temporária aplicada ao pincel/borracha e balde, inclusive nos limites de tiles.
- [x] Máscara por camada criada da seleção; inversão, remoção, undo/redo, persistência em PNG.
- [x] Clipping à transparência da camada imediatamente inferior, considerando máscara e opacidade, com compositor C++ v7.
- [ ] Edição/pintura direta da máscara, clipping em cadeia, grupos, composição por tiles e undo/redo eficiente.
- [ ] Seleção com laço, varinha, elipse, feathering e suporte nas ferramentas de formas.
- [ ] Selecao e transformacoes: laço, varinha, mover, redimensionar, rotacionar (retângulo básico já implementado).
- [ ] Filtros/efeitos de pintura e processamento com controle de memoria.
- [ ] Entrada de mesa digitalizadora (Windows), latencia e benchmark de tela grande.

### Fase 3 — Produto multiplataforma
- [x] Primeira reformulação visual: biblioteca de oito presets funcionais, miniaturas em camadas, seletor HSV, área de pintura central e barra de ferramentas compacta.
- [x] Favoritos persistentes na biblioteca e filtro funcional de pincéis.
- [x] Miniaturas de pincéis renderizadas com o motor C++ e cache por preset.
- [x] Prévia dinâmica, cache de um único canvas de prévia, reflexo da ponta, fluxo, pressão, opacidade, estabilização e cor selecionada.
- [x] Salvar/restaurar configuração individual de cada preset no disco, com validação dos valores e miniaturas atualizadas.
- [x] Biblioteca filtrável por categorias de pincéis, combinável com favoritos.
- [x] Inspetor lateral de largura ajustável por arraste, preservando o enquadramento do documento.
- [x] Rotação visual do canvas com mouse/pincel/seleção alinhados e zoom ancorado; sem alterar a orientação dos pixels exportados.
- [ ] Testar usabilidade da rotação com canetas digitais e gestos multitouch reais em Windows.
- [ ] Evoluir o desktop para nível profissional: dock de painéis, paleta flutuante, ajuste da textura de ponta importada, caneta digitalizadora, atalhos personalizáveis e UX validada com artistas.
- [ ] Formatos interoperáveis e documentos complexos.
- [ ] Reutilizar o mesmo nucleo C++/Lua em Android, com suporte a toque/gestos/caneta.
- [ ] Comparacao sistematica da experiencia com referencias, sem copiar marca, arte ou codigo proprietario.

## Regra de entrega

Cada iteracao deve: **apontar o item do roadmap**, produzir alteracao concreta e testavel, executar/validar build, documentar limites e publicar commit. A lista nao equivale a implementacao. Evitar adicionar apenas botoes sem melhorar o nucleo. **TRABALHA, IA.**
