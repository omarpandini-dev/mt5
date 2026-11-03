//+------------------------------------------------------------------+
//| Bollinger 20/1: retorno para dentro das bandas                  |
//| Sinais confirmados somente apos o fechamento do candle.        |
//+------------------------------------------------------------------+
#property copyright ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5
#property indicator_label1  "BB central"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSilver
#property indicator_label2  "BB superior"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_label3  "BB inferior"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_label4  "Compra"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLimeGreen
#property indicator_width4  2
#property indicator_label5  "Venda"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrTomato
#property indicator_width5  2

input int    PeriodoBB       = 20;    // Media aritmetica sobre fechamentos
input double DesvioBB        = 1.0;
input double MaxAmplitude    = 500.0; // Pontos do indice (maxima - minima)
input int    HoraInicio      = 13;    // Horario do servidor MT5
input int    HoraFim         = 15;    // Limite exclusivo
input int    BarrasHistorico = 5000;

double LinhaCentral[];
double BandaSuperior[];
double BandaInferior[];
double SetaCompra[];
double SetaVenda[];
int    handleBB = INVALID_HANDLE;

bool DentroHorario(const datetime fechamento)
  {
   MqlDateTime horario;
   if(!TimeToStruct(fechamento,horario))
      return false;
   const int minuto = horario.hour*60+horario.min;
   return minuto >= HoraInicio*60 && minuto < HoraFim*60;
  }

int OnInit()
  {
   if(PeriodoBB < 2 || DesvioBB <= 0 || MaxAmplitude <= 0 ||
      HoraInicio < 0 || HoraInicio > 23 || HoraFim < 1 || HoraFim > 24 ||
      HoraInicio >= HoraFim || BarrasHistorico < PeriodoBB+2)
      return INIT_PARAMETERS_INCORRECT;

   SetIndexBuffer(0,LinhaCentral,INDICATOR_DATA);
   SetIndexBuffer(1,BandaSuperior,INDICATOR_DATA);
   SetIndexBuffer(2,BandaInferior,INDICATOR_DATA);
   SetIndexBuffer(3,SetaCompra,INDICATOR_DATA);
   SetIndexBuffer(4,SetaVenda,INDICATOR_DATA);
   ArraySetAsSeries(LinhaCentral,true);
   ArraySetAsSeries(BandaSuperior,true);
   ArraySetAsSeries(BandaInferior,true);
   ArraySetAsSeries(SetaCompra,true);
   ArraySetAsSeries(SetaVenda,true);
   PlotIndexSetInteger(3,PLOT_ARROW,233);
   PlotIndexSetInteger(4,PLOT_ARROW,234);
   for(int plot=0; plot<5; plot++)
      PlotIndexSetDouble(plot,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   handleBB=iBands(_Symbol,_Period,PeriodoBB,0,DesvioBB,PRICE_CLOSE);
   if(handleBB == INVALID_HANDLE)
      return INIT_FAILED;
   IndicatorSetString(INDICATOR_SHORTNAME,"BB 20/1 retorno + sinais");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(handleBB != INVALID_HANDLE)
      IndicatorRelease(handleBB);
  }

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],
                const double &high[],const double &low[],
                const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total < PeriodoBB+2)
      return 0;

   if(prev_calculated == 0)
     {
      for(int i=0;i<rates_total;i++)
        {
         LinhaCentral[i]=EMPTY_VALUE;
         BandaSuperior[i]=EMPTY_VALUE;
         BandaInferior[i]=EMPTY_VALUE;
         SetaCompra[i]=EMPTY_VALUE;
         SetaVenda[i]=EMPTY_VALUE;
        }
     }

   const int quantidade=MathMin(rates_total,BarrasHistorico);
   MqlRates candles[];
   double central[],superior[],inferior[];
   if(CopyRates(_Symbol,_Period,0,quantidade,candles) != quantidade ||
      CopyBuffer(handleBB,0,0,quantidade,central) != quantidade ||
      CopyBuffer(handleBB,1,0,quantidade,superior) != quantidade ||
      CopyBuffer(handleBB,2,0,quantidade,inferior) != quantidade)
      return prev_calculated;

   ArraySetAsSeries(candles,true);
   ArraySetAsSeries(central,true);
   ArraySetAsSeries(superior,true);
   ArraySetAsSeries(inferior,true);

   for(int i=0;i<quantidade;i++)
     {
      LinhaCentral[i]=central[i];
      BandaSuperior[i]=superior[i];
      BandaInferior[i]=inferior[i];
      SetaCompra[i]=EMPTY_VALUE;
      SetaVenda[i]=EMPTY_VALUE;
     }

   // i=1 e o ultimo candle fechado; i+1 e o candle anterior.
   for(int i=quantidade-2;i>=1;i--)
     {
      if(!DentroHorario(candles[i-1].time) ||
         candles[i].high-candles[i].low > MaxAmplitude)
         continue;

      if(candles[i+1].close < inferior[i+1] &&
         candles[i].close > inferior[i] &&
         candles[i].close > candles[i].open)
         SetaCompra[i]=candles[i].low-10*_Point;

      if(candles[i+1].close > superior[i+1] &&
         candles[i].close < superior[i] &&
         candles[i].close < candles[i].open)
         SetaVenda[i]=candles[i].high+10*_Point;
     }
   return rates_total;
  }
