#ifndef IMPULSE_SIGNALS_MQH
#define IMPULSE_SIGNALS_MQH
// A media exclui sempre o candle analisado. ATR tambem usa shift+1.
bool ReadSignalData(int shift,MqlRates &bar,double &volume,double &averageVolume,double &referenceRange)
{
 if(shift<1) return false;
 int n=(int)MathMax(PeriodoMediaVolume,PeriodoMediaAmplitude);
 MqlRates rates[]; ArraySetAsSeries(rates,true);
 if(CopyRates(_Symbol,signalTF,shift,n+1,rates)!=n+1) return false;
 bar=rates[0];
 bool real=(MetodoVolume!=USAR_VOLUME_TICK);
 if(MetodoVolume==VOLUME_AUTOMATICO)
   for(int k=0;k<=PeriodoMediaVolume;k++) if(rates[k].real_volume<=0) { real=false; break; }
 volume=real ? (double)bar.real_volume : (double)bar.tick_volume;
 averageVolume=0;
 for(int k=1;k<=PeriodoMediaVolume;k++) averageVolume+=real ? (double)rates[k].real_volume : (double)rates[k].tick_volume;
 averageVolume/=PeriodoMediaVolume;
 referenceRange=0;
 if(MetodoCalculoAmplitude==ATR)
 {
   double a[1]; if(CopyBuffer(atrHandle,0,shift+1,1,a)!=1 || a[0]==EMPTY_VALUE) return false;
   referenceRange=a[0];
 }
 else
 {
   for(int k=1;k<=PeriodoMediaAmplitude;k++) referenceRange+=rates[k].high-rates[k].low;
   referenceRange/=PeriodoMediaAmplitude;
 }
 return averageVolume>0 && referenceRange>0;
}
double GetAverageVolume()
{ MqlRates b; double v,a,r; return ReadSignalData(1,b,v,a,r) ? a : 0; }
double GetAverageRange()
{
 MqlRates b[]; if(CopyRates(_Symbol,signalTF,2,PeriodoMediaAmplitude,b)!=PeriodoMediaAmplitude) return 0;
 double a=0; for(int i=0;i<ArraySize(b);i++) a+=b[i].high-b[i].low; return a/PeriodoMediaAmplitude;
}
double GetATRValue()
{ double a[1]; return CopyBuffer(atrHandle,0,2,1,a)==1 ? a[0] : 0; }
TipoGatilho ClassifyCandle(const MqlRates &b,double volume,double averageVolume,double referenceRange)
{
 double range=b.high-b.low;
 if(range<=0 || b.close==b.open || averageVolume<=0 || referenceRange<=0 || volume<averageVolume*MultiplicadorVolume ||
    range<referenceRange*(MetodoCalculoAmplitude==ATR ? MultiplicadorATR : MultiplicadorAmplitude) ||
    MathAbs(b.close-b.open)/range*100<PercentualMinimoCorpo) return SEM_GATILHO;
 return b.close>b.open ? GATILHO_COMPRA : GATILHO_VENDA;
}
TipoGatilho EvaluateSignal(int shift,bool &available)
{
 MqlRates b; double v,a,r;
 available=ReadSignalData(shift,b,v,a,r);
 if(!available) return SEM_GATILHO; // Falta de historico NAO significa candle invalido.
 return ClassifyCandle(b,v,a,r);
}
TipoGatilho GetCandleTrigger(int shift) { bool ok; return EvaluateSignal(shift,ok); }
bool IsExpressiveCandle(int shift) { return GetCandleTrigger(shift)!=SEM_GATILHO; }
bool IsBullishSignal() { return GetCandleTrigger(1)==GATILHO_COMPRA; }
bool IsBearishSignal() { return GetCandleTrigger(1)==GATILHO_VENDA; }
bool CandleConfirmaGridAtual(int shift) { return (int)GetCandleTrigger(shift)==S.direcao; }
bool IsNewBar()
{ datetime now=iTime(_Symbol,signalTF,0); return now>0 && now!=S.lastBar; }
#endif
