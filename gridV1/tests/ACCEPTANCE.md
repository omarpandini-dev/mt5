**Roteiro de aceitação no MT5 — pendente de execução nativa**

Registre versão/build do terminal, corretora, símbolo, especificação de tick/lote, moeda da conta, modalidade, período, qualidade de ticks e `.set` utilizado. Compile EA e script com zero erros/avisos. O script `ImpulseGridTests.mq5` deve terminar sem FAIL.

Use o modo visual para os cenários de sinal e reciclagem. Para garantir sequências específicas, utilize um símbolo personalizado com barras/ticks importados ou encontre e registre os timestamps correspondentes na série da corretora. Os testes de desconexão, reinício e intervenções manuais exigem terminal/demo; o Tester sozinho não reproduz todas as condições do servidor.

| Caso | Ação e resultado esperado |
| --- | --- |
| Candle em formação | Alterar volume/preço dentro do candle: nenhum novo sinal antes do fechamento. |
| Timeframe independente | Gráfico M1, sinal M5: somente os fechamentos M5 participam. |
| Médias | Confirmar que o impulso não está incluído na média/ATR de referência. |
| Volume automático | Sem volume real na janela, toda a comparação usa ticks; nenhuma mistura. |
| Alta sem entrada | Fechamento 190600 e parâmetros padrão: L1 190500, L2 190450, L3 190400. |
| Continuidade | Dois novos impulsos de alta sem execução mantêm os mesmos preços. |
| Sem confirmação | Candle seguinte insuficiente cancela todo o grid sem entrada. |
| Mesma cor | Candle de alta sem volume/corpo/amplitude não confirma compra. |
| Entrada antes do fechamento | Primeiro fill, inclusive parcial, impede cancelamento por candle posterior. |
| Inversão | Sem fill, impulso contrário fica retido até cancelamento confirmado. Nenhum BUY/SELL grid simultâneo. |
| Inversão demorada | Novo candle sem confirmação durante cancelamento descarta o sinal retido. |
| Corrida fill/cancel | Fill durante cancelamento é reconciliado e encerrado; não dispara inversão automática. |
| NETTING | L1 190500 e L2 190450; em 190500, sai apenas o volume virtual de L2 e L1 continua. |
| Reciclagem | Após TP de L2, nova LIMIT permanece exatamente em 190450, inclusive após dez ciclos. |
| HEDGING | TP real por posição; saída de uma posição não fecha/rearma outro nível. |
| Parcial de entrada | Dois deals da mesma ordem contam uma execução; saldo pendente é cancelado; sem segunda entrada independente. |
| Parcial de saída | Nenhum rearme até todo o volume sair e a ordem de saída terminar. |
| Limite e delay | Limite 3 aceita três ciclos; delay conta da última saída integral. |
| Modo sequencial | L2 é liberado pelo primeiro fill de L1; níveis já liberados reciclam. |
| Stop individual | Encerra só a perna; sem rearme por padrão; com a opção ligada respeita delay/limite. |
| Stop global | Realizado 150 e flutuante -80 resultam em 70, sem zerar realizado na reciclagem. |
| Limites globais | Ao atingir stop/alvo, bloquear entradas antes de cancelar/fechar; repetir recusas sem duplicar saída. |
| Diário | Verificar reset à meia-noite do servidor, bloqueio até o dia seguinte e grids/dia sem contar rearmes. |
| Horário | Conferir as três ações; CANCELAR não volta a reciclar no dia seguinte. |
| Manual | Cancelar uma pendente ou fechar parte da exposição dispara encerramento do grid, sem rearme. |
| NETTING compartilhado | Ordem/entrada alheia bloqueia gestão automática da posição ambígua; trades alheios não são fechados. |
| Magic distinto HEDGING | Posições de outro EA/manual permanecem intactas. |
| Tick e lote | Distâncias fora do tick e lote fora do passo são recusados; nenhum hardcode de cinco pontos. |
| Mercado atravessou nível | Não transformar LIMIT inválida em entrada a mercado nem mover o nível. |
| Reinício sem fill | Restaurar preços/candle/última validação e processar candles perdidos antes de novas entradas. |
| Reinício com fill | `GridJaTeveEntrada` verdadeiro e contadores/realizado recuperados sem duplicação. |
| Reinício entre TP e rearme | Recuperar TP do histórico, rearmar uma única vez no preço original. |
| Reinício encerrando | Manter rearme bloqueado e continuar cancelamentos/saídas. |
| Snapshot interrompido | Com EA desligado em ambiente de teste, truncar a cópia mais recente: selecionar a outra válida. |
| Dois snapshots inválidos | Recusar inicialização; não inventar grid a partir de exposição incompleta. |
| Instância duplicada | Segundo EA com mesma conta/símbolo/Magic não consegue adquirir lock. |
| Timeout após envio | Verificar ordem/histórico antes de repetir; sem evidência, manter barreira. |
| Ordem antes do deal | Simular/observar ORDER_DELETE anterior ao DEAL_ADD: não rearmar nesse intervalo. |
| Otimização | Passes repetidos não herdam estado; parâmetros inválidos retornam INIT_PARAMETERS_INCORRECT. |

Arquive logs e relatórios por caso. Uma execução positiva dos testes portáveis não substitui estes testes. TP servidor, custos, regras de sessão, preenchimentos parciais e sequência de transações precisam ser confirmados com a infraestrutura que efetivamente será utilizada.
