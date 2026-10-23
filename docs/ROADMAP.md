# Inkora — Plano de desenvolvimento vinculante

> **Objetivo vinculante:** **engenharia reversa funcional do ibisPaint e reproducao de seu funcionamento em Lua + C++ nativo**, nao apenas um editor inspirado ou semelhante. Documentar comportamento observado, reproduzi-lo com implementacao independente e validar por comparacao real; o desenvolvimento e incremental, mas a meta final e a paridade funcional demonstrada. Windows primeiro, Android depois. Consulte [AGENTS.md](../AGENTS.md).

## Estado verificado do repositorio

| Componente | Estado atual |
| --- | --- |
| Protótipo desktop Lua/LÖVE (canvas e UI) | Biblioteca visual, prévia dinâmica C++, perfis de pincel editáveis persistentes, HSV, miniaturas, favoritos e canvas rotacionável; teste manual Windows pendente |
| Pincel, borracha, formas, balde, camadas e projeto básico | Protótipos Lua; não equivalem ao ibisPaint |
| Engenharia reversa funcional documentada do ibisPaint | **Matriz inicial baseada em documentação pública; medição lado a lado pendente** |
| Auditoria detalhada de ReveriePaint e Klecks | **Auditoria inicial dos arquivos C++/JNI e TS de pincel/camadas; aprofundar ainda** |
| Motor gráfico Inkora em C++ | **C++ ABI v13: preserva pincel v12 e acrescenta balde contíguo em C++ com bounding box de dirty pixels; testes CI** |
| Ponte Lua ↔ C++ com testes | **LuaJIT FFI ABI v13: balde C++ por região, pincel v12 preservado; textura/direção, blend, máscaras e clipping** |
| Build Windows integrando C++ e Lua | **CI configurado para DLL C++ + LÖVE; build automático. Execução/mesa real Windows ainda sem validação** |
| Entrada de caneta Windows | **Ponte WinTab experimental via LuaJIT FFI, sem interceptar SDL, com curvas de pressão e fallback; teste com driver físico pendente** |
| Android sobre o mesmo núcleo | **Futuro** |

## Engenharia reversa de entrada — tela inicial, galeria e novo canvas

- [x] Fluxo integrado: titulo -> Minha galeria -> novo canvas -> editor -> salvar/voltar -> reabrir obra.
- [x] Tela inicial funcional com galeria, novo desenho e retomada.
- [x] Galeria com barras escuras, miniaturas responsivas alinhadas a esquerda e fundo claro, visualizacao ampliada antes de Editar, selecao, miniaturas de pastas emolduradas e atalhos. A fidelidade visual ainda depende de calibracao por capturas lado a lado. Comandos reais: criar, renomear manifesto (sem regravar layers), duplicar, exportar PNG, mover para lixeira recuperavel, restaurar ultima obra.
- [x] Janela Novo SOBRE Minha Galeria como no tutorial oficial: Pasta de criacao imediata, Importar PNG (arrastar arquivo), campos L/A com +/- e selecao, Velocidade/Qualidade e presets por proporcao e impressao; OK customizado cria a tela, preset cria imediatamente. Canvas em branco nao apresenta texto ficticio.
- [x] Teste grafico end-to-end no LÖVE com arquivo reaberto e pincelada persistida; capturas de tres telas no CI.
- [ ] Comparacao visual e de gestos lado a lado com versao concreta do ibisPaint em hardware Windows / tablet.
- [x] Grupos/pastas na galeria: menu + abre Nova pasta e Novo desenho; pastas aninhadas, renomeacao pelo titulo, mover desenhos via selecao ou arrastar, agrupar ao arrastar um desenho sobre outro, navegacao Voltar, lixeira e criacao de obra dentro do grupo. Indice persistente separado do formato INKORA1, testado em Lua e GPU.
- [ ] Ordenacao manual da galeria, mover varias pastas de uma vez, importacao direta, time-lapse, sincronizacao na nuvem e interface completa da lixeira (atualmente restaura a ultima obra).

\n## Importacao experimental de .ipv / pesquisa de interoperabilidade\n\n- [x] Auditar as fontes publicas [ipv-format (MIT)](https://github.com/fapotaa/ipv-format), [reeng-ibispaint (sem licenca identificada)](https://github.com/HatLink/reeng-ibispaint), [Rusty Painter (GPL-3.0-only)](https://github.com/Vectra777/rusty-painter) e [Toon Paint (sem licenca identificada)](https://github.com/saimoneybusiness-afk/Toon-Paint---IbisPaint-clone), registrando incompatibilidades e limites em [IBISPAINT_INTEROPERABILITY.md](IBISPAINT_INTEROPERABILITY.md).\n- [x] Leitor `src/ibis_ipv.lua` independente: valida tipos, sentinelas e tamanhos; decodifica spans, pixels e orientacao vertical RPNG em camadas Inkora; importa referencia composta oculta e usa fallback achatado para formatos desconhecidos. Testes unitarios/GPU com pixels e salvamento de camadas. Arquivo de origem preservado.\n- [ ] Validar o leitor e a importacao visual contra **varios** arquivos .ipv reais de Windows 14.1.2 e Android 14.0.11, incluindo sessoes repetidas, camadas e documentos grandes. A leitura de metadados de **uma** fixture publica real do Android passou no CI; importacao editavel e arquivos reais Windows ainda nao foram testados.
- [x] Acrescentar teste de leitura de arquivo IPV **real publico** gerado pelo ibisPaint X Android, sem redistribuir a amostra: download fixado por commit/hash no GitHub Actions, leitura pura em Lua e exportacao de relatorio de metadados sem imagens. Isso valida o container, **nao** a abertura editavel, a fidelidade de camadas ou a versao Windows.\n- [x] Leitura conservadora do ultimo registro `0300/0600` para evitar ressuscitar camadas excluidas, com validacao de grupos e sentinelas, fallback por ID e testes sinteticos de regressao. **Nao comprovado em .ipv reais.**
- [x] Comparador visual preliminar em Lua de camadas RPNG versus PNG achatado: RGBA premultiplicado, amostragem limitada, tentativa da ordem inversa e fallback seguro para PNG quando ha divergencia. Testes GPU sinteticos de sucesso, inversao e divergencia; **nao** valida comportamento com arquivos Windows reais.
- [ ] Validar fidelidade de camadas RPNG contra projetos reais, confirmar orientacao visual da ordem `0300/0600`, recuperar metadados de blend/visibilidade/opacidade; estudar texto editavel e pincel IPBZ.\n
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
- [x] C++ v9: textura determinística em coordenadas globais, dispersão e variação do diâmetro por carimbo, sem costuras entre tiles.
- [x] C++ v10: mistura de pigmentos com cores preexistentes na mesma camada, regulação de umidade e carga, com resultado seco idêntico à ABI v9.
- [x] C++ v11: reservatório do pincel com amostragem antes do segmento, captação e retenção de pigmento, mantendo continuidade entre eventos e igualdade dos resultados entre tiles.
- [x] C++ v12: API de consulta de posições dos carimbos em duas passagens, buffer validado de amostras RGBA por carimbo, reservatório atualizado a cada carimbo e mesma lista para todos os tiles.
- [x] Leitura de amostras por cache LRU de tiles, sem recapturar GPU por carimbo; instrumentação `Native.stats().pigmentSamples` e testes C++/Lua de continuidade.
- [ ] Medir desempenho/latência em documentos grandes e realizar perfis de readback e uso de memória para a nova captação.
- [x] Aba Tinta exibe mistura local versus transporte de pigmento; Aquarela usa o novo modo e os perfis antigos são compatíveis.
- [ ] Pigmento físico com captação por carimbo, transporte entre pixels e mistura com vizinhança; medir desempenho.
- [x] Aba Tinta com comparação seca/úmida renderizada em C++, controles e persistência de presets (15 campos com leitura dos 8/10/13 antigos).
- [ ] Tinta úmida com transporte entre pixels, mistura entre camadas e secagem; avaliar comparação visual com comportamento observado do ibisPaint.
- [x] Aba Textura com três sliders, visualização no motor C++ e presets compatíveis com arquivos v7/v8.
- [ ] Texturas PNG contínuas, modos de pincel úmido, deformação de ponta por inclinação e desempenho para telas grandes.
- [x] Salvar e restaurar ângulo e modo de direção em presets, mantendo leitura de configurações antigas.
- [x] A prévia em C++ também simula estabilização; teste puro Lua para variação de taxa/tremor e teste gráfico integrado ao C++.
- [x] Ponta personalizada por PNG até 512×512, máscara alfa (ou luminância invertida), com armazenamento local.
- [x] Fluxo básico por carimbo e dinâmica linear de opacidade conforme pressão, via C++ ABI v4.
- [x] Três pontas nativas iniciais (redonda, chata, granulada procedural), com API C++ v3 e testes.
- [x] Cache de tiles 128×128 com leituras regionais sob demanda, inicialização transparente e invalidação em operações Lua.
- [x] Limite de tiles em cache por camada, com LRU e recarregamento seguro após expulsão.
- [ ] Benchmark real, uso máximo de VRAM/CPU e teste prolongado com canvas grandes. A primeira composição e mudanças estruturais agora usam lotes até 512×512 (ainda percorrem todas as camadas); pinceladas atualizam regiões de 128×128. Faltam benchmarks reais de latência/memória.
- [x] Compositor C++ v5 e cinco modos iniciais: Normal, Multiply, Screen, Add, Overlay; integrados à interface, undo, exportação PNG e manifesto.
- [x] Alpha Lock por camada, preservado em undo/redo e no manifesto do projeto (retrocompatível).
- [x] Seleção retangular temporária aplicada ao pincel/borracha e balde, inclusive nos limites de tiles.
- [x] Máscara por camada criada da seleção; inversão, remoção, undo/redo, persistência em PNG.
- [x] Clipping à transparência da camada imediatamente inferior, considerando máscara e opacidade, com compositor C++ v7.
- [x] Recomposição incremental por tiles de 128×128 após pinceladas, usando as dirty regions do núcleo e o mesmo compositor nativo com blend/máscara/clipping.
- [x] Métricas de tiles/pixels recompostos expostas no painel de Camadas e verificadas com teste de regressão GPU comparando pixels com a composição integral.
- [x] Composição inicial e mudanças estruturais processadas em lotes limitados a 512×512, sem buffers temporários por camada de 4096×4096.
- [x] Teste de comparação contra a implementação C++ integral anterior em 768×640 com máscara, clipping, Screen e borda 512.
- [x] Histórico de pincel/borracha por tiles de 128×128 com captura única por bloco, swap em desfazer/refazer, invalidação do cache nativo e preservação dos snapshots estruturais.
- [x] Indicador visível de passos e MiB RGBA estimados no cabeçalho e testes GPU de histórico misto, transparência e costuras de tiles.
- [x] Snapshots de camadas estruturais por referências imutáveis e cópia sob escrita de Canvas/máscara, incluindo restauração de histórico misto e estimativa de memória sem duplicar buffers compartilhados.
- [x] Orçamento lógico de 256 MiB para buffers RGBA do histórico, preservando ao menos um passo e avisando no cabeçalho quando uma única operação excede o limite; testes GPU de budget para strokes e substituição estrutural. **Não é um teto físico de RAM/VRAM.**\n- [x] Balde contíguo C++ v13 com atualização GPU apenas da região alterada, histórico de preenchimento por tiles e testes C++/Lua de seleção, Alpha Lock e undo/redo. Ainda lê o Canvas inteiro para descobrir a região.\n- [ ] Edição/pintura direta da máscara, clipping em cadeia, grupos, orçamento **físico** de memória do histórico e renderização incremental progressiva.
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
