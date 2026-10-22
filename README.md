# Inkora 🎨

**Inkora** é um projeto de **engenharia reversa funcional do ibisPaint**: reconstruir progressivamente suas ferramentas e o comportamento de pintura, com **código, identidade e recursos próprios**, usando **Lua + C++**. **Windows/PC primeiro; Android depois, sobre o mesmo núcleo.**

> **Regra permanente para qualquer IA que continuar o projeto:** leia **[AGENTS.md](AGENTS.md)** e **[docs/ROADMAP.md](docs/ROADMAP.md)**. **TRABALHA, IA.** Não desvie do objetivo para criar outro editor genérico.

> **Situação atual:** existe um **motor raster C++ v7 + ponte LuaJIT FFI**, integrado ao pincel e à borracha. Esta atualização introduz a **primeira reformulação visual do desktop Inkora**, com biblioteca de presets de pincel, seletor de cores HSV e miniaturas de camadas. **Não** é ainda um editor profissional equivalente ao ibisPaint; os recursos da interface estão sendo aproximados progressivamente do fluxo de trabalho de pintura digital. A ponte usa tiles de 128×128, carregados sob demanda e mantidos em cache entre pinceladas, sem leitura integral por traço.

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

### Interface de pintura — primeira reformulação perceptível

- Área de desenho destacada com mesa escura, tela centralizada, barra compacta de ferramentas e zoom rápido sobre o canvas.
- Quatro abas funcionais no inspetor lateral: **Pincéis** (biblioteca visual com prévias), **Ajustes**, **Camadas** (miniaturas reais) e **Cor** (anel de matiz e quadrado de saturação/brilho).
- Oito presets iniciais independentes: Nanquim, Lápis, Marcador, Aerógrafo, Giz, Pincel macio, Pixel e Ponta PNG. Cada preset altera parâmetros **reais** do motor de pintura C++, como ponta, fluxo, espaçamento, dureza, tamanho e opacidade.
- Canvas com estado inicial orientativo, cursor de pincel proporcional ao tamanho e controles rápidos para tamanho, opacidade e zoom.
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

**Correção de prioridade:** versões anteriores desenvolveram recursos técnicos sem transformarem suficientemente a experiência visual. Esta revisão altera a organização da área de trabalho, adiciona oito presets funcionais e introduz miniaturas reais de camadas e um seletor de cores HSV. **Ainda faltam** docking completo de painéis, UI otimizada para tela pequena, uma biblioteca profissional de pontas, comparativos visuais com o ibisPaint e testes de usabilidade com artistas. Não declarar equivalência visual ou funcional até validar esses itens.

## Rumo ao motor Lua + C++

**Atualização atual (C++ v7):** **máscaras de camada** e **clipping** reais no compositor nativo. A máscara da camada é criada a partir da seleção retangular ativa (ou inteiramente branca se não houver seleção), pode ser invertida e removida. O clipping usa a transparência da camada imediatamente abaixo, combinada com sua máscara e opacidade; uma camada-base oculta torna a camada recortada invisível. Máscaras e clipping participam de desfazer/refazer, reabertura do projeto e exportação PNG. O manifesto anterior segue compatível, com arquivos `mask-NN.png` por camada. **Limitações:** ainda não há pintura direta na máscara, clipping em cadeia/grupos nem compositor otimizado por tiles; documentos grandes com efeitos podem recompor todas as camadas na CPU.

**Atualização anterior:** a API C++ **v6** acrescenta **Alpha Lock** na camada e **seleção retangular** para restringir o pincel, respeitando as bordas mesmo ao atravessar tiles. O balde de tinta também respeita seleção e Alpha Lock. A seleção é temporária (não vai para o projeto); Alpha Lock é salvo e participa de undo/redo. O atalho **M** seleciona; **Ctrl+D** ou **Esc** limpa a seleção. O botão de bloqueio está na aba Camadas. **Limitação:** linha, retângulo e elipse ficam bloqueados enquanto houver seleção/Alpha Lock, até receberem a mesma proteção por pixel. A borracha com Alpha Lock ligado não apaga.

**Etapa anterior:** a API C++ **v5** acrescenta um compositor de camadas nativo, com modos Normal, Multiply, Screen, Add e Overlay e composição RGBA baseada em alfa. Os modos podem ser alterados na aba Camadas e são preservados no projeto e no PNG exportado. A composição C++ é calculada sob demanda para documentos com modos diferentes de Normal; a visualização de camadas normais continua rápida pela GPU. **Limitação:** editar um documento grande com modos especiais força leitura e composição integrais das camadas visíveis; ainda faltam tiles de composição, máscaras e grupos.

**Motor de pincéis anterior:** a API C++ **v4** acrescenta importação de pontas PNG (máscara alfa), fluxo por carimbo e influência configurável da pressão na opacidade. A API C++ v3 havia acrescentado pontas **redonda, chata e granulada**, com textura procedural determinística. O módulo LuaJIT gerencia tiles de 128×128 com **cache LRU limitado** (padrão: 96 tiles por camada, variável opcional `INKORA_TILE_LIMIT` para testes), reaproveita pixels entre traços e faz upload parcial. Tiles pintados expulsos do cache são recuperados da GPU. Camadas vazias iniciam sem readback. Isso ainda não equivale ao motor de pincéis profissional do ibisPaint.

**Motor implementado inicialmente:** `native/inkora_core.cpp` expõe uma API C versionada, que `src/native.lua` chama por LuaJIT FFI. O pincel/borracha já utiliza C++ se a DLL estiver presente. Testes C++ exercitam alpha, pressão interpolada, espaçamento e validação de buffers. O LÖVE no CI exercita a ponte real no Linux; o Windows é compilado com o C++ nativo. Consulte a [auditoria técnica](docs/REVERSE_ENGINEERING.md) e o [roadmap](docs/ROADMAP.md).

**Próxima prioridade:** permitir pintar diretamente nas máscaras de camada, seleção elíptica e laço, grupos/clipping em cadeia, composição por tiles e pressão Windows Ink/WinTab. Pressão funciona no motor e em eventos de toque que a reportem; mouse comum permanece a 100%.

## Limitações atuais e próximos passos

Este ainda é um MVP, não um motor profissional: não há pressão nativa de mesa digitalizadora no desktop, filtros profissionais, estabilizador de ponta, formatos PSD/KRA, biblioteca ampla de pincéis nem aceleração otimizada para telas enormes. A seleção retangular básica existe, mas ainda não possui laço ou varinha. O balde de tinta processa apenas a camada atual na CPU e pode demorar em imagens grandes. O histórico usa cópias completas de camadas e por isso é limitado em tamanho. A interface desktop será adaptada futuramente para Android. É necessário testar a execução real no LÖVE e o desempenho em diferentes GPUs.

**Desenvolvimento:** projeto independente de pintura digital. Nome e identidade próprios; sem associação oficial ao ibisPaint.
