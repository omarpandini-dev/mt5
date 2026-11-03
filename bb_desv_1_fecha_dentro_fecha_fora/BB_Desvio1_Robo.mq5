//+------------------------------------------------------------------+
//| Robo para mini indice: retorno para dentro das Bollinger 20/1  |
//| Executa na abertura do candle seguinte ao sinal confirmado.    |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.10"
#include <Trade/Trade.mqh>

enum MODO_SAIDA
  {
   SAIDA_BANDA_CENTRAL = 0, // Alvo na linha central; stop no candle de sinal
   SAIDA_PONTOS_FIXOS  = 1, // Alvo e stop em pontos do indice
   SAIDA_SEM_ALVO_STOP = 2  // Posicao gerida externamente ou encerrada as 16h
  };

input double     Lotes              = 1.0;
input int        PeriodoBB          = 20;
input double     DesvioBB           = 1.0;
input double     MaxAmplitude       = 500.0; // Maxima - minima, em pontos do indice
input int        HoraInicio         = 13;    // Horario do servidor MT5
input int        HoraFim            = 15;    // Limite exclusivo
input MODO_SAIDA ModoSaida          = SAIDA_PONTOS_FIXOS;
input double     StopPontos         = 400.0; // Pontos do indice
input double     AlvoPontos         = 50.0;  // Pontos do indice
input ulong      NumeroMagico       = 20131501;
input ulong      DesvioExecucao     = 20;    // Pontos da cotacao MT5

CTrade trade;
int handleBB=INVALID_HANDLE;
datetime ultimaBarra=0;

bool DentroHorario(const datetime quando)
  {
   MqlDateTime h;
   if(!TimeToStruct(quando,h))
      return false;
   const int minuto=h.hour*60+h.min;
   return minuto >= HoraInicio*60 && minuto < HoraFim*60;
  }

bool HaPosicaoAberta()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         (PositionGetString(POSITION_SYMBOL)==_Symbol ||
          (ulong)PositionGetInteger(POSITION_MAGIC)==NumeroMagico))
         return true;
     }
   return false;
  }

datetime LimiteDaPosicao(const datetime abertura)
  {
   MqlDateTime dia;
   if(!TimeToStruct(abertura,dia))
      return 0;
   dia.hour=16;
   dia.min=0;
   dia.sec=0;
   return StructToTime(dia);
  }

void EncerrarPosicoesVencidas()
  {
   const datetime agora=TimeTradeServer();
   if(agora<=0)
      return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket) ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=NumeroMagico)
         continue;
      const datetime limite=LimiteDaPosicao((datetime)PositionGetInteger(POSITION_TIME));
      if(limite==0 || agora<limite)
         continue;
      const string simbolo=PositionGetString(POSITION_SYMBOL);
      trade.SetTypeFillingBySymbol(simbolo);
      if(!trade.PositionClose(ticket,DesvioExecucao) ||
         trade.ResultRetcode()!=TRADE_RETCODE_DONE)
         PrintFormat("Falha ao encerrar posicao %I64u apos as 16h: %u %s",
                     ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
     }
  }

double AjustarPreco(const double preco,const bool paraCima)
  {
   double passo=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(passo<=0)
      passo=_Point;
   const double ajustado=paraCima ? MathCeil(preco/passo)*passo
                                   : MathFloor(preco/passo)*passo;
   return NormalizeDouble(ajustado,_Digits);
  }

bool VolumeValido()
  {
   const double minimo=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   const double maximo=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   const double passo=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(passo<=0 || Lotes<minimo || Lotes>maximo)
      return false;
   return MathAbs(Lotes/passo-MathRound(Lotes/passo))<1e-7;
  }

int OnInit()
  {
   if(PeriodoBB<2 || DesvioBB<=0 || MaxAmplitude<=0 ||
      HoraInicio<0 || HoraInicio>23 || HoraFim<1 || HoraFim>24 ||
      HoraInicio>=HoraFim || NumeroMagico==0 ||
      (ModoSaida==SAIDA_PONTOS_FIXOS && (StopPontos<=0 || AlvoPontos<=0)))
      return INIT_PARAMETERS_INCORRECT;
   if(!VolumeValido())
     {
      Print("Lotes fora dos limites ou do passo aceito pelo simbolo.");
      return INIT_PARAMETERS_INCORRECT;
     }

   handleBB=iBands(_Symbol,_Period,PeriodoBB,0,DesvioBB,PRICE_CLOSE);
   if(handleBB==INVALID_HANDLE)
      return INIT_FAILED;
   trade.SetExpertMagicNumber(NumeroMagico);
   trade.SetDeviationInPoints(DesvioExecucao);
   trade.SetTypeFillingBySymbol(_Symbol);
   if(!EventSetTimer(10))
     {
      PrintFormat("Nao foi possivel iniciar o temporizador de encerramento: %d",GetLastError());
      IndicatorRelease(handleBB);
      handleBB=INVALID_HANDLE;
      return INIT_FAILED;
     }
   ultimaBarra=iTime(_Symbol,_Period,0); // Nao operar sinal antigo ao anexar o robo.
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(handleBB!=INVALID_HANDLE)
      IndicatorRelease(handleBB);
  }

void OnTimer()
  {
   EncerrarPosicoesVencidas();
  }

void OnTick()
  {
   EncerrarPosicoesVencidas();
   const datetime agora=TimeTradeServer();

   const datetime novaBarra=iTime(_Symbol,_Period,0);
   if(novaBarra==0 || novaBarra==ultimaBarra)
      return;
   if(!DentroHorario(novaBarra) || !DentroHorario(agora))
     {
      ultimaBarra=novaBarra;
      return;
     }

   MqlRates candles[];
   double central[],superior[],inferior[];
   if(CopyRates(_Symbol,_Period,0,3,candles)!=3 ||
      CopyBuffer(handleBB,0,0,3,central)!=3 ||
      CopyBuffer(handleBB,1,0,3,superior)!=3 ||
      CopyBuffer(handleBB,2,0,3,inferior)!=3)
      return; // Tentar de novo no proximo tick desta barra.
   ultimaBarra=novaBarra;
   ArraySetAsSeries(candles,true);
   ArraySetAsSeries(central,true);
   ArraySetAsSeries(superior,true);
   ArraySetAsSeries(inferior,true);

   if(candles[1].high-candles[1].low>MaxAmplitude || HaPosicaoAberta())
      return;
   const bool compra=(candles[2].close<inferior[2] &&
                      candles[1].close>inferior[1] &&
                      candles[1].close>candles[1].open);
   const bool venda=(candles[2].close>superior[2] &&
                     candles[1].close<superior[1] &&
                     candles[1].close<candles[1].open);
   if(!compra && !venda)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   const double entrada=compra ? tick.ask : tick.bid;
   double stop=0,alvo=0;
   if(ModoSaida==SAIDA_BANDA_CENTRAL)
     {
      stop=compra ? AjustarPreco(candles[1].low,false)
                  : AjustarPreco(candles[1].high,true);
      alvo=AjustarPreco(central[1],compra);
     }
   else if(ModoSaida==SAIDA_PONTOS_FIXOS)
     {
      stop=AjustarPreco(entrada+(compra ? -StopPontos : StopPontos),!compra);
      alvo=AjustarPreco(entrada+(compra ? AlvoPontos : -AlvoPontos),compra);
     }

   if(ModoSaida!=SAIDA_SEM_ALVO_STOP)
     {
      const double distancia=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
      if((compra && (stop>=tick.bid-distancia || alvo<=tick.bid+distancia)) ||
         (venda && (stop<=tick.ask+distancia || alvo>=tick.ask-distancia)))
        {
         Print("Sinal ignorado: stop ou alvo invalido para o preco atual.");
         return;
        }
     }

   bool enviado=false;
   trade.SetTypeFillingBySymbol(_Symbol);
   if(compra)
      enviado=trade.Buy(Lotes,_Symbol,0,stop,alvo,"BB retorno compra");
   else
      enviado=trade.Sell(Lotes,_Symbol,0,stop,alvo,"BB retorno venda");
   if(!enviado || trade.ResultRetcode()!=TRADE_RETCODE_DONE)
      PrintFormat("Ordem nao executada: %u %s",trade.ResultRetcode(),
                  trade.ResultRetcodeDescription());
  }
