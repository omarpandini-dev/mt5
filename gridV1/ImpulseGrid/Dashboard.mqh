#ifndef IMPULSE_DASHBOARD_MQH
#define IMPULSE_DASHBOARD_MQH
void UpdateDashboard()
{
 int positions=0,orders=0,executions=0;
 for(int p=PositionsTotal()-1;p>=0;p--) if(PositionGetTicket(p)>0 && OwnPosition()) positions++;
 for(int o=OrdersTotal()-1;o>=0;o--) if(OrderGetTicket(o)>0 && OwnOrder()) orders++;
 string rows="";
 for(int i=0;i<S.niveis;i++)
 {
   executions+=S.levels[i].quantidadeExecucoes;
   rows+=StringFormat("L%d | %.*f -> %.*f | %s | Exec: %d | Vol: %.2f\n",i+1,
     (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),S.levels[i].precoEntrada,
     (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS),S.levels[i].precoAlvo,
     EnumToString((EstadoNivel)S.levels[i].estado),S.levels[i].quantidadeExecucoes,legs[i].volume);
 }
 string text=StringFormat("IMPULSE GRID | EA %s | %s | %s | %s\nEstado: %s | GridID: %I64d | %s\n",
    (S.isolado || ioFailure ? "BLOQUEADO" : "ATIVO"),_Symbol,EnumToString(signalTF),hedging ? "HEDGING" : "NETTING",
    EnumToString((EstadoEA)S.EstadoAtual),S.GridID,EnumToString((TipoGatilho)S.direcao));
 text+="Candle original: "+TimeToString(S.CandleGatilhoTime)+" | Validado: "+TimeToString(S.UltimoCandleValidacaoTime)+"\n";
 text+="Grid confirmado / primeira entrada: "+(S.GridJaTeveEntrada ? "SIM" : "NAO")+
   " | Ultimo candle confirmou: "+(S.ultimoConfirmou ? "SIM" : "NAO")+"\n";
 text+=StringFormat("Niveis: %d | Posicoes: %d | Pendentes: %d | Execucoes grid: %d\n",S.niveis,positions,orders,executions);
 text+=StringFormat("Realizado: %.2f | Flutuante: %.2f | Total: %.2f %s\nStop: %.2f | Alvo: %.2f | Dia: %.2f\n",
   realized,CalculateGridFloatingResult(),CalculateGridTotalResult(),AccountInfoString(ACCOUNT_CURRENCY),
   StopFinanceiroGlobal,AlvoFinanceiroGlobal,CalculateDailyResult());
 text+=StringFormat("Grids: %I64d | Com entrada: %I64d | Cancelados sem entrada: %I64d | Inversoes: %I64d\n",
   S.grids,S.comEntrada,S.canceladosSemEntrada,S.inversoes);
 if(HasIntents()) text+="Envio em reconciliacao: entradas e novos fechamentos aguardam confirmacao.\n";
 if(fault!="") text+="AVISO: "+fault+"\n";
 Comment(text+rows);
}
void PrintStatistics()
{
 long executions=S.execucoesConcluidas,recycles=S.reciclagensConcluidas;
 for(int i=0;i<S.niveis;i++)
 { executions+=S.levels[i].quantidadeExecucoes; recycles+=(long)MathMax(0,S.levels[i].quantidadeExecucoes-1); }
 double rate=S.grids>0 ? 100.0*S.comEntrada/S.grids : 0;
 double avg=S.gridsEsperaFinalizada>0 ? (double)S.candlesEsperaTotal/S.gridsEsperaFinalizada : 0;
 PrintFormat("ESTATISTICAS grids=%I64d; com_entrada=%I64d; cancelados_sem_entrada=%I64d; sem_confirmacao=%I64d; inversoes=%I64d; mantidos=%I64d; execucoes=%I64d; reciclagens=%I64d; primeira_entrada_pct=%.2f; media_candles_espera=%.2f; resultado=%.2f",
   S.grids,S.comEntrada,S.canceladosSemEntrada,S.semConfirmacao,S.inversoes,S.mantidos,executions,recycles,rate,avg,
   S.resultadoConcluido+CalculateGridTotalResult());
}
#endif
