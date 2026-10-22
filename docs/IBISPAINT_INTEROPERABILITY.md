# Interoperabilidade com ibisPaint — evidências e licenças

> Escopo atual: leitura **experimental e somente de importação** de uma imagem composta extraída de um arquivo `.ipv`, dentro do Inkora. Não implica compatibilidade de camadas, textos, histórico ou escrita do formato.

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
- **não** decodifica `RPNG`, não recria camadas do ibisPaint, não edita textos nem exporta `.ipv`;
- arquivos truncados, sentinelas inválidas, formatos e snapshots ausentes são rejeitados;
- arrastar um arquivo `.ipv` para a janela cria um **novo projeto INKORA1** com a imagem composta numa camada editável, mantendo o arquivo de origem inalterado;
- limite de entrada de 256 MiB, limite da imagem composta de 64 MiB e limite de resolução editável do Inkora de 4096 × 4096 pixels;
- testes puros Lua com registros sintéticos e teste GPU com PNG verdadeiro + rejeição de corrupção.

### Compatibilidade comprovada e pendente

**Comprovado pelos testes locais/CI** (quando verdes): leitura de **arquivos IPV sintéticos** contendo os tipos documentados e importação da imagem PNG reconstruída como projeto Inkora. Isso **não comprova** abertura de documentos reais do ibisPaint: ainda faltam amostras autorizadas de versões reais (principalmente **Windows 14.1.2**) e casos com sessões repetidas.

**Próxima etapa**: montar fixtures reais com obras próprias, confirmar se a última imagem composta sempre está disponível, documentar variações e experimentar importação das camadas raster `RPNG` em memória e testes pixel a pixel. Só depois avaliar exportador IPV; editar snapshots sem reconstruir a cadeia de histórico pode gerar arquivos que o ibisPaint considere corrompidos.

### Política de integração

O formato é analisado para interoperabilidade. Os nomes, ícones, pincéis, gráficos e o código do Inkora continuam independentes. Materiais de terceiros devem permanecer sob as licenças e avisos correspondentes sempre que forem incorporados.
