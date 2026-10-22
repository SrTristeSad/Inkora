# Inkora — Plano de desenvolvimento vinculante

> **Objetivo:** equivalencia funcional progressiva com o ibisPaint, por estudo do comportamento observavel; Lua + C++ nativo, Windows primeiro, Android depois. Consulte [AGENTS.md](../AGENTS.md).

## Estado verificado do repositorio

| Componente | Estado atual |
| --- | --- |
| Protótipo desktop Lua/LÖVE (canvas e UI) | Implementado; requer testes de uso no Windows |
| Pincel, borracha, formas, balde, camadas e projeto básico | Protótipos Lua; não equivalem ao ibisPaint |
| Engenharia reversa funcional documentada do ibisPaint | **Matriz inicial baseada em documentação pública; medição lado a lado pendente** |
| Auditoria detalhada de ReveriePaint e Klecks | **Auditoria inicial dos arquivos C++/JNI e TS de pincel/camadas; aprofundar ainda** |
| Motor gráfico Inkora em C++ | **C++ ABI v6 com Alpha Lock e seleção retangular sobre pincéis e tiles; CI em validação** |
| Ponte Lua ↔ C++ com testes | **LuaJIT FFI ABI v6, modos de mesclagem, Alpha Lock e seleção retangular** |
| Build Windows integrando C++ e Lua | **CI configurado para DLL C++ + LÖVE; validar resultado da execução** |
| Android sobre o mesmo núcleo | **Futuro** |

## Ordem de execução

### Fase 1 — Fundacao correta (proxima prioridade)
- [x] Criar **docs/REVERSE_ENGINEERING.md**, matriz de equivalencia observada do ibisPaint: gestos, desenho, resposta, layer blend e casos extremos, com evidencia e nivel de confianca.
- [x] Auditar inicialmente arquivos e APIs reais de **ReveriePaint** (C++/Krita/GPL-3.0) e **Klecks** (MIT/TypeScript) e registrar integracao possivel versus reimplementacao.
- [x] Definir uma API versionada **Lua ↔ C++** para rasterizacao em imagens RGBA, sem dependencias de Android na logica.
- [ ] Compilar modulo C++ no CI Windows e testar ponte em LÖVE/Linux (CI deve confirmar execução).
- [x] Mover **um pincel real** do prototipo Lua para C++ com trajetoria, espessura, espacamento, alpha e testes visuais/regressao. Nao remover o caminho Lua antigo antes de passar testes.

### Fase 2 — Motor de pintura
- [ ] Pincéis profissionais: interpolação avançada, textura contínua, tinta úmida, estabilização profissional e pressão Windows Ink/WinTab.
- [x] Ponta personalizada por PNG até 512×512, máscara alfa (ou luminância invertida), com armazenamento local.
- [x] Fluxo básico por carimbo e dinâmica linear de opacidade conforme pressão, via C++ ABI v4.
- [x] Três pontas nativas iniciais (redonda, chata, granulada procedural), com API C++ v3 e testes.
- [x] Cache de tiles 128×128 com leituras regionais sob demanda, inicialização transparente e invalidação em operações Lua.
- [x] Limite de tiles em cache por camada, com LRU e recarregamento seguro após expulsão.
- [ ] Benchmark real, uso máximo de VRAM/CPU e teste prolongado com canvas grandes, incluindo blend modes que usam readbacks completos.
- [x] Compositor C++ v5 e cinco modos iniciais: Normal, Multiply, Screen, Add, Overlay; integrados à interface, undo, exportação PNG e manifesto.
- [x] Alpha Lock por camada, preservado em undo/redo e no manifesto do projeto (retrocompatível).
- [x] Seleção retangular temporária aplicada ao pincel/borracha e balde, inclusive nos limites de tiles.
- [ ] Camadas: máscaras, clipping, grupos, composição por tiles e undo/redo eficiente.
- [ ] Seleção com laço, varinha, elipse, feathering e suporte nas ferramentas de formas.
- [ ] Selecao e transformacoes: laço, varinha, mover, redimensionar, rotacionar (retângulo básico já implementado).
- [ ] Filtros/efeitos de pintura e processamento com controle de memoria.
- [ ] Entrada de mesa digitalizadora (Windows), latencia e benchmark de tela grande.

### Fase 3 — Produto multiplataforma
- [ ] UI refinada de editor de pintura, fluxo de documentos e formatos interoperaveis.
- [ ] Reutilizar o mesmo nucleo C++/Lua em Android, com suporte a toque/gestos/caneta.
- [ ] Comparacao sistematica da experiencia com referencias, sem copiar marca, arte ou codigo proprietario.

## Regra de entrega

Cada iteracao deve: **apontar o item do roadmap**, produzir alteracao concreta e testavel, executar/validar build, documentar limites e publicar commit. A lista nao equivale a implementacao. Evitar adicionar apenas botoes sem melhorar o nucleo. **TRABALHA, IA.**
