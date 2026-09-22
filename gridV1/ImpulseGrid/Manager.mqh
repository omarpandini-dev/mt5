#ifndef IMPULSE_MANAGER_MQH
#define IMPULSE_MANAGER_MQH
bool InSchedule()
{
 if(!UsarFiltroHorario) return true;
 MqlDateTime d; TimeToStruct(TimeCurrent(),d); int m=d.hour*60+d.min;
 if(startMinute<endMinute) return m>=startMinute && m<endMinute;
 return m>=startMinute || m<endMinute; // Janela que atravessa meia-noite.
}
void BeginClose(MotivoEncerramentoGrid reason)
{
 if(!IsActive() || IsClosing()) return;
 S.PermitirRearmeGrid=false; S.EstadoAtual=ENCERRANDO_GRID; S.motivo=reason;
 if(reason!=GATILHO_CONTRARIO) { S.pendingSignalTime=0; S.pendingSignalDirection=SEM_GATILHO; }
 Print("Encerrando grid ",S.GridID," motivo=",EnumToString(reason)); SaveGridState();
}
void CancelUnconfirmedGrid(string reason)
{
 if(S.GridJaTeveEntrada) return;
 Print(reason);
 BeginClose(SEM_CONFIRMACAO_GATILHO);
}
void HandleOppositeTrigger(TipoGatilho trigger)
{
 if(S.GridJaTeveEntrada) return;
 S.pendingSignalDirection=trigger;
 Print("Gatilho contrario detectado. Aguardando cancelamento completo.");
 BeginClose(GATILHO_CONTRARIO);
}
void CheckGlobalStop()
{ if(IsActive() && StopFinanceiroGlobal>0 && CalculateGridTotalResult()<=-StopFinanceiroGlobal) BeginClose(STOP_GLOBAL); }
void CheckGlobalTarget()
{ if(IsActive() && AlvoFinanceiroGlobal>0 && CalculateGridTotalResult()>=AlvoFinanceiroGlobal) BeginClose(TARGET_GLOBAL); }
void CheckDailyLimits(bool stopsOnly=false)
{
 double result=CalculateDailyResult();
 if(UsarStopDiario && result<=-StopFinanceiroDiario)
 {
   S.dayBlocked=true; S.pendingSignalTime=0;
   if(IsActive()) BeginClose(STOP_DIARIO); else S.EstadoAtual=BLOQUEADO_DIA;
 }
 else if(!stopsOnly && UsarAlvoDiario && result>=AlvoFinanceiroDiario)
 {
   S.dayBlocked=true; S.pendingSignalTime=0;
   if(IsActive()) BeginClose(ALVO_DIARIO); else S.EstadoAtual=BLOQUEADO_DIA;
 }
}
void CheckSchedule()
{
 if(!IsActive() || InSchedule() || !UsarFiltroHorario || IsClosing()) return;
 if(RegraFimHorario==ENCERRAR_GRID) BeginClose(FIM_HORARIO);
 else if(RegraFimHorario==CANCELAR_PENDENTES_MANTER_POSICOES)
 {
   if(S.PermitirRearmeGrid) { S.PermitirRearmeGrid=false; S.motivo=FIM_HORARIO; SaveGridState(); }
   CancelPendingGridOrders();
 }
}
void BuildGridLevels()
{
 double sign=S.direcao==GATILHO_COMPRA ? 1 : -1;
 for(int i=0;i<S.niveis;i++)
 {
   ZeroMemory(S.levels[i]); ZeroMemory(legs[i]);
   S.levels[i].gridId=S.GridID; S.levels[i].numeroNivel=i+1; S.levels[i].direcao=S.direcao;
   S.levels[i].precoEntrada=NormalizePriceToTick(S.CandleGatilhoClose-sign*PointsToPrice(DistanciaPrimeiraEntrada+i*DistanciaEntreEntradas));
   S.levels[i].precoAlvo=NormalizePriceToTick(S.levels[i].precoEntrada+sign*PointsToPrice(AlvoPontosPorEntrada));
   S.levels[i].volume=NormalizeVolume(LotePadrao);
   S.levels[i].habilitado=(i==0 || ModoGrid==TODAS_ORDENS_IMEDIATAMENTE);
   S.levels[i].estado=S.levels[i].habilitado ? NIVEL_AGUARDANDO_ORDEM : NIVEL_INATIVO;
 }
}
bool StartGrid(TipoGatilho trigger,datetime candle)
{
 if(IsActive() || HasOwnExposure() || HasIntents() || S.isolado || S.dayBlocked || ioFailure || !historyReady ||
    trigger==SEM_GATILHO || !InSchedule() || !NettingExclusive()) return false;
 if(MaximoGridsPorDia>0 && S.gridsDia>=MaximoGridsPorDia) return false;
 int shift=iBarShift(_Symbol,signalTF,candle,true); if(shift<1) return false;
 MqlRates b; double v,a,r; if(!ReadSignalData(shift,b,v,a,r)) return false;
 // Signal ID usa o tempo de criacao, monotono mesmo com dois grids no mesmo segundo.
 S.GridID=(long)MathMax((long)TimeCurrent(),S.lastGridID+1); S.lastGridID=S.GridID;
 S.direcao=trigger; S.niveis=MaximoNiveisGrid; S.GridJaTeveEntrada=false; S.PermitirRearmeGrid=true;
 S.EstadoAtual=(trigger==GATILHO_COMPRA ? GRID_AGUARDANDO_PRIMEIRA_ENTRADA_COMPRA : GRID_AGUARDANDO_PRIMEIRA_ENTRADA_VENDA);
 S.CandleGatilhoTime=b.time; S.CandleGatilhoOpen=b.open; S.CandleGatilhoHigh=b.high;
 S.CandleGatilhoLow=b.low; S.CandleGatilhoClose=b.close; S.CandleGatilhoVolume=v;
 S.CandleGatilhoAmplitude=b.high-b.low; S.UltimoCandleValidacaoTime=b.time; S.ultimoConfirmou=true;
 S.candlesEspera=0; S.motivo=MOTIVO_NENHUM; realized=0; S.grids++; S.gridsDia++;
 BuildGridLevels();
 if(!SaveGridState()) return false;
 Print("Candle gatilho de ",trigger==GATILHO_COMPRA ? "ALTA" : "BAIXA"," identificado: ",TimeToString(candle));
 Print("Grid criado e aguardando primeira entrada. GridID=",S.GridID);
 return true;
}
void StartBuyGrid() { StartGrid(GATILHO_COMPRA,iTime(_Symbol,signalTF,1)); }
void StartSellGrid() { StartGrid(GATILHO_VENDA,iTime(_Symbol,signalTF,1)); }
void ClearGridState()
{
 S.GridID=0; S.niveis=0; S.direcao=SEM_GATILHO; S.GridJaTeveEntrada=false; S.PermitirRearmeGrid=false;
 S.manualDetected=false;
 S.EstadoAtual=S.dayBlocked ? BLOQUEADO_DIA : AGUARDANDO_SINAL; realized=0;
 for(int i=0;i<MAX_LEVELS;i++) { ZeroMemory(S.levels[i]); ZeroMemory(legs[i]); }
}
void FinishGrid()
{
 if(HasOwnExposure() || HasIntents() || !historyReady || dirty) return;
 for(int i=0;i<S.niveis;i++) if(legs[i].ativa) return;
 if(!S.GridJaTeveEntrada)
 {
   S.canceladosSemEntrada++; S.candlesEsperaTotal+=S.candlesEspera; S.gridsEsperaFinalizada++;
   if(S.motivo==SEM_CONFIRMACAO_GATILHO) S.semConfirmacao++;
 }
 // Um fill durante cancelamento e encerrado como protecao; nao inverter em seguida.
 if(S.GridJaTeveEntrada) S.pendingSignalTime=0;
 for(int i=0;i<S.niveis;i++)
 {
   S.execucoesConcluidas+=S.levels[i].quantidadeExecucoes;
   S.reciclagensConcluidas+=(long)MathMax(0,S.levels[i].quantidadeExecucoes-1);
 }
 S.resultadoConcluido+=realized;
 Print("Grid anterior encerrado. GridID=",S.GridID," resultado=",DoubleToString(realized,2));
 ClearGridState(); SaveGridState();
}
void CloseEntireGrid()
{
 if(!IsClosing()) return;
 CancelPendingGridOrders();
 if(dirty && (!RebuildGridState() || ledgerError || !NettingExclusive())) return;
 for(int i=0;i<S.niveis;i++) if(legs[i].ativa)
 { CloseLeg(i,3); if(dirty || HasIntents()) return; }
 FinishGrid();
}
void StartPendingSignal()
{
 if(IsActive() || S.pendingSignalTime==0 || !historyReady || dirty) return;
 if(S.dayBlocked || !InSchedule() || S.isolado)
 { S.pendingSignalTime=0; SaveGridState(); return; }
 datetime candle=S.pendingSignalTime; TipoGatilho direction=(TipoGatilho)S.pendingSignalDirection;
 if(StartGrid(direction,candle))
 {
   S.pendingSignalTime=0; S.pendingSignalDirection=SEM_GATILHO; S.inversoes++;
   // Ja validamos os candles que fecharam durante os cancelamentos.
   S.UltimoCandleValidacaoTime=iTime(_Symbol,signalTF,1);
   Print("Iniciando novo grid na direcao contraria."); SaveGridState();
 }
}
void ValidateUnconfirmedCandle(TipoGatilho trigger,datetime candle)
{
 if(!IsActive() || IsClosing() || S.GridJaTeveEntrada || candle<=S.UltimoCandleValidacaoTime) return;
 S.UltimoCandleValidacaoTime=candle; S.candlesEspera++;
 S.ultimoConfirmou=((int)trigger==S.direcao);
 Print("Novo candle fechado sem execucao do grid: ",TimeToString(candle));
 if(UsarConfirmacaoContinuaGatilho && !S.ultimoConfirmou)
 {
   if(trigger==SEM_GATILHO) CancelUnconfirmedGrid("GRID_SEM_ENTRADA_SEM_CONFIRMACAO");
   else { S.pendingSignalTime=candle; HandleOppositeTrigger(trigger); }
 }
 else if(MaximoCandlesSemEntrada>0 && S.candlesEspera>=MaximoCandlesSemEntrada) BeginClose(LIMITE_CANDLES);
 else if(S.ultimoConfirmou)
 { S.mantidos++; Print("Candle confirmou gatilho. Grid mantido com precos originais."); }
}
void ProcessNewClosedBar()
{
 datetime current=iTime(_Symbol,signalTF,0);
 if(current<=0 || current==S.lastBar) return;
 int first=1;
 if(S.lastBar>0)
 {
   first=iBarShift(_Symbol,signalTF,S.lastBar,true);
   if(first<0) { fault="Historico nao cobre ultimo candle processado"; return; }
 }
 for(int shift=first;shift>=1;shift--)
 {
   datetime candle=iTime(_Symbol,signalTF,shift); if(candle<=0) return;
   bool available; TipoGatilho trigger=EvaluateSignal(shift,available);
   if(!available) { fault="Aguardando dados completos do sinal"; return; }
   if(IsClosing() || (!IsActive() && S.pendingSignalTime>0))
   {
     if(S.pendingSignalTime>0 && candle>S.pendingSignalTime && (int)trigger!=S.pendingSignalDirection)
     { S.pendingSignalTime=0; S.pendingSignalDirection=SEM_GATILHO; }
   }
   else if(IsActive() && !S.GridJaTeveEntrada && candle>S.UltimoCandleValidacaoTime)
     ValidateUnconfirmedCandle(trigger,candle);
   else if(!IsActive() && S.pendingSignalTime==0 && shift==1 && trigger!=SEM_GATILHO)
     StartGrid(trigger,candle); // Nao abrir novos grids retroativamente.
   S.lastBar=iTime(_Symbol,signalTF,shift-1);
   if(!SaveGridState()) return;
 }
 S.lastBar=current;
}
void ManageGrid(bool allowEntries=true)
{
 if(!IsActive() || S.isolado || !historyReady || ioFailure) return;
 if(IsClosing()) { CloseEntireGrid(); return; }
 CancelPendingGridOrders(true); if(dirty) return;
 if(hedging) ManageHedgingPositions(); else ManageNettingLegs();
 if(dirty || HasIntents()) return;
 if(!S.PermitirRearmeGrid)
 {
   if(!HasOwnExposure()) BeginClose(FIM_HORARIO);
   return;
 }
 if(!allowEntries) return;
 bool exhausted=true;
 for(int i=0;i<S.niveis;i++)
 {
   if(legs[i].ativa || S.levels[i].ticketOrdem>0) exhausted=false;
   if(!S.levels[i].finalizado && S.levels[i].estado!=NIVEL_FINALIZADO &&
     (MaximoExecucoesPorNivel==0 || S.levels[i].quantidadeExecucoes<MaximoExecucoesPorNivel)) exhausted=false;
   if(LevelCanBeRearmed(i))
   {
     RearmGridLevel(i);
     if(dirty)
     {
       if(!RebuildGridState() || ledgerError || !NettingExclusive() || HasIntents()) return;
       CheckGlobalStop(); CheckDailyLimits(true); CheckGlobalTarget(); CheckDailyLimits();
       if(IsClosing() || S.dayBlocked) return;
     }
   }
 }
 if(exhausted) BeginClose(NIVEIS_ESGOTADOS);
}
#endif
