# Inkora — Plano de desenvolvimento vinculante

> **Objetivo:** equivalencia funcional progressiva com o ibisPaint, por estudo do comportamento observavel; Lua + C++ nativo, Windows primeiro, Android depois. Consulte [AGENTS.md](../AGENTS.md).

## Estado verificado do repositorio

| Componente | Estado atual |
| --- | --- |
| Protótipo desktop Lua/LÖVE (canvas e UI) | Implementado; requer testes de uso no Windows |
| Pincel, borracha, formas, balde, camadas e projeto básico | Protótipos Lua; não equivalem ao ibisPaint |
| Engenharia reversa funcional documentada do ibisPaint | **Pendente** |
| Auditoria detalhada de ReveriePaint e Klecks | **Pendente** |
| Motor gráfico Inkora em C++ | **Pendente** |
| Ponte Lua ↔ C++ com testes | **Pendente** |
| Build Windows integrando C++ e Lua | **Pendente** |
| Android sobre o mesmo núcleo | **Futuro** |

## Ordem de execução

### Fase 1 — Fundacao correta (proxima prioridade)
- [ ] Criar **docs/REVERSE_ENGINEERING.md**, matriz de equivalencia observada do ibisPaint: gestos, desenho, resposta, layer blend e casos extremos, com evidencia e nivel de confianca.
- [ ] Auditar arquivos e APIs reais de **ReveriePaint** (C++/Krita/GPL-3.0) e **Klecks** (MIT/TypeScript) e registrar integracao possivel versus reimplementacao.
- [ ] Definir uma API versionada **Lua ↔ C++** para rasterizacao em imagens RGBA, sem dependencias de Android na logica.
- [ ] Compilar um modulo C++ nativo no CI para Windows e exercita-lo por Lua em um teste.
- [ ] Mover **um pincel real** do prototipo Lua para C++ com trajetoria, espessura, espacamento, alpha e testes visuais/regressao. Nao remover o caminho Lua antigo antes de passar testes.

### Fase 2 — Motor de pintura
- [ ] Pinceis: dureza, ponta/textura, dinamica, opacidade, fluxo, estabilidade e pressao quando disponivel.
- [ ] Camadas: composicao, mascara, clipping, multiplos modos de mesclagem, grupos e undo/redo eficiente.
- [ ] Selecao e transformacoes: laco, retangulo, varinha, mover, redimensionar, rotacionar.
- [ ] Filtros/efeitos de pintura e processamento com controle de memoria.
- [ ] Entrada de mesa digitalizadora (Windows), latencia e benchmark de tela grande.

### Fase 3 — Produto multiplataforma
- [ ] UI refinada de editor de pintura, fluxo de documentos e formatos interoperaveis.
- [ ] Reutilizar o mesmo nucleo C++/Lua em Android, com suporte a toque/gestos/caneta.
- [ ] Comparacao sistematica da experiencia com referencias, sem copiar marca, arte ou codigo proprietario.

## Regra de entrega

Cada iteracao deve: **apontar o item do roadmap**, produzir alteracao concreta e testavel, executar/validar build, documentar limites e publicar commit. A lista nao equivale a implementacao. Evitar adicionar apenas botoes sem melhorar o nucleo. **TRABALHA, IA.**
