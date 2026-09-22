**Verificação realizada em 22/09/2026**

`node tests/smoke.mjs`: **26 cenários passaram**, código de saída 0.

Foram exercitadas funções extraídas dos arquivos de produção, com adaptação limitada de sintaxe para JavaScript e APIs simuladas: classificação do candle, níveis BUY/SELL, unidades de preço e lote, confirmação contínua, idempotência da primeira entrada, inversão retida, limites/delay, bloqueio de duplicação, reconstrução cronológica de deals, contabilidade NETTING, parciais, TP HEDGING, intervenção manual, exposição alheia e validação de candles perdidos após reinício.

Revisão estática: nove fontes MQL5 verificadas quanto a delimitadores, includes locais, nomes de funções duplicados e campos referenciados das estruturas. Nenhuma inconsistência encontrada nesses critérios. O script PowerShell de compilação passou pelo parser do PowerShell.

Na revisão foram corrigidos, entre outros pontos: colisão com os nomes nativos `VOLUME_REAL`/`VOLUME_TICK`, janela entre remoção da ordem e chegada do deal, retenção de cancelamento manual entre reconstruções, contagem única de fills parciais, resultado real versus preço médio NETTING e invalidação de sinal contrário retido depois do encerramento do grid anterior.

**Não executados:** compilação pelo MetaEditor, script `ImpulseGridTests.mq5`, Strategy Tester, otimização e forward/demo. Não foi encontrado MetaEditor nos diretórios de instalação usuais e na árvore MetaQuotes pesquisada. O ambiente também não forneceu histórico/ticks de uma corretora MT5 para executar os cenários de mercado.

Os testes portáveis não comprovam compatibilidade binária MQL5, integração CTrade, ordem real dos eventos do servidor, slippage ou desempenho. A aprovação para uso depende dos testes nativos descritos em `ACCEPTANCE.md`; não há `.ex5` validado nesta entrega.
