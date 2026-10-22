# AGENTS.md — REGRA DO PROJETO INKORA

> **TRABALHA, IA.** Leia isto **antes** de alterar qualquer arquivo. Nao transforme a visao do usuario em um editor de rabiscos.

## MISSAO INEGOCIAVEL
Reconstruir **funcionalmente o ibisPaint** por engenharia reversa do comportamento observavel: ferramentas, pinceis, sensacao do traco, fluxo de trabalho, camadas, filtros, selecao, desempenho e UX. Nome, identidade, codigo e recursos do Inkora devem ser proprios. **Nao basta criar um aplicativo que "desenha".** A meta e atingir progressivamente equivalencia funcional real, verificavel por testes.

## BASE TECNICA DEFINIDA PELO USUARIO
- **Lua + C++**: Lua controla a UI, ferramentas, comandos e extensoes; **C++ nativo** executa rasterizacao, pinceis, composicao de camadas, filtros e rotinas de alto desempenho, com ponte documentada Lua ↔ C++.
- **PC/Windows primeiro; Android depois**. Um mesmo nucleo, codigo e formato de documento entre plataformas; adaptacoes de input e UI por plataforma.
- **Referencia 1: ReveriePaint** — https://github.com/LanRhyme/ReveriePaint (motor C++/Krita; GPL-3.0). Inspecionar arquitetura e avaliar reutilizacao real, **sem ignorar GPL**.
- **Referencia 2: Klecks** — https://github.com/bitbof/klecks (algoritmos, pinceis e UX; MIT). Inspecionar implementacao e aproveitar componentes compativeis quando util.
- **LÖVE** pode servir de hospedeiro/prototipo Lua, **nao substitui** a construcao/integracao do motor C++ do Inkora.

## REALIDADE ATUAL (NAO INVENTAR PROGRESSO)
O repositorio possui um prototipo Lua/LÖVE e **um primeiro motor C++ raster integrado via LuaJIT FFI para pincel/borracha**. O motor C++ ABI v12 fornece posicoes exatas dos carimbos e amostras RGBA8 antes de pintar por segmento; atualiza o reservatorio por carimbo sem costuras de tiles, aproveitando cache Lua de 128x128. ABI v11 acrescenta reservatorio por pincelada com captacao e retencao de pigmento; o estado global e atualizado uma vez por segmento e compartilhado por todos os tiles. A nova aba Tinta mostra a diferenca local x arraste. Ainda nao ha simulacao fisica de tinta. O v10 acrescenta mistura local estilizada de pigmentos com controles umidade/carga e uma aba Tinta com comparacao de pixels seca/umida; ainda nao tem fluido nem secagem. O v9 acrescenta textura procedural de pigmento, dispersao e variacao de tamanho com estado de carimbo compartilhado entre tiles e eventos; a interface ganhou a aba Textura funcional. O v8 acrescenta rotação real de pontas chatas/PNG conforme a direção da trajetória ou ângulo fixo; o v7 acrescenta máscaras de camada e clipping à camada imediatamente inferior, com persistência. Ainda sem pintura direta na máscara nem grupos. O v6 possui Alpha Lock e seleção retangular nos pincéis; o v5 contém compositor RGBA8 (Normal/Multiply/Screen/Add/Overlay), e o v4 suporta máscara personalizada PNG, fluxo básico e opacidade por pressão; mantém as três pontas iniciais, calcula regiões sujas e mantém espaçamento entre eventos; LuaJIT administra um cache LRU limitado de tiles de 128×128. Existe uma ponte de pressao WinTab opcional e experimental (`src/tablet.lua`), com curvas de pressao e fallback no mouse; a entrada fisica real ainda NAO foi validada em hardware Windows. Ainda não há equivalência comprovada de pincel com ibisPaint, pressão Windows Ink ou filtros nativos. A existencia de um pincel C++ nao cumpre a missao. Nao descreva o Inkora como clone completo ou motor profissional.

## EXPERIENCIA VISUAL E UX (REGRA DA VISAO DO USUARIO)
O usuario apontou que as versoes antigas quase nao tinham diferenca perceptivel. **Nao voltar a entregar apenas alteracoes invisiveis no motor**: avancar em paralelo na interface e demonstrar funcionalidades reais ao artista. O documento com blend/máscara/clipping agora possui recomposicao incremental por tiles de 128x128 para pinceladas, mantendo composicao integral inicial e nas alteracoes estruturais. O painel Camadas exibe os tiles/pixels atualizados. A reformulacao do desktop inclui biblioteca de presets configurando C++, miniaturas de brush produzidas pelo core nativo (nao simuladas na UI), previa de brush em tempo real para os parametros, angulo, modo direcional e a cor ativos, estabilizador temporal adaptativo com caminho do pincel suavizado e terminacao do traco amostrada, presets editaveis com salvamento/restauracao local, filtro por categoria, inspetor redimensionavel, seletor HSV, favoritos persistentes, miniaturas de camadas e giro de visualizacao com conversao correta de coordenadas. A rotacao NAO modifica os pixels do arquivo exportado. Preservar esses fluxos, evitar botoes decorativos. Documentar sempre a diferenca VISIVEL e o teste funcional correspondente.

## ORDEM DE TRABALHO OBRIGATORIA
1. Inspecione o codigo existente e consulte **docs/ROADMAP.md**; preserve o que ja funciona.
2. Faça uma matriz de comportamento do ibisPaint: ferramenta/gesto, resultados, casos extremos e teste comparativo. Identifique o que e **observado** versus **estimado**; nao invente descoberta de engenharia reversa.
3. Audite o codigo real de ReveriePaint e Klecks, licencas e dependencias, antes de escolher componentes.
4. **Motor C++ v1 + API Lua ↔ C++ + pincel integrado implementados**: preserve-os, meca-os e evolua para dirty tiles, parametros profissionais, camadas, composicao, filtros, selecao e UX. Nunca volte ao motor unicamente Lua.
5. Entregue sempre **codigo executavel**, teste automatico e build Windows, com logs honestos e commits no repositorio. Se houver falha, corrija ou reporte; **nao anuncie sucesso sem verificar**.
6. Atualize o roadmap e o README com o que foi **realmente** construido, o que continua faltando e o proximo passo.

## LIMITES LEGAIS E TECNICOS
- Engenharia reversa **funcional**: estudar comportamento permitido e implementar de forma independente; sem extrair codigo/arte proprietaria ou burlar protecoes.
- **GPL-3.0 (ReveriePaint/Krita)** impõe obrigacoes de distribuicao e licenciamento ao incorporar codigo. **MIT (Klecks)** preserva aviso de copyright/licenca. Avaliar antes de mesclar.
- Nao prometer desempenho identico nem compatibilidade sem medicao.

## A REGRA FINAL
**Nao mude o objetivo, nao reinicie do zero por conveniencia, nao esconda lacunas atras de uma interface bonita.** A cada continuacao, mova o Inkora em direcao ao **ibisPaint funcional em Lua + C++**, mantendo Windows como primeira plataforma.

**TRABALHA, IA.** O alvo e um editor de pintura serio, nao mais um prototipo generico.
