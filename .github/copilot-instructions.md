# Instrucoes obrigatorias para agentes de codigo — Inkora

**TRABALHA, IA.** Antes de qualquer alteracao, leia [AGENTS.md](../AGENTS.md) e [docs/ROADMAP.md](../docs/ROADMAP.md).

O Inkora **nao** e um app de rabiscos. Objetivo fixado pelo usuario: **engenharia reversa funcional do ibisPaint**, com codigo/identidade proprios e equivalencia progressiva de ferramentas e comportamento. **Lua para interface/logica + C++ nativo para motor grafico** e ponte Lua↔C++. **Windows/PC primeiro, Android depois**, com nucleo compartilhado. **ReveriePaint (GPL-3.0) + Klecks (MIT)** sao as referencias tecnicas obrigatorias a estudar e, apenas quando licencas/arquitetura permitirem, integrar.

**Situacao real:** existe apenas um MVP Lua/LÖVE. Falta o motor C++ e a ponte. Priorize auditar as referencias e implementar **um componente C++ real, compilavel, invocado via Lua**, antes de adicionar cosmetica. Preserve os recursos atuais. Sempre execute testes, gere build Windows e atualize documentacao com evidencias. Nao marque tarefas incompletas como prontas. Nao copie arte/codigo proprietario do ibisPaint nem contorne protecoes.

**Nao desvie da visao do projeto.**
