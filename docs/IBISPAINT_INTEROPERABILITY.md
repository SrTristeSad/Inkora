# Interoperabilidade com ibisPaint — evidências e licenças

> Escopo atual: importacao **experimental de imagem composta e camadas raster RPNG reconhecidas**. Nao implica fidelidade de ordem de camadas, modos de mistura, visibilidade, texto, historico ou escrita do formato.

## Auditoria de projetos públicos (22/10/2026)

| Repositório | Licença verificada | Resultado |
| --- | --- | --- |
| [fapotaa/ipv-format](https://github.com/fapotaa/ipv-format) | **MIT**, manifesto no GitHub e `LICENSE` | Fonte preferida para pesquisa de interoperabilidade. Documenta container com campos big-endian e sentinelas, snapshot composto PNG (`0100/0500`), RPNG de camadas, texto e limites. É experimental e baseado no ibisPaint X Android 14.0.11. |
| [HatLink/reeng-ibispaint](https://github.com/HatLink/reeng-ibispaint) | **Nenhuma licença explícita encontrada** | Documentação pública útil em `IPV/main.md`, `IPCF/main.md` e `IPBZ/main.md`. Não copiar código, recursos ou arquivos deste repositório sem permissão. A informação sobre pastas em IPCF é marcada incerta pelo autor. |
| [Vectra777/rusty-painter](https://github.com/Vectra777/rusty-painter) | **GPL-3.0-only** | `src/brush_engine/import/ibis.rs` demonstra interpretação de QR de pincéis IPBZ, com limitações. Pode orientar testes e o desenho de um parser independente. Não copiar nem vincular componentes GPL a um Inkora sem definição/compatibilidade de licença. |
| [saimoneybusiness-afk/Toon-Paint---IbisPaint-clone](https://github.com/saimoneybusiness-afk/Toon-Paint---IbisPaint-clone) | **Nenhuma licença explícita encontrada** | Código Android de uma aplicação própria, sem evidência de descompilação do motor ibisPaint; benefício muito limitado para um aplicativo Lua/C++ Windows. |

A ausência de `LICENSE` **não** concede licença de reutilização. A referência GPL não fica automaticamente compatível com o Inkora pelo fato de estar pública; condições de redistribuição e de trabalho derivado precisam ser respeitadas. A MIT permite reutilização sob os seus avisos; nesta etapa não importamos código da biblioteca `ipv-format`.

## Implementação entregue

- `src/ibis_ipv.lua`: leitor independente baseado **somente na especificação publicada** em [FORMAT.md](https://github.com/fapotaa/ipv-format/blob/main/docs/FORMAT.md), sem linhas de código copiadas das implementações externas;
- cabeçalhos e números em big-endian, validação de limites e da sentinela negativa dos registros;
- identifica a imagem composta PNG mais recente e valida suas dimensões;
- decodifica os retangulos raster `RPNG` conhecidos, cobertura em `u16` (skip/run) e linhas invertidas; cada retangulo vira uma camada nativa Inkora independente;
- compara pixels amostrados das camadas RPNG decodificadas usando composicao Normal em RGBA premultiplicado com a imagem final PNG do IPV, experimentando ordem invertida somente se produzir correspondencia; resultado divergente ou inconclusivo usa importacao do PNG achatado, sem presumir blend/visibilidade/alpha desconhecidos; a amostragem tem limite e **nao prova equivalencia pixel a pixel de imagens grandes**;
- preserva a imagem composta original numa camada de referencia **oculta** para verificacao; quando um registro `0300/0600` de lista de camadas passa nas validacoes (grupos `0300/0603`, comprimentos, sentinelas e IDs), o importador usa o **ultimo conjunto apos a operacao** para ordenar as camadas e nao ressuscitar camadas excluidas. Sem uma lista reconhecida, mantem ordenacao estimada por ID;
- **nao** decodifica propriedades de visibilidade/blend/opacidade do ibisPaint, texto editavel, operacoes do historico nem exporta `.ipv`. A leitura da ordem `0300/0600` foi exercitada apenas com fixtures sinteticas; a direcao visual e a compatibilidade no Windows 14.1.2 permanecem pendentes;
- arquivos truncados, sentinelas inválidas, formatos e snapshots ausentes são rejeitados;
- arrastar um arquivo `.ipv` cria um **novo projeto INKORA1**. Quando todas as camadas RPNG reconhecidas passam na validacao, cria camadas raster editaveis e referencia composta oculta; caso contrario, importa apenas a imagem composta e informa o motivo. O arquivo de origem nunca e modificado;
- limite de entrada de 256 MiB, limite da imagem composta de 64 MiB e limite de resolução editável do Inkora de 4096 × 4096 pixels;
- testes puros Lua com registros sintéticos e teste GPU com PNG verdadeiro + rejeição de corrupção.

### Compatibilidade comprovada e pendente

**Comprovado pelos testes locais/CI** (quando verdes): leitura de **arquivos IPV sintéticos** contendo os tipos documentados, importacao da imagem PNG e testes RPNG sinteticos com 2x2 pixels, mascara esparsa, inversao de coordenadas Y, reabertura de camadas e fallback quando mascaras sao invalidas. Isso **não comprova** abertura de documentos reais do ibisPaint: ainda faltam amostras autorizadas de versões reais (principalmente **Windows 14.1.2**) e casos com sessões repetidas.

**Próxima etapa**: coletar fixtures IPV reais criadas pelo proprio usuario no ibisPaint, medir resultados pixel a pixel, validar a ordem `0300/0600` (incluindo orientacao da pilha), decodificar visibilidade/blend/opacidade e definir fidelidade antes de afirmar importacao nativa fiel. Depois estudar IPBZ. Editar snapshots sem reconstruir a cadeia do historico pode gerar arquivos que o ibisPaint considere corrompidos.

### Política de integração

O formato é analisado para interoperabilidade. Os nomes, ícones, pincéis, gráficos e o código do Inkora continuam independentes. Materiais de terceiros devem permanecer sob as licenças e avisos correspondentes sempre que forem incorporados.

### Leitura conservadora de ordem — experimento 22/10/2026

O parser reconhece grupos encadeados `0300/0603` terminados por ID `-1` na ultima operacao `0300/0600`. Utiliza somente o segundo grupo (IDs apos a operacao) quando integro: IDs antigos excluidos deixam de aparecer na importacao, e snapshots inexistentes para IDs ainda ativos provocam fallback achatado. Metadados desconhecidos mantem o comportamento anterior de ordenacao por ID. O aviso do editor identifica a origem da ordem. Os testes sao **sinteticos**: ainda nao comprovam ordenacao visual equivalente ao ibisPaint Windows 14.1.2, propriedades de camada ou importacao de arquivos reais. A implementacao e independente da base MIT.

### Auditoria de fixture publica real (Android 14.0.11)

A pipeline foi ampliada para **baixar temporariamente** a fixture publica
[general-30-text-layers.ipv](https://github.com/fapotaa/ipv-format/blob/main/templates/general-30-text-layers.ipv),
fixada no commit `a5bded915994dbbf972b549eafe02c6a64c94731` e verificada pelo Git blob SHA
`d3dc6f83d90f59a3b145967a18d6c6aaabf8356a`, sem adiciona-la a este repositorio.
O tamanho do canvas documentado e de **720 x 16000** pixels. O script
`tests/ipv_real_fixture.lua` valida a leitura do container real (cabecalho,
dimensoes, snapshots e registros de texto), e
`tools/inspect_ipv.lua` produz um relatorio de metadados, sem extrair desenhos
nem executar codigo da origem. O workflow publica apenas `ipv-audit.txt`.

Esta verificacao **nao comprova** fidelidade visual de camadas nem importacao
editavel de um canvas de 16000 pixels: o Inkora limita atualmente documentos
editaveis a 4096 x 4096. Tambem nao valida ibisPaint Windows 14.1.2.

Para auditar um arquivo IPV local com Lua 5.1, executar na raiz do projeto:
`lua tools/inspect_ipv.lua "caminho/para/obra.ipv"`.
A ferramenta preserva o arquivo original e nao exibe conteudo dos textos.
