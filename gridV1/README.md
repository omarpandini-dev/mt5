**ImpulseGrid — Expert Advisor MQL5 para MT5**

Implementação de grid por candle de impulso, com níveis fixos, reciclagem e confirmação contínua até a primeira entrada. O arquivo principal é `ImpulseGrid.mq5`; a pasta `ImpulseGrid` contém os módulos e precisa acompanhá-lo.

**Estado da validação:** foram executados 26 cenários portáveis sobre funções extraídas do código de produção, incluindo reconstrução NETTING/HEDGING com uma corretora simulada. Isso não equivale a compilar MQL5. MetaEditor/MetaTrader 5 não foram encontrados neste ambiente; compilação nativa, script de testes MQL5, Strategy Tester e forward em demo ainda precisam ser executados. Não há arquivo `.ex5` ou resultado de rentabilidade certificado nesta entrega.

**Instalação e compilação**

1. No MT5, abra **Arquivo → Abrir Pasta de Dados → MQL5 → Experts**.
2. Crie uma pasta `ImpulseGridEA`. Copie para ela `ImpulseGrid.mq5` e a subpasta `ImpulseGrid` inteira.
3. Abra o arquivo principal no MetaEditor e pressione **F7**. Confira o resultado da compilação antes de executar.
4. No Strategy Tester, selecione o EA, o contrato WIN efetivamente disponível na corretora e o período de teste. Prefira **Cada tick baseado em ticks reais**, quando os dados estiverem disponíveis. Verifique custos, especificação do contrato e horário do servidor.
5. Execute os casos de `tests/ACCEPTANCE.md`, incluindo as duas modalidades de conta. Só depois faça forward em conta demo.

Também é possível compilar os arquivos diretamente desta pasta, informando uma instalação existente do MetaEditor:

```powershell
.\tools\compile.ps1 -MetaEditor 'C:\caminho\MetaTrader 5\metaeditor64.exe' -IncludeTests
```

O script exige **0 errors, 0 warnings** nos logs. Ele não instala programas, não abre o terminal para operar e não inicia backtests.

Para executar os testes MQL5, copie `tests/ImpulseGridTests.mq5` para `MQL5/Scripts/ImpulseGridTests/` e a pasta de módulos para `MQL5/Scripts/ImpulseGrid/`, preservando o caminho relativo `../ImpulseGrid/`. Compile e execute o script com parâmetros padrão. Ele testa funções de produção e arquivos de teste; não envia ordens. O resultado aparece na aba **Experts**.

Os testes portáveis já executados podem ser repetidos com Node.js:

```powershell
node tests/smoke.mjs
```

Eles extraem corpos de funções MQL5, adaptam declarações/casts escalares e simulam APIs do terminal. Validam cenários de lógica e contabilidade, mas não validam o compilador, a biblioteca CTrade, o protocolo da corretora ou desempenho no Tester.

**Divisão do código**

| Arquivo | Responsabilidade |
| --- | --- |
| `ImpulseGrid.mq5` | Inicialização, validação de parâmetros, prioridade de risco e eventos do terminal. |
| `Types.mqh` | Inputs agrupados, enums, níveis, pernas e estado persistente. |
| `Signals.mqh` | Candles fechados, volume, amplitude/ATR e corpo mínimo. |
| `Ledger.mqh` | Reconstrução por ordens/deals, posições, parciais, propriedade e resultados. |
| `Execution.mqh` | Envio, pré-validação, cancelamento, TP, stop individual e barreiras contra duplicação. |
| `Manager.mqh` | Ciclo do grid, confirmação, inversão, horários, limites e encerramento. |
| `Persistence.mqh` | Lock exclusivo, snapshots alternados, checksum e restauração. |
| `Dashboard.mqh` | Painel por grid/nível e estatísticas no diário. |

**Sinal e confirmação contínua**

O sinal usa exclusivamente `TimeframeSinal`, resolvido na inicialização. `PERIOD_CURRENT` usa o timeframe do gráfico naquele momento. O candle em formação nunca gera sinal. Para analisar o candle de shift `k`, as médias usam `k+1` em diante; o ATR também usa `k+1`, excluindo o próprio impulso da referência.

No volume automático, o EA usa volume real quando há valores positivos no candle e em toda a janela de comparação. Caso contrário, usa tick volume para a janela inteira, evitando misturar unidades. No modo REAL, a falta de volume suficiente impede o sinal. Falta de histórico/ATR é tratada como indisponibilidade de dados; não é interpretada como candle sem gatilho.

As opções do enum são `VOLUME_AUTOMATICO`, `USAR_VOLUME_REAL` e `USAR_VOLUME_TICK`. Os dois últimos nomes evitam redefinir `VOLUME_REAL`/`VOLUME_TICK`, que já são constantes nativas de MQL5. [Constantes oficiais de volume](https://www.mql5.com/en/docs/constants/indicatorconstants/prices).

Um gatilho cria o grid não confirmado. Cada novo candle fechado precisa passar novamente por **todos** os filtros na mesma direção. Um candle comum da mesma cor não basta. Os timestamps impedem validar o original como confirmação ou contar o mesmo candle duas vezes. Na recuperação, os candles fechados perdidos são examinados em sequência antes de novas entradas.

A primeira entrada, inclusive parcial, confirma definitivamente o GridID. Depois dela, candles sem gatilho ou contrários não invalidam esse grid. Um gatilho contrário anterior à primeira entrada fica armazenado durante os cancelamentos e só pode criar o novo grid depois de desaparecer toda exposição antiga. Candles que fecharem durante essa espera também precisam preservar a validade do sinal armazenado. Se houver preenchimento na corrida com o cancelamento, a exposição será encerrada e a inversão descartada.

**Níveis, execução e reciclagem**

As distâncias da estratégia são **unidades de preço**: fechamento 190600 menos distância 100 resulta em 190500. Não se aplica `_Point` às distâncias do grid ou ao alvo. `DesvioMaximoPontos`, por ser parâmetro de execução do MT5, é expresso em pontos MT5.

O tick size, os dígitos e os limites/passo de lote vêm do símbolo. Distâncias que não sejam múltiplos exatos do tick e lotes fora do passo são rejeitados na inicialização. Não há tick de cinco pontos fixado no código do EA. Os preços originais e os alvos são persistidos e não acompanham preço médio, mercado ou candles posteriores.

Ordens são BUY LIMIT na compra e SELL LIMIT na venda. Se o mercado já ultrapassou um nível e a LIMIT não puder ser colocada validamente, o EA espera; não converte a entrada em ordem a mercado. São verificados sessão de negociação, permissões, tipo de ordem, distância mínima, freeze level e `OrderCheck`. Restrições finais continuam sujeitas ao servidor.

No modo TODAS, todos os níveis elegíveis são enviados sequencialmente, com reconciliação entre envios. No modo PROXIMA, a primeira execução do nível anterior libera o seguinte. Parciais da mesma ordem contam como uma execução. O saldo pendente de uma entrada parcialmente preenchida é cancelado antes de o EA fechar/rearmar essa perna. A coexistência transitória de posição e saldo pendente é inerente ao preenchimento parcial da bolsa e não pode ser eliminada pelo cliente.

Após uma saída integral pelo TP normal, o nível pode voltar ao mesmo preço original, respeitando delay e limite de execuções. `DelayReentradaSegundos=0` não adiciona espera após a confirmação; rejeições definitivas de entrada/saída têm intervalo mínimo de dois segundos entre tentativas. Stops individuais só permitem reciclagem quando `RearmarAposStopIndividual=true`. Saídas manuais, stops globais/diários e cancelamentos não liberam rearme.

**NETTING e HEDGING**

Em HEDGING, cada posição é associada pelo identificador estável da posição e pelas ordens/deals do nível. O EA utiliza TP no servidor quando o símbolo e as distâncias permitem, e tenta instalá-lo posteriormente se necessário. Sem TP instalado, o alvo é gerenciado virtualmente.

Em NETTING, o terminal consolida o símbolo em uma posição. As pernas virtuais preservam volume, execução real e alvo de cada nível. A saída de L2 envia uma operação oposta limitada ao volume de L2, com ticket da posição e comentário identificador; L1 permanece no registro interno. `CTrade::PositionClosePartial` é específico de HEDGING, por isso essas saídas usam `MqlTradeRequest` explícito. [Referência oficial do método](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclosepartial).

NETTING exige **uso exclusivo do símbolo** por esta estratégia. MagicNumber não separa fisicamente posições consolidadas. Posição/ordem alheia, entrada de outro Magic ou divergência persistente entre pernas e posição bloqueia novas operações. O EA cancela suas pendentes mapeadas e preserva a posição cuja propriedade esteja ambígua. Não tente compartilhar o mesmo símbolo com operação manual ou outro EA. Um cliente não consegue impedir que outro cliente negocie no mesmo instante.

Em ambas as modalidades, fechamento manual de uma exposição identificada ou cancelamento manual de pendente encerra o restante do grid, sem reciclagem. Em NETTING, uma saída manual não identificada por nível consome o registro virtual em FIFO apenas para reconciliar o saldo e acionar esse encerramento; não é tratada como TP.

**Resultado financeiro, prioridades e horário**

O resultado global usa o realizado real da corretora (`profit + commission + swap + fee` nos deals atribuídos) mais lucro/swap das posições abertas. Não se substitui o lucro realizado do NETTING por um lucro teórico de cada perna, pois isso duplicaria ganhos em relação ao preço médio da corretora. O stop individual usa a marcação da perna ao preço de execução e seus custos de ciclo; o resultado contábil por nível segue os deals efetivos. Encargos lançados separadamente sem símbolo/atribuição não podem ser rateados automaticamente.

Stop/alvo global em zero ficam desabilitados. Valores monetários são na **moeda da conta**, não necessariamente reais. O resultado diário é do símbolo/Magic, desde meia-noite do servidor, somado ao flutuante atual completo. Não é a variação da equity desde meia-noite nem um limite para a conta inteira. Um grid atravessando a meia-noite continua gerenciado; o bloqueio e contador de novos grids do dia são reiniciados.

A ordem de decisão no cliente é stop global, stop diário, integridade/propriedade, alvo global, alvo diário, horário/invalidação, stop individual, TP e entradas/rearmes. Um TP no servidor pode executar antes de uma decisão local; não existe prioridade absoluta sobre operações que o servidor já executou. Encerramentos cancelam pendentes e repetem as tentativas necessárias de saída, sem autorizar um novo GridID enquanto houver exposição ou envio pendente de confirmação.

Os horários são do **servidor**, com início inclusivo e fim exclusivo; janelas atravessando meia-noite são aceitas. MANTER permite gerenciar e reciclar o grid existente fora da janela, mas não iniciar outro. CANCELAR_PENDENTES_MANTER_POSICOES desliga definitivamente entradas/rearmes daquele GridID e mantém suas posições sob risco/TP até ficarem zeradas. ENCERRAR_GRID solicita encerramento total.

Stops financeiros, TP virtual NETTING e outras decisões locais precisam de EA ativo, conexão e mercado disponível. Não há SL financeiro garantido no servidor; gaps, slippage e rejeições podem ultrapassar os valores configurados. Remover o EA **não fecha posições**: o estado é salvo para retomada. Para encerrar manualmente, mantenha o EA ligado ao fechar/cancelar a exposição, permitindo que ele detecte a intervenção.

**Persistência, reinício e incerteza**

Fora do Tester, dois snapshots `.a`/`.b` e um lock `.lock` ficam em **Terminal/Common/Files**, com prefixo `ImpulseGrid_<conta>_<hash-servidor>_<hash-simbolo>_<magic>`. O arquivo válido de maior sequência é escolhido. O checksum detecta corrupção/truncamento, e a outra cópia preserva o último estado válido. Arquivos binários preservam tickets de 64 bits e a estrutura inteira; não dependem de representar tickets como `double` em Global Variables.

O estado inclui preços, candle original, última validação, primeira entrada, sinal contrário retido, contadores e intenções de envio. Após carregar, ordens, deals e posições são reconciliados. O ledger é recalculado deterministamente, com deduplicação por deal e execução contada por ordem de entrada. A ordem de chegada de eventos de negociação não é garantida pelo MT5; por isso desaparecimento de ordem sem os negócios correspondentes suspende o rearme. [Referência oficial de OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction).

Uma intenção é gravada **antes** de enviar uma operação. Timeout ou perda de conexão não autoriza repetição automática. O EA procura o ticket/comentário nas ordens e no histórico e espera resultado conclusivo. Sem evidência, mantém a barreira de envio: segurança contra duplicação tem precedência sobre continuar operando. Essa barreira também pode retardar fechamentos locais, pois uma saída incerta não pode ser repetida sem risco de inverter a posição.

É necessário manter os dois arquivos de estado e o histórico da corretora. Se ambos os snapshots estiverem corrompidos, houver exposição órfã, comentários irreconhecíveis ou histórico inconsistente, o EA bloqueia em vez de inventar níveis. Essa condição não é uma reconstrução garantida a partir de qualquer conjunto incompleto de dados. Enquanto houver grid ativo, mudanças de parâmetros/tipo de conta são recusadas; retome com a configuração original.

O lock impede instâncias concorrentes no mesmo computador/área Common. Não coordena computadores distintos. No Tester, o estado usa a área de arquivos local do agente e é limpo a cada passe, evitando contaminar otimizações.

Em isolamento persistente, falha de disco ou envio sem resultado, examine **Experts**, ordens, posições e histórico com a corretora. Não exclua snapshots com exposição ou envio incerto. Depois de confirmar que o símbolo/Magic está inteiramente zerado e que não há solicitações em trânsito, remova o EA, arquive os dois snapshots correspondentes e reinicie, se precisar abandonar o estado antigo. Isso também reinicia os contadores persistentes de grids; considere esse efeito sobre os limites do dia.

**Otimização e estatísticas**

Os parâmetros pedidos estão disponíveis para otimização no Strategy Tester:

| Grupo | Parâmetros |
| --- | --- |
| Sinal | `MultiplicadorVolume`, `MultiplicadorAmplitude`, `PercentualMinimoCorpo`; no modo ATR, `MultiplicadorATR` e `PeriodoATR`. |
| Construção | `DistanciaPrimeiraEntrada`, `DistanciaEntreEntradas`, `MaximoNiveisGrid`. |
| Reciclagem | `AlvoPontosPorEntrada`, `MaximoExecucoesPorNivel`, `DelayReentradaSegundos`. |
| Risco | `StopFinanceiroGlobal`, `AlvoFinanceiroGlobal`. |
| Comparação da regra | `UsarConfirmacaoContinuaGatilho` true/false; opcionalmente `MaximoCandlesSemEntrada`. |

Use passos compatíveis com o tick real para as distâncias. Separe amostras de ajuste e de validação e compare a regra de confirmação ligada/desligada sobre os mesmos dados/custos. Os valores padrão reproduzem o pedido; não representam calibração validada para uso real. O critério customizado de `OnTester` retorna o lucro líquido do relatório padrão (`STAT_PROFIT`), e as métricas adicionais são registradas no diário do agente.

O painel mostra estado, identificação/direção do grid, candle original, confirmação, níveis, ordens, posições, execuções e resultados. Ao término são registrados grids criados, com entrada, cancelados sem entrada, cancelados sem confirmação, inversões efetivamente iniciadas, confirmações consecutivas, execuções, reciclagens e resultado. A porcentagem de primeira entrada usa grids criados; a média de espera usa candles completos dos grids cuja espera terminou por primeira entrada ou cancelamento, excluindo espera ainda em andamento.
