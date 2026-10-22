# Inkora 🎨

**Inkora** é um projeto de **engenharia reversa funcional do ibisPaint**: reconstruir progressivamente suas ferramentas e o comportamento de pintura, com **código, identidade e recursos próprios**, usando **Lua + C++**. **Windows/PC primeiro; Android depois, sobre o mesmo núcleo.**

> **Regra permanente para qualquer IA que continuar o projeto:** leia **[AGENTS.md](AGENTS.md)** e **[docs/ROADMAP.md](docs/ROADMAP.md)**. **TRABALHA, IA.** Não desvie do objetivo para criar outro editor genérico.

> **Situação atual:** existe agora o primeiro **motor raster C++ v1 + ponte LuaJIT FFI**, integrado ao pincel e à borracha. **Não** é ainda um motor profissional nem um clone completo: a interface e as demais ferramentas seguem no protótipo Lua/LÖVE. A ponte faz upload da camada completa para a GPU durante os traços, o que deve ser otimizado por regiões/tiles.

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

### Ferramentas incluídas nesta primeira versão

- Pincel e borracha rasterizados em Canvas com interpolação de traços e estabilizador configurável.
- Ferramentas de linha, retângulo e elipse com pré-visualização.
- Balde de tinta na camada selecionada (tolerância configurável).
- Conta-gotas para amostrar a cor visível de todas as camadas.
- Escolha de cores por paleta, tamanho, opacidade do traço e estabilização.
- Painéis separados para pincéis e camadas, com controles deslizantes arrastáveis.
- Novo documento com largura e altura configuráveis (64 a 4096 px).
- Camadas transparentes: criar, excluir, ordenar, ocultar, controlar opacidade.
- Desfazer/refazer com histórico limitado de snapshots.
- Zoom ancorado no cursor, pan com botão do meio ou Espaço + arrastar, ajuste da tela.
- Importação de imagem PNG arrastada para a janela.
- Exportação PNG com composição das camadas.
- Salvar e abrir projetos editáveis com um arquivo PNG por camada e um manifesto de texto.

### Teclas e mouse

| Ação | Atalho |
| --- | --- |
| Pincel / Borracha / Mover | B / E / H |
| Balde / Conta-gotas | G / I |
| Linha / Retângulo / Elipse | L / R / O |
| Aumentar / diminuir tamanho | ] / [ |
| Desfazer / Refazer | Ctrl+Z / Ctrl+Y |
| Novo documento | Ctrl+N |
| Salvar projeto | Ctrl+S |
| Abrir projeto | Ctrl+O |
| Exportar PNG | Ctrl+Shift+S |
| Ajustar ao espaço | F |
| Zoom | Roda do mouse |
| Mover tela | Meio do mouse ou Espaço + arrastar |
| Importar PNG | Arraste um PNG para a janela |

### Onde os desenhos são salvos?

Os projetos e PNGs são gravados no diretório de dados do LÖVE, usando a identidade **Inkora**. No Windows costuma ser:

`%APPDATA%\LOVE\Inkora\`

- `projects/` — projetos editáveis, com manifesto e PNGs de cada camada.
- `exports/` — imagens PNG exportadas.

O rodapé do aplicativo mostra o diretório real retornado por `love.filesystem.getSaveDirectory()`. O sistema ainda **não** tem diálogo nativo “Salvar como”.

## Estrutura

```text
Inkora/
├── main.lua                # Eventos LÖVE e fluxo da aplicação
├── conf.lua                # Configuração da janela
├── src/
│   ├── document.lua        # Camadas, histórico, projeto e PNG
│   ├── brush.lua           # Motor de pincel raster inicial
│   ├── ui.lua              # Interface desktop em Lua
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

## Rumo ao motor Lua + C++

**Motor implementado nesta etapa:** `native/inkora_core.cpp` expõe uma API C versionada, que `src/native.lua` chama por LuaJIT FFI. O pincel/borracha já utiliza C++ se a DLL estiver presente. Testes C++ exercitam alpha, pressão interpolada, espaçamento e validação de buffers. O LÖVE no CI exercita a ponte real no Linux; o Windows é compilado com o C++ nativo. Consulte a [auditoria técnica](docs/REVERSE_ENGINEERING.md) e o [roadmap](docs/ROADMAP.md).

**Próxima prioridade:** uploads parciais/tiles, dureza e espaçamento expostos na interface, entrada de pressão de mesa digitalizadora, modos de mesclagem e seleção.

## Limitações atuais e próximos passos

Este é um MVP, não um motor profissional: não há pressão nativa de mesa digitalizadora no desktop, seleção, filtros, estabilizador profissional por trajetória, formatos PSD/KRA, pincéis de textura nem aceleração otimizada para telas enormes. O balde de tinta processa apenas a camada atual na CPU e pode demorar em imagens grandes. O histórico usa cópias completas de camadas e por isso é limitado em tamanho. A interface desktop será adaptada futuramente para Android. É necessário testar a execução real no LÖVE e o desempenho em diferentes GPUs.

**Desenvolvimento:** projeto independente de pintura digital. Nome e identidade próprios; sem associação oficial ao ibisPaint.
