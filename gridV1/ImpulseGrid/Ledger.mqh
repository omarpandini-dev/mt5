#ifndef IMPULSE_LEDGER_MQH
#define IMPULSE_LEDGER_MQH
struct EntryMap { ulong order,position; int index,cycle; };
EntryMap entryMap[];
ulong ownedPositionIds[];
bool Contains(ulong &items[],ulong value)
{ for(int i=0;i<ArraySize(items);i++) if(items[i]==value) return true; return false; }
void AddUnique(ulong &items[],ulong value)
{ if(value==0 || Contains(items,value)) return; int n=ArraySize(items); ArrayResize(items,n+1); items[n]=value; }
int PositionLevel(ulong id)
{ for(int j=0;j<ArraySize(entryMap);j++) if(entryMap[j].position==id) return entryMap[j].index; return -1; }
string DealTag(ulong deal)
{
 string t=HistoryDealGetString(deal,DEAL_COMMENT); long g; int i,c; string a;
 if(ParseTag(t,g,i,a,c)) return t;
 return HistoryOrderGetString((ulong)HistoryDealGetInteger(deal,DEAL_ORDER),ORDER_COMMENT);
}
bool DealBefore(ulong a,ulong b)
{
 long ta=HistoryDealGetInteger(a,DEAL_TIME_MSC),tb=HistoryDealGetInteger(b,DEAL_TIME_MSC);
 return ta<tb || (ta==tb && a<b);
}
void SortDeals(ulong &arr[],int left,int right)
{
 int i=left,j=right; ulong pivot=arr[(left+right)/2];
 while(i<=j)
 {
   while(DealBefore(arr[i],pivot)) i++;
   while(DealBefore(pivot,arr[j])) j--;
   if(i<=j) { ulong temp=arr[i]; arr[i]=arr[j]; arr[j]=temp; i++; j--; }
 }
 if(left<j) SortDeals(arr,left,j); if(i<right) SortDeals(arr,i,right);
}
bool IsTerminalOrder(ulong ticket)
{
 if(ticket==0 || OrderSelect(ticket)) return false;
 long state=HistoryOrderGetInteger(ticket,ORDER_STATE);
 return state==ORDER_STATE_FILLED || state==ORDER_STATE_CANCELED || state==ORDER_STATE_REJECTED || state==ORDER_STATE_EXPIRED;
}
void ConfirmFirstGridExecution()
{
 if(S.GridJaTeveEntrada) return;
 S.GridJaTeveEntrada=true; S.comEntrada++;
 S.candlesEsperaTotal+=S.candlesEspera; S.gridsEsperaFinalizada++;
 if(!IsClosing()) S.EstadoAtual=(S.direcao==GATILHO_COMPRA ? GRID_COMPRA_ATIVO : GRID_VENDA_ATIVO);
 Print("Primeira entrada executada. Grid confirmado definitivamente.");
}
// Reconstrucao deterministica: resultados/counters derivados do historico, nunca somados
// cegamente a cada callback. O conjunto seenDeals elimina notificacoes repetidas.
bool RebuildGridState()
{
 historyReady=false; externalExit=S.manualDetected; ledgerError=false;
 datetime from=IsActive() ? (datetime)MathMin((long)S.day,(long)S.CandleGatilhoTime) : S.day;
 if(!HistorySelect(from,TimeCurrent())) { fault="Historico indisponivel"; return false; }
 ulong deals[]; int count=0;
 ArrayResize(deals,HistoryDealsTotal());
 ArrayResize(ownedPositionIds,0); ArrayResize(entryMap,0); ArrayResize(seenDeals,0);
 // Primeiro passe identifica propriedade por entradas, inclusive saidas manuais de magic zero.
 for(int d=0;d<HistoryDealsTotal();d++)
 {
   ulong ticket=HistoryDealGetTicket(d);
   if(ticket==0 || HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
   deals[count++]=ticket;
   if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=MagicNumber) continue;
   ENUM_DEAL_ENTRY e=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
   if(e==DEAL_ENTRY_IN) AddUnique(ownedPositionIds,(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID));
   int i,c; string a;
   if(IsActive() && e==DEAL_ENTRY_IN && ParseCurrent(DealTag(ticket),i,a,c) && IsEntryAction(a))
   {
     ulong order=(ulong)HistoryDealGetInteger(ticket,DEAL_ORDER);
     bool exists=false;
     for(int m=0;m<ArraySize(entryMap);m++) if(entryMap[m].order==order) { exists=true; break; }
     if(!exists)
     {
       int n=ArraySize(entryMap); ArrayResize(entryMap,n+1);
       entryMap[n].order=order; entryMap[n].position=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
       entryMap[n].index=i; entryMap[n].cycle=c;
     }
   }
 }
 // Saidas manuais de posicoes abertas ANTES da meia-noite tambem pertencem ao
 // resultado diario. Consultar a linhagem completa, restaurando a selecao depois.
 ulong candidates[];
 for(int d=0;d<count;d++)
 {
   ulong t=deals[d],pid=(ulong)HistoryDealGetInteger(t,DEAL_POSITION_ID);
   if(HistoryDealGetInteger(t,DEAL_ENTRY)==DEAL_ENTRY_OUT &&
      HistoryDealGetInteger(t,DEAL_MAGIC)!=MagicNumber && !Contains(ownedPositionIds,pid)) AddUnique(candidates,pid);
 }
 for(int p=0;p<ArraySize(candidates);p++)
 {
   if(!HistorySelectByPosition(candidates[p])) return false;
   bool ours=false,foreign=false;
   for(int d=0;d<HistoryDealsTotal();d++)
   {
     ulong t=HistoryDealGetTicket(d);
     if(HistoryDealGetInteger(t,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
     if(HistoryDealGetInteger(t,DEAL_MAGIC)==MagicNumber) ours=true; else foreign=true;
   }
   if(ours && !foreign) AddUnique(ownedPositionIds,candidates[p]);
 }
 if(ArraySize(candidates)>0 && !HistorySelect(from,TimeCurrent())) return false;
 ArrayResize(deals,count); if(count>1) SortDeals(deals,0,count-1);
 realized=0; dailyRealized=0;
 for(int i=0;i<S.niveis;i++)
 {
   ZeroMemory(legs[i]); legs[i].gridId=S.GridID; legs[i].numeroNivel=i+1; legs[i].precoAlvo=S.levels[i].precoAlvo;
   S.levels[i].ticketOrdem=0; S.levels[i].ticketPosicao=0;
   S.levels[i].quantidadeExecucoes=0; S.levels[i].lucroRealizado=0;
   S.levels[i].horarioUltimaEntrada=0; S.levels[i].horarioUltimaSaida=0;
 }
 ulong entryOrders[];
 for(int d=0;d<count;d++)
 {
   ulong ticket=deals[d];
   ulong pid=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
   long magic=HistoryDealGetInteger(ticket,DEAL_MAGIC);
   double cash=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
     HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_FEE);
   datetime time=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
   ENUM_DEAL_ENTRY ent=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
   if(time>=S.day && (magic==MagicNumber || (Contains(ownedPositionIds,pid) && ent==DEAL_ENTRY_OUT))) dailyRealized+=cash;
   if(!IsActive()) continue;
   int i=-1,c=0; string a=""; bool tagged=ParseCurrent(DealTag(ticket),i,a,c);
   if(!tagged) i=PositionLevel(pid);
   if(i<0 || i>=S.niveis) continue;
   if(ent==DEAL_ENTRY_IN && magic!=MagicNumber) { if(!hedging) ledgerError=true; continue; }
   if(ent==DEAL_ENTRY_INOUT || ent==DEAL_ENTRY_OUT_BY) { ledgerError=true; continue; }
   if(Contains(seenDeals,ticket)) continue;
   AddUnique(seenDeals,ticket);
   realized+=cash; S.levels[i].lucroRealizado+=cash;
   double volume=HistoryDealGetDouble(ticket,DEAL_VOLUME),price=HistoryDealGetDouble(ticket,DEAL_PRICE);
   ulong order=(ulong)HistoryDealGetInteger(ticket,DEAL_ORDER);
   if(ent==DEAL_ENTRY_IN)
   {
     if(!tagged || !IsEntryAction(a)) { ledgerError=true; continue; }
     ENUM_DEAL_TYPE dt=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);
     if((S.direcao==GATILHO_COMPRA && dt!=DEAL_TYPE_BUY) || (S.direcao==GATILHO_VENDA && dt!=DEAL_TYPE_SELL))
     { ledgerError=true; continue; }
     if(hedging && legs[i].volume>volStep/2 && legs[i].positionId!=pid) ledgerError=true;
     bool newCycle=!Contains(entryOrders,order);
     if(newCycle)
     {
       if(legs[i].volume>volStep/2) ledgerError=true;
       AddUnique(entryOrders,order); S.levels[i].quantidadeExecucoes++;
       legs[i].custoCiclo=0; legs[i].ultimaSaida=0;
     }
     double total=legs[i].volume+volume;
     legs[i].precoEntradaReal=(legs[i].precoEntradaReal*legs[i].volume+price*volume)/total;
     legs[i].volume=total; legs[i].custoCiclo+=cash; legs[i].ativa=true;
     legs[i].positionId=pid; legs[i].ordemEntrada=order; legs[i].dealEntrada=ticket; legs[i].horarioEntrada=time;
     S.levels[i].horarioUltimaEntrada=time;
   }
   else if(ent==DEAL_ENTRY_OUT)
   {
     // NETTING: nunca atribuir automaticamente uma saida desconhecida a uma perna.
     // O netting compartilha POSITION_ID entre todos os niveis.
     if(!hedging && (!tagged || IsEntryAction(a)))
     {
       // Intervencao manual: consumir FIFO apenas para reconciliar o saldo fisico,
       // bloquear a reciclagem e encerrar o restante do grid. Nunca tratar como TP.
       double remaining=volume;
       for(int k=0;k<S.niveis && remaining>volStep/2;k++)
       {
         double used=MathMin(remaining,legs[k].volume); if(used<=0) continue;
         legs[k].volume-=used; legs[k].ativa=legs[k].volume>volStep/2;
         legs[k].ultimaSaida=3; remaining-=used;
         if(!legs[k].ativa) S.levels[k].horarioUltimaSaida=time;
       }
       if(remaining>volStep/2) ledgerError=true;
       externalExit=true; S.manualDetected=true; continue;
     }
     int reason=(int)HistoryDealGetInteger(ticket,DEAL_REASON);
     int why=(tagged && !IsEntryAction(a)) ? ExitCode(a) : (reason==DEAL_REASON_TP ? 1 : 3);
     if(volume>legs[i].volume+volStep/2) ledgerError=true;
     legs[i].volume=MathMax(0,legs[i].volume-volume); legs[i].ativa=legs[i].volume>volStep/2;
     legs[i].custoCiclo+=cash;
     // Uma saida manual parcial impede reciclagem posterior, mesmo se o restante atingir TP.
     if(legs[i].ultimaSaida!=3 && legs[i].ultimaSaida!=2) legs[i].ultimaSaida=why;
     if(why==3) { legs[i].ultimaSaida=3; if(!IsClosing()) { externalExit=true; S.manualDetected=true; } }
     if(!legs[i].ativa)
     {
       S.levels[i].horarioUltimaSaida=time;
       S.levels[i].horarioPermitidoRearme=time+DelayReentradaSegundos;
     }
   }
 }
 for(int i=0;i<S.niveis;i++)
 {
   if(S.levels[i].quantidadeExecucoes>0) ConfirmFirstGridExecution();
   if(i==0 || ModoGrid==TODAS_ORDENS_IMEDIATAMENTE || S.levels[i-1].quantidadeExecucoes>0) S.levels[i].habilitado=true;
 }
 // Ordens vivas sao a fonte de verdade, inclusive apos timeout do envio.
 for(int o=OrdersTotal()-1;o>=0;o--)
 {
   ulong ticket=OrderGetTicket(o); if(ticket==0 || !OwnOrder()) continue;
   int i,c; string a;
   if(!IsActive() || !ParseCurrent(OrderGetString(ORDER_COMMENT),i,a,c)) { ledgerError=true; continue; }
   if(IsEntryAction(a))
   {
     if(S.levels[i].ticketOrdem!=0) ledgerError=true;
     S.levels[i].ticketOrdem=ticket;
     S.levels[i].ultimaOrdemEntrada=ticket;
   }
 }
 for(int p=PositionsTotal()-1;p>=0;p--)
 {
   ulong ticket=PositionGetTicket(p); if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
   if(!hedging) continue;
   if(!OwnPosition()) continue;
   int i=PositionLevel((ulong)PositionGetInteger(POSITION_IDENTIFIER));
   if(i<0) { ledgerError=true; continue; }
   S.levels[i].ticketPosicao=ticket;
   if(MathAbs(PositionGetDouble(POSITION_VOLUME)-legs[i].volume)>volStep/2) ledgerError=true;
 }
 for(int i=0;i<S.niveis;i++)
 {
   ulong previous=S.levels[i].ultimaOrdemEntrada;
   if(previous>0 && S.levels[i].ticketOrdem==0)
   {
     // ORDER_DELETE pode preceder DEAL_ADD: nao rearmar nessa janela.
     if(!IsTerminalOrder(previous)) ledgerError=true;
     else
     {
       double expected=HistoryOrderGetDouble(previous,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(previous,ORDER_VOLUME_CURRENT);
       double observed=0;
       for(int d=0;d<count;d++) if((ulong)HistoryDealGetInteger(deals[d],DEAL_ORDER)==previous)
         observed+=HistoryDealGetDouble(deals[d],DEAL_VOLUME);
       if(observed+volStep/2<expected) ledgerError=true;
       else
       {
         long os=HistoryOrderGetInteger(previous,ORDER_STATE);
         if((os==ORDER_STATE_CANCELED || os==ORDER_STATE_EXPIRED) &&
            previous!=S.levels[i].ordemCanceladaEA && !IsClosing())
         { externalExit=true; S.manualDetected=true; }
         S.levels[i].ultimaOrdemEntrada=0;
       }
     }
   }
   if(hedging && legs[i].ativa && S.levels[i].ticketPosicao==0) ledgerError=true;
   ResolveIntent(i);
   if(legs[i].ativa) S.levels[i].estado=NIVEL_POSICAO_ABERTA;
   else if(S.levels[i].ticketOrdem>0) S.levels[i].estado=NIVEL_ORDEM_PENDENTE;
   else if(S.levels[i].finalizado || (MaximoExecucoesPorNivel>0 && S.levels[i].quantidadeExecucoes>=MaximoExecucoesPorNivel) ||
           (S.levels[i].quantidadeExecucoes>0 &&
           legs[i].ultimaSaida!=1 && !(legs[i].ultimaSaida==2 && RearmarAposStopIndividual))) S.levels[i].estado=NIVEL_FINALIZADO;
   else if(!S.levels[i].habilitado) S.levels[i].estado=NIVEL_INATIVO;
   else S.levels[i].estado=(S.levels[i].quantidadeExecucoes>0 ? NIVEL_AGUARDANDO_REARME : NIVEL_AGUARDANDO_ORDEM);
 }
 historyReady=true; dirty=false; lastHistorySync=TimeCurrent(); return true;
}
void ResolveIntent(int i)
{
 if(S.levels[i].intento==0) return;
 string expected=Tag(i,S.levels[i].intento==1 ? (S.direcao==GATILHO_COMPRA ? "B" : "S") :
   (S.levels[i].motivoSaida==1 ? "T" : (S.levels[i].motivoSaida==2 ? "X" : "C")),S.levels[i].cicloIntento);
 ulong found=S.levels[i].ordemIntento;
 if(found==0)
 {
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
     ulong t=OrderGetTicket(j);
     if(t>0 && OwnOrder() && OrderGetString(ORDER_COMMENT)==expected) { found=t; break; }
   }
   if(found==0) for(int j=HistoryOrdersTotal()-1;j>=0;j--)
   {
     ulong t=HistoryOrderGetTicket(j);
     if(HistoryOrderGetInteger(t,ORDER_MAGIC)==MagicNumber && HistoryOrderGetString(t,ORDER_SYMBOL)==_Symbol &&
        HistoryOrderGetString(t,ORDER_COMMENT)==expected) { found=t; break; }
   }
 }
 if(found==0) return; // Ausencia de evidencia nao autoriza reenvio.
 S.levels[i].ordemIntento=found;
 if(S.levels[i].intento==1 && OrderSelect(found))
 { S.levels[i].intento=0; S.levels[i].ordemIntento=0; return; }
 if(!IsTerminalOrder(found)) return;
 // Historico da ordem pode chegar antes de seus deals. Esperar volume executado correspondente.
 double filled=HistoryOrderGetDouble(found,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(found,ORDER_VOLUME_CURRENT);
 double observed=0;
 for(int d=0;d<HistoryDealsTotal();d++)
 {
   ulong t=HistoryDealGetTicket(d);
   if((ulong)HistoryDealGetInteger(t,DEAL_ORDER)==found) observed+=HistoryDealGetDouble(t,DEAL_VOLUME);
 }
 if(observed+volStep/2<filled) return;
 S.levels[i].intento=0; S.levels[i].ordemIntento=0;
}
bool LevelHasPendingOrder(int index)
{
 for(int j=OrdersTotal()-1;j>=0;j--)
 {
   if(OrderGetTicket(j)==0 || !OwnOrder()) continue;
   int i,c; string a;
   if(ParseCurrent(OrderGetString(ORDER_COMMENT),i,a,c) && i==index) return true;
 }
 return false;
}
bool LevelHasOpenPosition(int index) { return legs[index].ativa; }
bool HasIntents()
{ for(int i=0;i<S.niveis;i++) if(S.levels[i].intento!=0) return true; return false; }
bool HasOwnExposure()
{
 for(int j=OrdersTotal()-1;j>=0;j--) if(OrderGetTicket(j)>0 && OwnOrder()) return true;
 for(int j=PositionsTotal()-1;j>=0;j--) if(PositionGetTicket(j)>0 && OwnPosition()) return true;
 return false;
}
bool NettingExclusive()
{
 if(hedging) return true;
 for(int j=OrdersTotal()-1;j>=0;j--)
   if(OrderGetTicket(j)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)!=MagicNumber) return false;
 if(!PositionSelect(_Symbol))
 {
   double expected=0; for(int i=0;i<S.niveis;i++) expected+=legs[i].volume;
   return expected<volStep/2;
 }
 if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber) return false;
 ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
 if(!Contains(ownedPositionIds,pid)) return false;
 for(int d=0;d<HistoryDealsTotal();d++)
 {
   ulong t=HistoryDealGetTicket(d);
   if((ulong)HistoryDealGetInteger(t,DEAL_POSITION_ID)!=pid) continue;
   if(HistoryDealGetInteger(t,DEAL_ENTRY)==DEAL_ENTRY_IN && HistoryDealGetInteger(t,DEAL_MAGIC)!=MagicNumber) return false;
 }
 double expected=0; for(int i=0;i<S.niveis;i++) expected+=legs[i].volume;
 if(MathAbs(expected-PositionGetDouble(POSITION_VOLUME))>volStep/2) return false;
 return (S.direcao==GATILHO_COMPRA && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) ||
        (S.direcao==GATILHO_VENDA && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL);
}
double CalculateGridRealizedResult() { return realized; }
double CalculateGridFloatingResult()
{
 if(!IsActive()) return 0;
 double total=0;
 for(int p=PositionsTotal()-1;p>=0;p--)
 {
   if(PositionGetTicket(p)==0 || !OwnPosition()) continue;
   if(hedging && PositionLevel((ulong)PositionGetInteger(POSITION_IDENTIFIER))<0) continue;
   total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
 }
 return total;
}
double CalculateGridTotalResult() { return CalculateGridRealizedResult()+CalculateGridFloatingResult(); }
double CalculateDailyResult() { return dailyRealized+CalculateGridFloatingResult(); }
double LegFloating(int i)
{
 MqlTick t; if(!SymbolInfoTick(_Symbol,t)) return 0;
 double p=0;
 if(!OrderCalcProfit(S.direcao==GATILHO_COMPRA ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,
    legs[i].volume,legs[i].precoEntradaReal,S.direcao==GATILHO_COMPRA ? t.bid : t.ask,p)) return 0;
 if(hedging && PositionSelectByTicket(S.levels[i].ticketPosicao)) p+=PositionGetDouble(POSITION_SWAP);
 return p+legs[i].custoCiclo;
}
#endif
