#ifndef IMPULSE_EXECUTION_MQH
#define IMPULSE_EXECUTION_MQH
bool TradingSessionOpen()
{
 MqlDateTime now; TimeToStruct(TimeTradeServer(),now);
 if(MQLInfoInteger(MQL_TESTER)) TimeToStruct(TimeCurrent(),now);
 int seconds=now.hour*3600+now.min*60+now.sec;
 for(int back=0;back<=1;back++)
 {
   ENUM_DAY_OF_WEEK day=(ENUM_DAY_OF_WEEK)((now.day_of_week+7-back)%7);
   for(uint n=0;n<32;n++)
   {
     datetime begin,end; if(!SymbolInfoSessionTrade(_Symbol,day,n,begin,end)) break;
     int b=(int)((long)begin%86400),e=(int)((long)end%86400);
     if(back==0 && ((b==e) || (e>b && seconds>=b && seconds<e) || (e<b && seconds>=b))) return true;
     if(back==1 && e<b && seconds<e) return true;
   }
 }
 return false;
}
bool TradingAvailable(bool opening)
{
 if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
    !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
    !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) return false;
 ENUM_SYMBOL_TRADE_MODE mode=(ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
 if(mode==SYMBOL_TRADE_MODE_DISABLED) return false;
 if(opening && (mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
   (S.direcao==GATILHO_COMPRA && mode==SYMBOL_TRADE_MODE_SHORTONLY) ||
   (S.direcao==GATILHO_VENDA && mode==SYMBOL_TRADE_MODE_LONGONLY))) return false;
 MqlTick t; if(!SymbolInfoTick(_Symbol,t) || t.bid<=0 || t.ask<=0) return false;
 return TradingSessionOpen();
}
bool Accepted(uint code)
{ return code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL || code==TRADE_RETCODE_PLACED; }
bool Ambiguous(uint code)
{ return code==0 || code==TRADE_RETCODE_TIMEOUT || code==TRADE_RETCODE_CONNECTION || code==TRADE_RETCODE_ERROR; }
void LogResult(string action,bool sent,uint code,string description)
{ if(!sent || !Accepted(code)) PrintFormat("%s: retcode=%u (%s), erro=%d",action,code,description,GetLastError()); }
ENUM_ORDER_TYPE_FILLING MarketFilling()
{
 long modes=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
 if((modes&SYMBOL_FILLING_FOK)!=0) return ORDER_FILLING_FOK;
 if((modes&SYMBOL_FILLING_IOC)!=0) return ORDER_FILLING_IOC;
 return ORDER_FILLING_RETURN;
}
bool Checked(MqlTradeRequest &r)
{
 MqlTradeCheckResult c={}; ResetLastError();
 if(!OrderCheck(r,c) || (c.retcode!=0 && c.retcode!=TRADE_RETCODE_DONE))
 { PrintFormat("OrderCheck bloqueou %s: %u %s",r.comment,c.retcode,c.comment); return false; }
 return true;
}
bool LevelCanBeRearmed(int i)
{
 if(!S.PermitirRearmeGrid || IsClosing()) return false;
 if(!historyReady || ledgerError || S.manualDetected || S.isolado || ioFailure || HasIntents()) return false;
 if(!S.levels[i].habilitado || S.levels[i].finalizado || S.levels[i].estado==NIVEL_FINALIZADO) return false;
 if(LevelHasPendingOrder(i) || LevelHasOpenPosition(i)) return false;
 if(MaximoExecucoesPorNivel>0 && S.levels[i].quantidadeExecucoes>=MaximoExecucoesPorNivel) return false;
 if(TimeCurrent()<S.levels[i].horarioPermitidoRearme || TimeCurrent()<S.levels[i].ultimaTentativa+2) return false;
 if(S.levels[i].quantidadeExecucoes>0 && legs[i].ultimaSaida!=1 &&
    !(legs[i].ultimaSaida==2 && RearmarAposStopIndividual)) return false;
 return true;
}
bool PlaceGridLevelOrder(int i)
{
 if(!S.PermitirRearmeGrid || IsClosing()) return false;
 if(!LevelCanBeRearmed(i) || !TradingAvailable(true) || !NettingExclusive()) return false;
 if((SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE)&SYMBOL_ORDER_LIMIT)==0) return false;
 MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return false;
 double price=S.levels[i].precoEntrada;
 double distance=MathMax((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
    (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*pointSize;
 distance=MathMax(distance,tickSize);
 if(S.direcao==GATILHO_COMPRA ? price>t.ask-distance+1e-8 : price<t.bid+distance-1e-8) return false;
 double tp=0;
 if(hedging && (SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE)&SYMBOL_ORDER_TP)!=0 &&
    MathAbs(S.levels[i].precoAlvo-price)+1e-8>=distance) tp=S.levels[i].precoAlvo;
 ENUM_ORDER_TYPE_TIME expiration=ORDER_TIME_GTC;
 long expiry=SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE);
 if((expiry&SYMBOL_EXPIRATION_GTC)==0)
 { if((expiry&SYMBOL_EXPIRATION_DAY)==0) return false; expiration=ORDER_TIME_DAY; }
 MqlTradeRequest r={}; r.action=TRADE_ACTION_PENDING; r.magic=(ulong)MagicNumber; r.symbol=_Symbol;
 r.volume=S.levels[i].volume; r.price=price; r.tp=tp;
 r.type=S.direcao==GATILHO_COMPRA ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
 r.type_filling=ORDER_FILLING_RETURN; r.type_time=expiration;
 r.comment=Tag(i,S.direcao==GATILHO_COMPRA ? "B" : "S",S.levels[i].cicloIntento+1);
 S.levels[i].ultimaTentativa=TimeCurrent();
 if(!Checked(r)) return false;
 S.levels[i].intento=1; S.levels[i].cicloIntento++; S.levels[i].ordemIntento=0;
 if(!SaveGridState()) return false;
 trade.SetTypeFilling(ORDER_FILLING_RETURN);
 bool sent=(S.direcao==GATILHO_COMPRA ?
    trade.BuyLimit(r.volume,r.price,_Symbol,0,tp,expiration,0,r.comment) :
    trade.SellLimit(r.volume,r.price,_Symbol,0,tp,expiration,0,r.comment));
 uint code=trade.ResultRetcode(); LogResult("Entrada "+r.comment,sent,code,trade.ResultRetcodeDescription());
 if(Accepted(code))
 { S.levels[i].ordemIntento=trade.ResultOrder(); S.levels[i].ultimaOrdemEntrada=trade.ResultOrder(); S.levels[i].ultimaTentativa=0; }
 else if(!Ambiguous(code)) S.levels[i].intento=0;
 SaveGridState(); dirty=true;
 return sent && Accepted(code);
}
bool RearmGridLevel(int i)
{
 if(!S.PermitirRearmeGrid || IsClosing()) return false;
 return PlaceGridLevelOrder(i);
}
bool CanDeleteSelected()
{
 MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return false;
 double freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*pointSize;
 ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
 if(type!=ORDER_TYPE_BUY_LIMIT && type!=ORDER_TYPE_SELL_LIMIT) return false;
 double market=type==ORDER_TYPE_BUY_LIMIT ? t.ask : t.bid;
 return freeze<=0 || MathAbs(OrderGetDouble(ORDER_PRICE_OPEN)-market)>freeze;
}
void CancelPendingGridOrders(bool residualOnly=false)
{
 if(!TradingAvailable(false)) return;
 for(int o=OrdersTotal()-1;o>=0;o--)
 {
   ulong ticket=OrderGetTicket(o); if(ticket==0 || !OwnOrder()) continue;
   int i,c; string a; bool mapped=ParseCurrent(OrderGetString(ORDER_COMMENT),i,a,c);
   if(!mapped || !IsEntryAction(a) || (residualOnly && !legs[i].ativa)) continue;
   if(!CanDeleteSelected()) continue;
   // Saldo de preenchimento parcial: cancelar antes de qualquer saida/rearme.
   S.levels[i].ordemCanceladaEA=ticket;
   if(!SaveGridState()) return;
   bool sent=trade.OrderDelete(ticket); uint code=trade.ResultRetcode();
   LogResult("Cancelar "+(string)ticket,sent,code,trade.ResultRetcodeDescription()); dirty=true;
 }
}
bool CloseLeg(int i,int reason)
{
 if(!historyReady || ledgerError || S.isolado || ioFailure || !legs[i].ativa || HasIntents()) return false;
 if(LevelHasPendingOrder(i) || !TradingAvailable(false) || !NettingExclusive()) return false;
 if(TimeCurrent()<S.levels[i].ultimaTentativa+2) return false;
 ulong ticket=0;
 if(hedging)
 {
   ticket=S.levels[i].ticketPosicao;
   if(!PositionSelectByTicket(ticket) || !OwnPosition()) return false;
 }
 else
 {
   if(!PositionSelect(_Symbol) || !OwnPosition()) return false;
   ticket=(ulong)PositionGetInteger(POSITION_TICKET);
 }
 double available=PositionGetDouble(POSITION_VOLUME);
 double volume=NormalizeVolume(MathMin(legs[i].volume,available)); if(volume<=0) return false;
 MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return false;
 MqlTradeRequest r={}; r.action=TRADE_ACTION_DEAL; r.symbol=_Symbol; r.magic=(ulong)MagicNumber;
 r.position=ticket; r.volume=volume; r.deviation=(ulong)DesvioMaximoPontos;
 r.type=S.direcao==GATILHO_COMPRA ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
 r.price=r.type==ORDER_TYPE_SELL ? t.bid : t.ask; r.type_filling=MarketFilling();
 r.comment=Tag(i,reason==1 ? "T" : (reason==2 ? "X" : "C"),S.levels[i].cicloIntento+1);
 S.levels[i].ultimaTentativa=TimeCurrent(); if(!Checked(r)) return false;
 S.levels[i].intento=2; S.levels[i].motivoSaida=reason; S.levels[i].cicloIntento++; S.levels[i].ordemIntento=0;
 if(!SaveGridState()) return false;
 // Pedido explicito com position+comment. Evita abrir hedge e permite atribuir a saida
 // NETTING ao nivel correto; CTrade::PositionClosePartial so se aplica a HEDGING.
 MqlTradeResult result={}; bool sent=OrderSend(r,result);
 LogResult("Saida "+r.comment,sent,result.retcode,result.comment);
 if(Accepted(result.retcode)) { S.levels[i].ordemIntento=result.order; S.levels[i].ultimaTentativa=0; }
 else if(!Ambiguous(result.retcode)) S.levels[i].intento=0;
 SaveGridState(); dirty=true; return sent && Accepted(result.retcode);
}
void CheckIndividualStops()
{
 if(!UsarStopFinanceiroPorEntrada || IsClosing()) return;
 for(int i=0;i<S.niveis;i++) if(legs[i].ativa && LegFloating(i)<=-StopFinanceiroPorEntrada)
 { CloseLeg(i,2); if(dirty) return; }
}
void CheckIndividualTargets()
{
 if(IsClosing()) return;
 MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return;
 for(int i=0;i<S.niveis;i++)
 {
   if(!legs[i].ativa) continue;
   // TP no servidor tem precedencia; nao concorrer com a ordem automatica de saida.
   if(hedging && PositionSelectByTicket(S.levels[i].ticketPosicao) && PositionGetDouble(POSITION_TP)>0) continue;
   if(S.direcao==GATILHO_COMPRA ? t.bid>=S.levels[i].precoAlvo : t.ask<=S.levels[i].precoAlvo)
   { CloseLeg(i,1); if(dirty) return; }
 }
}
void EnsureServerTargets()
{
 if(!hedging || IsClosing() || HasIntents() || !TradingAvailable(false)) return;
 if((SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE)&SYMBOL_ORDER_TP)==0) return;
 MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return;
 double distance=MathMax((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
    (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*pointSize;
 for(int i=0;i<S.niveis;i++)
 {
   if(!legs[i].ativa || !PositionSelectByTicket(S.levels[i].ticketPosicao) || !OwnPosition()) continue;
   double tp=S.levels[i].precoAlvo;
   if(PositionGetDouble(POSITION_TP)>0) continue;
   if(S.direcao==GATILHO_COMPRA ? tp<=t.bid+distance : tp>=t.ask-distance) continue;
   bool sent=trade.PositionModify(S.levels[i].ticketPosicao,PositionGetDouble(POSITION_SL),tp);
   LogResult("TP servidor",sent,trade.ResultRetcode(),trade.ResultRetcodeDescription());
 }
}
void ManageNettingLegs() { CheckIndividualStops(); if(!dirty) CheckIndividualTargets(); }
void ManageHedgingPositions() { EnsureServerTargets(); CheckIndividualStops(); if(!dirty) CheckIndividualTargets(); }
#endif
