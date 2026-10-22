# Inkora 🎨

**Inkora** é um projeto de **engenharia reversa funcional do ibisPaint**: reconstruir progressivamente suas ferramentas e o comportamento de pintura, com **código, identidade e recursos próprios**, usando **Lua + C++**. **Windows/PC primeiro; Android depois, sobre o mesmo núcleo.**

> **Regra permanente para qualquer IA que continuar o projeto:** leia **[AGENTS.md](AGENTS.md)** e **[docs/ROADMAP.md](docs/ROADMAP.md)**. **TRABALHA, IA.** Não desvie do objetivo para criar outro editor genérico.

> **Situação atual:** existe um **motor raster C++ v10 + ponte LuaJIT FFI**, integrado ao pincel e à borracha. Esta atualização introduz a **primeira reformulação visual do desktop Inkora**, com biblioteca de presets de pincel, seletor de cores HSV e miniaturas de camadas. **Não** é ainda um editor profissional equivalente ao ibisPaint; os recursos da interface estão sendo aproximados progressivamente do fluxo de trabalho de pintura digital. A ponte usa tiles de 128×128, carregados sob demanda e mantidos em cache entre pinceladas, sem leitura integral por traço.

**Referências obrigatórias:** [ReveriePaint](https://github.com/LanRhyme/ReveriePaint) (C++/Krita; GPL-3.0) e [Klecks](https://github.com/bitbof/klecks) (ferramentas e UX; MIT). Integração depende de auditoria de código e licença.

## Executar no PC

### Windows sem instalar LÖVE

1. Abra a aba [Actions](https://github.com/SrTristeSad/Inkora/actions/workflows/windows.yml) do repositório.
2. Entre na execução concluída mais recente do workflow **Inkora Desktop**.
3. Em **Artifacts**, baixe **Inkora-Windows-portable**.
4. Extraia o ZIP completo (incluindo as DLLs) e abra **Inkora.exe**.

A compilação é automática no GitHub Actions. O pacote Windows portátil inclui o LÖVE **e `inkora_core.dll` (C++)**, carregado por LuaJIT FFI. Não precisa instalar um runtime separado. Artefatos do Actions podem expirar, mas um novo push no `main` gera um novo pacote.

### Executar o código-fonte em LÖVE

1. Instale o [LÖVE 11.5](https://love2d.org/) para Windows (versão 64 bits).
2. Baixe o repositório (Code → Download ZIP) e extraia-o.
3. Arraste a **pasta `Inkora`** para `love.exe`, ou use `love caminho/para/Inkora` com LÖVE no PATH.
4. Uma janela do editor será aberta. Não é necessário Node.js nem instalação de pacotes Lua.

### Interface de pintura — biblioteca nativa e painéis ajustáveis

- Área de desenho destacada com mesa escura, tela centralizada, barra compacta de ferramentas e zoom rápido sobre o canvas.
- Quatro abas funcionais no inspetor lateral: **Pincéis** (biblioteca visual com prévias), **Ajustes**, **Camadas** (miniaturas reais) e **Cor** (anel de matiz e quadrado de saturação/brilho).
- Oito presets iniciais independentes: Nanquim, Lápis, Marcador, Aerógrafo, Giz, Pincel macio, Pixel e Ponta PNG. Cada preset altera parâmetros **reais** do motor de pintura C++, como ponta, fluxo, espaçamento, dureza, tamanho e opacidade.
- **Prévia gerada pelo motor C++**: as miniaturas da biblioteca são rasterizadas de verdade, com a ponta e dinâmica de cada preset, uma única vez e guardadas em cache (não são desenhos artificiais feitos pela interface). O tamanho na miniatura é adaptado ao espaço visual.
- **Prévia ao vivo na aba Ajustes**: alterar tamanho, opacidade, fluxo, dureza, espaçamento, ponta, influência da pressão **ou estabilização adaptativa** atualiza um traço de teste feito pelo motor C++ e pela cor selecionada. Apenas a última prévia dinâmica permanece em memória; mover os controles não modifica o desenho.
- **Entrada de caneta Windows (WinTab experimental):** o módulo opcional `src/tablet.lua` abre um contexto WinTab quando o driver existe, coleta pacotes de pressão no Windows e combina esses valores com a posição do cursor já fornecida pelo LÖVE. Os traços passam a usar pressão física quando os pacotes são recentes. Em outras plataformas, sem driver ou com amostras expiradas, o mouse continua a 100% e eventos de toque preservam a pressão própria. Na aba Ajustes, selecione **Leve, Linear ou Firme** e acompanhe a leitura de pressão. A preferência é salva em `pen-pressure-curve.txt`. **Limitação importante:** a ponte foi desenvolvida com base na especificação WinTab e passou por testes simulados, mas **a captura de pressão em mesa real no Windows ainda não foi validada**; Windows Ink, inclinação da caneta, calibração por modelo e medição de latência ainda faltam.
- **Mistura de tinta úmida C++ v10:** nova aba **Tinta** com dois controles reais: **Umidade** e **Carga de pigmento**. As cores misturam-se com o pigmento que já existe **na mesma camada**, por uma aproximação geométrica de mistura subtrativa; a opacidade e a pressão do pincel continuam válidas. A aba compara lado a lado traços secos e úmidos sobre fundos vermelho/azul renderizados pelo próprio C++. O preset inicial **Aquarela** utiliza umidade elevada e carga moderada. Os parâmetros podem ser salvos por pincel e os projetos e presets antigos seguem compatíveis. **Limites:** ainda não há transferência física de tinta entre pixels, mistura com camadas inferiores, secagem ou fluido real.
- **Pincéis texturizados C++ v9:** o novo núcleo oferece **Textura** (pontilhamento estável no espaço do documento), **Dispersão** (desvio determinístico dos carimbos) e **Variação de tamanho**. A nova aba **Textura** permite ajustar esses parâmetros, visualizar um traço gerado pelo núcleo C++, comparar com o padrão e salvar/restaurar o preset. O Lápis começa com uma textura suave e o Giz com maior dispersão. O índice global dos carimbos é mantido entre eventos e tiles para evitar emendas de textura. A v9 mantém disponíveis os símbolos anteriores; isso **não é ainda uma simulação de aquarela, óleo ou tinta úmida**.
- **Pontas direcionais (C++ v8):** pontas chatas e máscaras PNG usam um ângulo fixo ou giram conforme a **direção do movimento**. A aba Ajustes oferece o ângulo de 0° a 180° e a opção **Ponta acompanha o traço**. O preset Marcador ativa essa opção inicialmente; os demais preservam seus ângulos fixos. O motor preserva o estado direcional entre eventos e tiles e mantém APIs antigas disponíveis.
- **Traços com estabilização adaptativa ao tempo**: a suavização leva em conta o intervalo dos eventos e a velocidade do ponteiro, atenuando tremores de baixa velocidade sem atrasar tanto movimentos rápidos. O fim do traço é concluído por segmentos progressivos, preservando o espaçamento do C++ entre carimbos. Durante o desenho estabilizado, um marcador azul indica onde o pincel suavizado está, ligado ao cursor por uma linha discreta. Não há ainda estabilização profissional equivalente à do ibisPaint nem integração Windows Ink/WinTab.
- **Presets editáveis e persistentes**: use **Salvar preset** para conservar as configurações do pincel selecionado e **Restaurar** para voltar à configuração de fábrica. Os ajustes ficam em `brush-profiles-v1.txt` no diretório do Inkora. Um ponto ao lado do nome identifica presets personalizados. A prévia de cada cartão também passa a refletir as configurações salvas.
- **Categorias e favoritos combináveis:** navegue entre Todos, Tinta, Esboço, Pintura, Textura, Precisão e Sua biblioteca, mantendo o filtro de favoritos quando desejar.
- **Aba Tinta:** dois sliders de umidade e pigmento, comparação de traços reais com a mesma cor, presets editáveis e Aquarela como opção de pintura úmida.
- **Aba Textura:** controles independentes de granulação, dispersão e variação do diâmetro, com prévia real do motor C++ e configurações editáveis por pincel.
- **Painel lateral redimensionável:** arraste a borda esquerda do inspetor de pincéis/camadas/cores para ampliar o espaço de controles, preservando a posição do desenho no workspace.
- **Favoritos persistentes:** marque com `*` no cartão do pincel e use o filtro **Favoritos**. As preferências ficam em `brush-favorites.txt` no diretório do Inkora, sem depender de servidor.
- Canvas com estado inicial orientativo, cursor de pincel proporcional ao tamanho, controles rápidos para tamanho, opacidade, zoom e **rotação da visualização sem alterar os pixels**. Girar preserva a posição do cursor no documento, mesmo com zoom.
- Painel de camadas com miniaturas atualizadas a partir dos próprios canvases, botões de ordenação, visibilidade, máscaras, clipping e modos de mesclagem.
- A interface permanece escrita em Lua/LÖVE; o motor C++ v7 continua responsável por pintar, compor, mascarar e fazer clipping. O visual é próprio do Inkora, não uma reprodução dos gráficos proprietários do ibisPaint.

### Ferramentas disponíveis

- Pincel e borracha rasterizados em Canvas com interpolação de traços e estabilizador configurável.
- Ferramentas de linha, retângulo e elipse com pré-visualização.
- Balde de tinta na camada selecionada (tolerância configurável).
- Conta-gotas para amostrar a cor visível de todas as camadas.
- Escolha de cores por paleta, tamanho, opacidade do traço e estabilização.
- Biblioteca de pincéis, painel de ajustes, painel de camadas com miniaturas e estúdio de cores HSV.
- Novo documento com largura e altura configuráveis (64 a 4096 px).
- Camadas transparentes: criar, excluir, ordenar, ocultar, controlar opacidade, ativar Alpha Lock, criar/inverter/remover máscara, ativar clipping e escolher modos de mesclagem (Normal, Multiply, Screen, Add e Overlay).
- Seleção retangular temporária (M, arrastar, Ctrl+D para limpar) que restringe pincel, borracha e balde na área selecionada.
- Desfazer/refazer com histórico limitado de snapshots.
- Zoom ancorado no cursor, pan com botão do meio ou Espaço + arrastar, ajuste da tela.
- Importação de imagem PNG arrastada para a janela.
- Importação de **ponta personalizada** com **Shift + arrastar PNG** (até 512×512 px, arquivo até 12 MB). PNG transparente usa alfa; imagem inteiramente opaca usa luminância invertida (preto pinta, branco não). A ponta fica salva em `brushes/custom-tip.png` na pasta de dados do LÖVE.
- Controle de **fluxo por carimbo** e de quanto a pressão influencia a opacidade. Não é ainda a simulação de tinta do ibisPaint.
- Exportação PNG com composição das camadas.
- Salvar e abrir projetos editáveis com um arquivo PNG por camada e um manifesto de texto.

### Teclas e mouse

| Ação | Atalho |
| --- | --- |
| Pincel / Borracha / Mover | B / E / H |
| Balde / Conta-gotas | G / I |
| Seleção retangular / Limpar seleção | M / Ctrl+D ou Esc |
| Linha / Retângulo / Elipse | L / R / O |
| Aumentar / diminuir tamanho | ] / [ |
| Desfazer / Refazer | Ctrl+Z / Ctrl+Y |
| Novo documento | Ctrl+N |
| Salvar projeto | Ctrl+S |
| Abrir projeto | Ctrl+O |
| Exportar PNG | Ctrl+Shift+S |
| Ajustar ao espaço | F |
| Girar a visualização | , / . (15°) ou Alt + roda do mouse (5°) |
| Restaurar giro a 0° | 0 ou Ctrl+0 |
| Alternar biblioteca / camadas | Tab |
| Abrir seletor de cores | C |
| Zoom | Roda do mouse |
| Mover tela | Meio do mouse ou Espaço + arrastar |
| Importar PNG como camada | Arraste um PNG para a janela |
| Importar ponta personalizada | Segure Shift e arraste PNG para a janela |

### Onde os desenhos são salvos?

Os projetos e PNGs são gravados no diretório de dados do LÖVE, usando a identidade **Inkora**. No Windows costuma ser:

`%APPDATA%\LOVE\Inkora\`

- `projects/` — projetos editáveis, com manifesto e PNGs de cada camada.
- `exports/` — imagens PNG exportadas.
- `brush-favorites.txt` — preferências de pincéis favoritos.
- `brush-profiles-v1.txt` — ajustes personalizados dos nove presets, incluindo ângulo, direção, textura e tinta úmida. Entradas antigas com 8, 10 ou 13 parâmetros continuam aceitas; valores inválidos são ignorados.
- `pen-pressure-curve.txt` — preferência Leve, Linear ou Firme para a pressão de caneta, com leitura WinTab experimental no Windows.

Os caminhos podem ser consultados na pasta de dados do Inkora. O rodapé mostra o documento, a ferramenta e o zoom. O sistema ainda **não** tem diálogo nativo “Salvar como”.

## Estrutura

```text
Inkora/
├── main.lua                # Eventos LÖVE e fluxo da aplicação
├── conf.lua                # Configuração da janela
├── src/
│   ├── document.lua        # Camadas, histórico, projeto e PNG
│   ├── brush.lua           # Motor de pincel raster inicial
│   ├── ui.lua              # Interface desktop com biblioteca, cores e miniaturas
│   ├── presets.lua         # Presets que configuram o motor C++ de verdade
│   └── palette.lua         # Paleta de cores
├── native/                # Motor C++ independente (CMake)
│   ├── inkora_core.h       # Contrato ABI C v1
│   └── inkora_core.cpp     # Pincel raster nativo
├── src/native.lua          # Ponte LuaJIT FFI
├── docs/REVERSE_ENGINEERING.md
├── .gitignore
└── README.md
```

## Referências técnicas e licenças

- [Klecks](https://github.com/bitbof/klecks) — pintura digital na Web, **MIT**.
- [ReveriePaint](https://github.com/LanRhyme/ReveriePaint) — editor Android baseado no motor do Krita, **GPL-3.0**.

A **primeira implementação não incorpora código, pincéis, gráficos ou bibliotecas desses projetos**. São referências de pesquisa e de funcionalidades. A eventual incorporação de código do ReveriePaint/Krita exigirá respeitar a GPL-3.0 e reavaliar as condições de distribuição do Inkora.

## Interface: objetivo perceptível da próxima versão

**Correção de prioridade:** versões anteriores desenvolveram recursos técnicos sem transformarem suficientemente a experiência visual. A interface agora possui oito presets com prévias produzidas pelo motor C++, prévia dinâmica de ajustes de pincel, salvamento/restauração individual de presets, categorias funcionais, favoritos persistentes, inspetor redimensionável, rotação ancorada do canvas, miniaturas de camadas e um seletor HSV. **Ainda faltam** docking completo de painéis, UI otimizada para tela pequena, uma biblioteca profissional de pontas, comparativos visuais com o ibisPaint e testes de usabilidade com artistas. Não declarar equivalência visual ou funcional até validar esses itens.

## Rumo ao motor Lua + C++

**Atualização atual (C++ v7):** **máscaras de camada** e **clipping** reais no compositor nativo. A máscara da camada é criada a partir da seleção retangular ativa (ou inteiramente branca se não houver seleção), pode ser invertida e removida. O clipping usa a transparência da camada imediatamente abaixo, combinada com sua máscara e opacidade; uma camada-base oculta torna a camada recortada invisível. Máscaras e clipping participam de desfazer/refazer, reabertura do projeto e exportação PNG. O manifesto anterior segue compatível, com arquivos `mask-NN.png` por camada. **Limitações:** ainda não há pintura direta na máscara, clipping em cadeia/grupos nem compositor otimizado por tiles; documentos grandes com efeitos podem recompor todas as camadas na CPU.

**Atualização anterior:** a API C++ **v6** acrescenta **Alpha Lock** na camada e **seleção retangular** para restringir o pincel, respeitando as bordas mesmo ao atravessar tiles. O balde de tinta também respeita seleção e Alpha Lock. A seleção é temporária (não vai para o projeto); Alpha Lock é salvo e participa de undo/redo. O atalho **M** seleciona; **Ctrl+D** ou **Esc** limpa a seleção. O botão de bloqueio está na aba Camadas. **Limitação:** linha, retângulo e elipse ficam bloqueados enquanto houver seleção/Alpha Lock, até receberem a mesma proteção por pixel. A borracha com Alpha Lock ligado não apaga.

**Etapa anterior:** a API C++ **v5** acrescenta um compositor de camadas nativo, com modos Normal, Multiply, Screen, Add e Overlay e composição RGBA baseada em alfa. Os modos podem ser alterados na aba Camadas e são preservados no projeto e no PNG exportado. A composição C++ é calculada sob demanda para documentos com modos diferentes de Normal; a visualização de camadas normais continua rápida pela GPU. **Limitação:** editar um documento grande com modos especiais força leitura e composição integrais das camadas visíveis; ainda faltam tiles de composição, máscaras e grupos.

**Motor de pincéis anterior:** a API C++ **v4** acrescenta importação de pontas PNG (máscara alfa), fluxo por carimbo e influência configurável da pressão na opacidade. A API C++ v3 havia acrescentado pontas **redonda, chata e granulada**, com textura procedural determinística. O módulo LuaJIT gerencia tiles de 128×128 com **cache LRU limitado** (padrão: 96 tiles por camada, variável opcional `INKORA_TILE_LIMIT` para testes), reaproveita pixels entre traços e faz upload parcial. Tiles pintados expulsos do cache são recuperados da GPU. Camadas vazias iniciam sem readback. Isso ainda não equivale ao motor de pincéis profissional do ibisPaint.

**Motor implementado inicialmente:** `native/inkora_core.cpp` expõe uma API C versionada, que `src/native.lua` chama por LuaJIT FFI. O pincel/borracha já utiliza C++ se a DLL estiver presente. Testes C++ exercitam alpha, pressão interpolada, espaçamento e validação de buffers. O LÖVE no CI exercita a ponte real no Linux; o Windows é compilado com o C++ nativo. Consulte a [auditoria técnica](docs/REVERSE_ENGINEERING.md) e o [roadmap](docs/ROADMAP.md).

**Próxima prioridade:** validar em hardware Windows a ponte WinTab experimental, estudar Windows Ink, aprimorar o modelo de tinta úmida para transportar pigmento ao longo dos movimentos e aperfeiçoar os filtros de textura. Também faltam seleção avançada, máscaras editáveis e otimização do compositor.
 
**Observação sobre WinTab:** não houve novos testes físicos nesta atualização; a integração continua experimental.

 Pressão funciona no motor e em eventos de toque que a reportem; mouse comum permanece a 100%.

## Limitações atuais e próximos passos

Este ainda é um MVP, não um motor profissional: existe apenas uma ponte WinTab experimental ainda não verificada em mesa física Windows; não há suporte Windows Ink comprovado, filtros profissionais, estabilizador completo, formatos PSD/KRA, biblioteca ampla de pincéis nem aceleração otimizada para telas enormes. A seleção retangular básica existe, mas ainda não possui laço ou varinha. O balde de tinta processa apenas a camada atual na CPU e pode demorar em imagens grandes. O histórico usa cópias completas de camadas e por isso é limitado em tamanho. A interface desktop será adaptada futuramente para Android. É necessário testar a execução real no LÖVE e o desempenho em diferentes GPUs.

**Desenvolvimento:** projeto independente de pintura digital. Nome e identidade próprios; sem associação oficial ao ibisPaint.
