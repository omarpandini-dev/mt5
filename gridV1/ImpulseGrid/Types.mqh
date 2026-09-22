#ifndef IMPULSE_TYPES_MQH
#define IMPULSE_TYPES_MQH
#define MAX_LEVELS 100
#define STATE_VERSION 3
// VOLUME_REAL/VOLUME_TICK ja existem no ENUM_APPLIED_VOLUME do MQL5.
enum TipoVolume { VOLUME_AUTOMATICO,USAR_VOLUME_REAL,USAR_VOLUME_TICK };
enum MetodoAmplitude { MEDIA_AMPLITUDE,ATR };
enum TipoGatilho { SEM_GATILHO,GATILHO_COMPRA,GATILHO_VENDA };
enum ModoCriacaoGrid { TODAS_ORDENS_IMEDIATAMENTE,PROXIMA_APOS_EXECUCAO };
enum AcaoFimHorario { MANTER_GRID,CANCELAR_PENDENTES_MANTER_POSICOES,ENCERRAR_GRID };
enum EstadoEA { AGUARDANDO_SINAL,GRID_AGUARDANDO_PRIMEIRA_ENTRADA_COMPRA,
 GRID_AGUARDANDO_PRIMEIRA_ENTRADA_VENDA,GRID_COMPRA_ATIVO,GRID_VENDA_ATIVO,
 ENCERRANDO_GRID,BLOQUEADO_DIA };
enum EstadoNivel { NIVEL_INATIVO,NIVEL_AGUARDANDO_ORDEM,NIVEL_ORDEM_PENDENTE,
 NIVEL_POSICAO_ABERTA,NIVEL_AGUARDANDO_REARME,NIVEL_FINALIZADO };
enum MotivoEncerramentoGrid { MOTIVO_NENHUM,TARGET_GLOBAL,STOP_GLOBAL,STOP_DIARIO,
 ALVO_DIARIO,FIM_HORARIO,SEM_CONFIRMACAO_GATILHO,GATILHO_CONTRARIO,
 ENCERRAMENTO_MANUAL,PROTECAO_CRITICA,LIMITE_CANDLES,NIVEIS_ESGOTADOS };

input group "SINAL"
input ENUM_TIMEFRAMES TimeframeSinal=PERIOD_CURRENT;
input int PeriodoMediaVolume=20;
input double MultiplicadorVolume=2.0;
input TipoVolume MetodoVolume=VOLUME_AUTOMATICO;
input int PeriodoMediaAmplitude=20;
input double MultiplicadorAmplitude=1.5;
input MetodoAmplitude MetodoCalculoAmplitude=MEDIA_AMPLITUDE;
input int PeriodoATR=14;
input double MultiplicadorATR=1.5;
input double PercentualMinimoCorpo=60.0;
input group "GRID"
input int DistanciaPrimeiraEntrada=100;
input int DistanciaEntreEntradas=50;
input int MaximoNiveisGrid=5;
input double LotePadrao=1.0;
input ModoCriacaoGrid ModoGrid=TODAS_ORDENS_IMEDIATAMENTE;
input group "RECICLAGEM"
input int AlvoPontosPorEntrada=50;
input int MaximoExecucoesPorNivel=0;
input int DelayReentradaSegundos=0;
input group "RISCO"
input bool UsarStopFinanceiroPorEntrada=false;
input double StopFinanceiroPorEntrada=100.0;
input bool RearmarAposStopIndividual=false;
input double StopFinanceiroGlobal=500.0;
input double AlvoFinanceiroGlobal=500.0;
input group "VALIDACAO DE GATILHO"
input bool UsarConfirmacaoContinuaGatilho=true;
input int MaximoCandlesSemEntrada=0;
input group "DIARIO"
input bool UsarStopDiario=true;
input double StopFinanceiroDiario=1000.0;
input bool UsarAlvoDiario=false;
input double AlvoFinanceiroDiario=1000.0;
input int MaximoGridsPorDia=0;
input group "HORARIO (SERVIDOR)"
input bool UsarFiltroHorario=true;
input string HorarioInicio="09:05";
input string HorarioFinal="17:30";
input AcaoFimHorario RegraFimHorario=MANTER_GRID;
input group "EXECUCAO"
input long MagicNumber=20260922;
input int DesvioMaximoPontos=20; // Pontos MT5, somente para desvio.

struct GridLevel
{
 long gridId;
 int numeroNivel,direcao;
 double precoEntrada,precoAlvo,volume;
 bool habilitado;
 ulong ticketOrdem,ticketPosicao;
 int quantidadeExecucoes;
 double lucroRealizado;
 datetime horarioUltimaEntrada,horarioUltimaSaida,horarioPermitidoRearme;
 int estado;
 // Intento gravado ANTES de enviar: 1=entrada, 2=saida. Zero=sem envio incerto.
 int intento,cicloIntento,motivoSaida;
 ulong ordemIntento,ordemCanceladaEA,ultimaOrdemEntrada;
 datetime ultimaTentativa;
 bool finalizado;
};
struct GridLeg
{
 long gridId;
 int numeroNivel;
 double precoEntradaReal,precoAlvo,volume,custoCiclo;
 bool ativa;
 ulong dealEntrada,positionId,ordemEntrada;
 datetime horarioEntrada;
 int ultimaSaida; // 1=TP normal, 2=stop individual, 3=outro.
};
// Apenas tipos simples: snapshot binario com duas copias alternadas.
struct PersistedState
{
 int version;
 long sequence,account,magic;
 uint symbolHash,serverHash,configHash;
 int timeframe,accountMode;
 long GridID,lastGridID;
 int EstadoAtual,direcao,niveis;
 bool GridJaTeveEntrada,PermitirRearmeGrid,ultimoConfirmou,isolado,manualDetected;
 datetime CandleGatilhoTime,UltimoCandleValidacaoTime,lastBar;
 double CandleGatilhoOpen,CandleGatilhoHigh,CandleGatilhoLow,CandleGatilhoClose;
 double CandleGatilhoVolume,CandleGatilhoAmplitude;
 datetime pendingSignalTime;
 int pendingSignalDirection,motivo,candlesEspera;
 datetime day;
 bool dayBlocked;
 int gridsDia;
 long grids,comEntrada,canceladosSemEntrada,semConfirmacao,inversoes;
 long mantidos,candlesEsperaTotal,gridsEsperaFinalizada,execucoesConcluidas,reciclagensConcluidas;
 double resultadoConcluido;
 GridLevel levels[MAX_LEVELS];
};
PersistedState S;
GridLeg legs[MAX_LEVELS];
CTrade trade;
ENUM_TIMEFRAMES signalTF;
bool hedging=false,ready=false,ioFailure=false,historyReady=false,busy=false;
bool dirty=true,externalExit=false,ledgerError=false;
int atrHandle=INVALID_HANDLE,lockHandle=INVALID_HANDLE,storageFlags=0;
int startMinute=0,endMinute=0;
double tickSize=0,pointSize=0,volStep=0,volMin=0,volMax=0;
double realized=0,dailyRealized=0;
string stateBase="",fault="";
datetime lastHistorySync=0;
ulong seenDeals[];

uint HashText(const string value)
{
 uint h=2166136261;
 for(int i=0;i<StringLen(value);i++) { h^=(uint)StringGetCharacter(value,i); h*=16777619; }
 return h;
}
datetime DayStart(datetime t)
{
 MqlDateTime d; TimeToStruct(t,d); d.hour=0; d.min=0; d.sec=0; return StructToTime(d);
}
double PointsToPrice(double points) { return points; } // 100 pontos WIN = 100 unidades de preco.
double NormalizePriceToTick(double price)
{ return NormalizeDouble(MathRound(price/tickSize)*tickSize,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)); }
double NormalizeVolume(double volume)
{
 if(volume<volMin-1e-8 || volume>volMax+1e-8) return 0;
 double result=NormalizeDouble(MathFloor((volume+1e-9)/volStep)*volStep,8);
 return result>=volMin-1e-8 ? result : 0;
}
bool OwnOrder()
{ return OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)==MagicNumber; }
bool OwnPosition()
{ return PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==MagicNumber; }
string Tag(int i,string action,int cycle)
{ return StringFormat("G:%I64d:%d:%s:%d",S.GridID,i+1,action,cycle); }
bool ParseTag(string tag,long &grid,int &index,string &action,int &cycle)
{
 string p[]; if(StringSplit(tag,':',p)!=5 || p[0]!="G") return false;
 grid=StringToInteger(p[1]); index=(int)StringToInteger(p[2])-1;
 action=p[3]; cycle=(int)StringToInteger(p[4]);
 return grid>0 && index>=0 && index<MAX_LEVELS && cycle>=0;
}
bool ParseCurrent(string tag,int &index,string &action,int &cycle)
{ long g; return ParseTag(tag,g,index,action,cycle) && g==S.GridID && index<S.niveis; }
bool IsEntryAction(string action) { return action=="B" || action=="S"; }
int ExitCode(string action) { return action=="T" ? 1 : (action=="X" ? 2 : 3); }
bool IsActive() { return S.GridID>0; }
bool IsClosing() { return S.EstadoAtual==ENCERRANDO_GRID; }
#endif
