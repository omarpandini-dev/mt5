#property strict
#property version "1.00"
#property description "Grid de impulso com niveis fixos, reconciliacao e confirmacao continua."
#include <Trade/Trade.mqh>
#include "ImpulseGrid/Types.mqh"
#include "ImpulseGrid/Signals.mqh"
#include "ImpulseGrid/Persistence.mqh"
#include "ImpulseGrid/Ledger.mqh"
#include "ImpulseGrid/Execution.mqh"
#include "ImpulseGrid/Manager.mqh"
#include "ImpulseGrid/Dashboard.mqh"

datetime mismatchSince=0;
bool ParseClock(string value,int &minutes)
{
 if(StringLen(value)!=5 || StringSubstr(value,2,1)!=":") return false;
 for(int i=0;i<5;i++) if(i!=2 && (StringGetCharacter(value,i)<'0' || StringGetCharacter(value,i)>'9')) return false;
 int h=(int)StringToInteger(StringSubstr(value,0,2)),m=(int)StringToInteger(StringSubstr(value,3,2));
 minutes=h*60+m; return h<24 && m<60;
}
bool ValidateInputs()
{
 if(MagicNumber<=0 || PeriodoMediaVolume<1 || PeriodoMediaAmplitude<1 || PeriodoATR<1 ||
    MultiplicadorVolume<=0 || MultiplicadorAmplitude<=0 || MultiplicadorATR<=0 ||
    PercentualMinimoCorpo<0 || PercentualMinimoCorpo>100 || MaximoNiveisGrid<1 || MaximoNiveisGrid>MAX_LEVELS ||
    DistanciaPrimeiraEntrada<=0 || DistanciaEntreEntradas<=0 || AlvoPontosPorEntrada<=0 ||
    MaximoExecucoesPorNivel<0 || DelayReentradaSegundos<0 || MaximoCandlesSemEntrada<0 ||
    MaximoGridsPorDia<0 || DesvioMaximoPontos<0 || StopFinanceiroGlobal<0 || AlvoFinanceiroGlobal<0 ||
    (UsarStopFinanceiroPorEntrada && StopFinanceiroPorEntrada<=0) ||
    (UsarStopDiario && StopFinanceiroDiario<=0) || (UsarAlvoDiario && AlvoFinanceiroDiario<=0)) return false;
 if(!ParseClock(HorarioInicio,startMinute) || !ParseClock(HorarioFinal,endMinute) || startMinute==endMinute) return false;
 if(tickSize<=0 || pointSize<=0 || volStep<=0 || volMin<=0 || volMax<volMin) return false;
 if(NormalizeVolume(LotePadrao)<=0 || MathAbs(NormalizeVolume(LotePadrao)-LotePadrao)>1e-8) return false;
 // Distancias devem caber exatamente no tick. Nao reduzir silenciosamente o espacamento.
 double distances[3]; distances[0]=DistanciaPrimeiraEntrada; distances[1]=DistanciaEntreEntradas; distances[2]=AlvoPontosPorEntrada;
 for(int i=0;i<3;i++) if(MathAbs(distances[i]/tickSize-MathRound(distances[i]/tickSize))>1e-6) return false;
 return true;
}
int OnInit()
{
 ZeroMemory(S); S.EstadoAtual=AGUARDANDO_SINAL; S.day=DayStart(TimeCurrent());
 signalTF=TimeframeSinal==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : TimeframeSinal;
 hedging=AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
 if(!SymbolSelect(_Symbol,true)) return INIT_FAILED;
 tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); pointSize=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
 volStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP); volMin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
 volMax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
 if(!ValidateInputs()) { Print("Parametros invalidos: conferir lotes, distancias/tick, periodos e horarios."); return INIT_PARAMETERS_INCORRECT; }
 trade.SetExpertMagicNumber((ulong)MagicNumber); trade.SetDeviationInPoints((ulong)DesvioMaximoPontos);
 trade.SetAsyncMode(false); trade.SetMarginMode();
 atrHandle=iATR(_Symbol,signalTF,PeriodoATR); if(atrHandle==INVALID_HANDLE) return INIT_FAILED;
 if(!InitStorage()) return INIT_FAILED;
 if(!IsActive() && HasOwnExposure())
 { Print("Exposicao orfa sem snapshot ativo. Novos envios bloqueados; recuperar arquivos originais."); return INIT_FAILED; }
 if(S.lastBar==0 || (!IsActive() && S.pendingSignalTime==0)) S.lastBar=iTime(_Symbol,signalTF,0);
 // Dados podem ainda estar sincronizando no OnInit; repetir no primeiro tick/timer.
 RebuildGridState();
 ready=true; dirty=true;
 if(!EventSetTimer(1)) return INIT_FAILED;
 Print("ImpulseGrid iniciado. Pontos de estrategia = unidades de preco; moeda=",AccountInfoString(ACCOUNT_CURRENCY));
 return INIT_SUCCEEDED;
}
void RunEngine(bool allowSignals)
{
 if(!ready || busy) return; busy=true;
 datetime now=TimeCurrent();
 bool dayChanged=DayStart(now)!=S.day;
 if(dayChanged)
 {
   S.day=DayStart(now); S.dayBlocked=false; S.gridsDia=0;
   if(!IsActive()) S.EstadoAtual=AGUARDANDO_SINAL;
   dirty=true;
 }
 bool synced=false;
 if(dirty || now!=lastHistorySync) synced=RebuildGridState();
 if(!historyReady) { UpdateDashboard(); busy=false; return; }
 // Detectar primeiro fills/saidas antes de avaliar qualquer invalidacao de candle.
 CheckGlobalStop(); CheckDailyLimits(true);
 bool coherent=!ledgerError && NettingExclusive();
 if(!coherent)
 {
   if(mismatchSince==0) mismatchSince=now;
   fault="Reconciliacao divergente; novas operacoes suspensas";
   // Atualizacoes de order/deal/position nao possuem ordem de chegada garantida.
   // Aguardar estabilizacao antes de registrar isolamento persistente.
   if(now-mismatchSince>=3)
   {
     if(!S.isolado) { S.isolado=true; S.PermitirRearmeGrid=false; Print(fault,". Verificar uso exclusivo NETTING/historico."); SaveGridState(); }
     CancelPendingGridOrders();
   }
   UpdateDashboard(); busy=false; return;
 }
 mismatchSince=0;
 if(!ioFailure) fault="";
 if(S.isolado) { fault="Isolamento persistente: reconciliar exposicao antes de retomar."; UpdateDashboard(); busy=false; return; }
 if(externalExit && !IsClosing()) BeginClose(ENCERRAMENTO_MANUAL);
 CheckGlobalTarget(); CheckDailyLimits(false); CheckSchedule();
 if(synced || dayChanged) SaveGridState();
 if(allowSignals && IsNewBar() && !dirty) ProcessNewClosedBar();
 if(!dirty) ManageGrid(!IsNewBar());
 if(allowSignals && !IsNewBar()) StartPendingSignal();
 UpdateDashboard(); busy=false;
}
void OnTick() { RunEngine(true); }
void OnTimer() { RunEngine(false); }
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
 if(!ready) return;
 if(trans.type==TRADE_TRANSACTION_REQUEST && request.magic==(ulong)MagicNumber && request.symbol==_Symbol && !Accepted(result.retcode))
   PrintFormat("Transacao rejeitada/incerta: %u %s",result.retcode,result.comment);
 if(trans.type==TRADE_TRANSACTION_REQUEST && request.magic==(ulong)MagicNumber && request.symbol==_Symbol &&
    (request.action==TRADE_ACTION_PENDING || request.action==TRADE_ACTION_DEAL))
 {
   int i,cycle; string action;
   if(ParseCurrent(request.comment,i,action,cycle) && S.levels[i].intento!=0 && cycle==S.levels[i].cicloIntento)
   {
     if(Accepted(result.retcode) && result.order>0) S.levels[i].ordemIntento=result.order;
     else if(!Accepted(result.retcode) && !Ambiguous(result.retcode)) S.levels[i].intento=0;
   }
 }
 if(trans.symbol==_Symbol || (trans.type==TRADE_TRANSACTION_REQUEST && request.symbol==_Symbol))
 {
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && Contains(seenDeals,trans.deal)) return;
   dirty=true;
   // Reconciliar aqui; nao enviar novas ordens dentro da fila de transacoes.
   if(RebuildGridState()) SaveGridState();
 }
}
double OnTester()
{ PrintStatistics(); return TesterStatistics(STAT_PROFIT); }
void OnDeinit(const int reason)
{
 if(ready) { SaveGridState(); PrintStatistics(); }
 EventKillTimer(); if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
 if(lockHandle!=INVALID_HANDLE) FileClose(lockHandle);
 Comment("");
}
