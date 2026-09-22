#property strict
#property script_show_inputs
#include <Trade/Trade.mqh>
#include "../ImpulseGrid/Types.mqh"
#include "../ImpulseGrid/Signals.mqh"
#include "../ImpulseGrid/Persistence.mqh"
#include "../ImpulseGrid/Ledger.mqh"
#include "../ImpulseGrid/Execution.mqh"
#include "../ImpulseGrid/Manager.mqh"

// Testes das funcoes de producao. Nao chama OrderSend, CTrade ou gerenciadores
// de negociacao. Executar como SCRIPT, com parametros padrao, em qualquer grafico.
int passed=0,failed=0;
void Check(bool condition,string name)
{
 if(condition) { passed++; Print("PASS: ",name); }
 else { failed++; Print("FAIL: ",name); }
}
bool Near(double a,double b) { return MathAbs(a-b)<0.0000001; }
void ResetFixture()
{
 ZeroMemory(S); for(int i=0;i<MAX_LEVELS;i++) ZeroMemory(legs[i]);
 S.GridID=1700000000; S.direcao=GATILHO_COMPRA; S.niveis=4;
 S.CandleGatilhoClose=190600; S.CandleGatilhoTime=1699999900;
 S.PermitirRearmeGrid=true; S.EstadoAtual=GRID_AGUARDANDO_PRIMEIRA_ENTRADA_COMPRA;
 S.day=DayStart(TimeCurrent());
 tickSize=5; pointSize=1; volStep=1; volMin=1; volMax=100;
 signalTF=PERIOD_M5; storageFlags=0; ioFailure=false;
}
void OnStart()
{
 if(DistanciaPrimeiraEntrada!=100 || DistanciaEntreEntradas!=50 || AlvoPontosPorEntrada!=50 ||
    LotePadrao!=1 || MultiplicadorVolume!=2 || MultiplicadorAmplitude!=1.5 || PercentualMinimoCorpo!=60 ||
    MetodoCalculoAmplitude!=MEDIA_AMPLITUDE)
 { Print("Executar testes com os parametros padrao."); return; }
 stateBase="ImpulseGrid_UNIT_"+(string)GetTickCount64();
 ResetFixture();
 Check(Near(PointsToPrice(100),100),"WIN: 100 pontos correspondem a 100 unidades de preco");
 Check(Near(NormalizePriceToTick(190502),190500),"Tick consultado/parametrizado");
 Check(Near(NormalizeVolume(1),1) && NormalizeVolume(0.5)==0 && NormalizeVolume(101)==0,"Limites de volume");
 volStep=0.25; volMin=0.25;
 Check(Near(NormalizeVolume(1.39),1.25),"Passo de volume nao decimal");
 volStep=1; volMin=1;
 BuildGridLevels();
 Check(Near(S.levels[0].precoEntrada,190500) && Near(S.levels[3].precoEntrada,190350),"Grid de compra do exemplo");
 Check(Near(S.levels[0].precoAlvo,190550) && Near(S.levels[3].precoAlvo,190400),"TPs de compra");
 S.direcao=GATILHO_VENDA; BuildGridLevels();
 Check(Near(S.levels[0].precoEntrada,190700) && Near(S.levels[3].precoEntrada,190850),"Grid de venda");
 Check(Near(S.levels[0].precoAlvo,190650),"TP de venda abaixo da entrada");
 MqlRates bar={}; bar.open=100; bar.low=100; bar.high=200; bar.close=180;
 Check(ClassifyCandle(bar,200,100,50)==GATILHO_COMPRA,"Candle expressivo de compra");
 Check(ClassifyCandle(bar,199,100,50)==SEM_GATILHO,"Rejeitar volume abaixo do limiar");
 Check(ClassifyCandle(bar,200,100,100)==SEM_GATILHO,"Rejeitar amplitude insuficiente");
 bar.close=150;
 Check(ClassifyCandle(bar,200,100,50)==SEM_GATILHO,"Rejeitar corpo pequeno");
 bar.close=160;
 Check(ClassifyCandle(bar,200,100,50)==GATILHO_COMPRA,"Aceitar corpo no limiar exato");
 bar.open=200; bar.close=120;
 Check(ClassifyCandle(bar,200,100,50)==GATILHO_VENDA,"Candle expressivo de venda");
 bar.close=bar.open;
 Check(ClassifyCandle(bar,200,100,50)==SEM_GATILHO,"Rejeitar doji");
 bar.high=bar.low;
 Check(ClassifyCandle(bar,200,100,50)==SEM_GATILHO,"Rejeitar amplitude zero sem divisao por zero");
 ResetFixture(); BuildGridLevels(); S.candlesEspera=2;
 ConfirmFirstGridExecution(); ConfirmFirstGridExecution();
 Check(S.GridJaTeveEntrada && S.comEntrada==1 && S.EstadoAtual==GRID_COMPRA_ATIVO,"Primeira execucao idempotente");
 Check(S.candlesEsperaTotal==2 && S.gridsEsperaFinalizada==1,"Estatisticas nao duplicadas");
 CancelUnconfirmedGrid("Teste: cancelar confirmado deve ser ignorado");
 Check(S.EstadoAtual==GRID_COMPRA_ATIVO && S.PermitirRearmeGrid,"Nao invalidar depois da primeira entrada");
 ResetFixture(); BuildGridLevels(); CancelUnconfirmedGrid("Teste: candle sem confirmacao");
 Check(IsClosing() && !S.PermitirRearmeGrid && S.motivo==SEM_CONFIRMACAO_GATILHO,"Invalidacao bloqueia rearme antes de cancelar");
 Check(!LevelCanBeRearmed(0),"Rearme proibido durante encerramento");
 ResetFixture(); BuildGridLevels(); S.pendingSignalTime=1700000100;
 HandleOppositeTrigger(GATILHO_VENDA);
 Check(IsClosing() && S.pendingSignalDirection==GATILHO_VENDA && S.pendingSignalTime==1700000100,"Preservar sinal contrario enquanto cancela");
 Check(Near(S.levels[0].precoEntrada,190500),"Invalidacao nao move os niveis originais");
 int index,cycle; string action; long grid;
 Check(ParseTag(Tag(3,"T",17),grid,index,action,cycle) && grid==S.GridID && index==3 && action=="T" && cycle==17,"Comentarios reconstruiveis");
 Check(!ParseTag("manual",grid,index,action,cycle),"Nao assumir propriedade de comentario desconhecido");
 Check(ExitCode("T")==1 && ExitCode("X")==2 && ExitCode("C")==3,"Distinguir alvo, stop individual e encerramento");
 S.GridJaTeveEntrada=true; S.UltimoCandleValidacaoTime=1700000200;
 S.levels[2].intento=1; S.levels[2].cicloIntento=42;
 Check(SaveGridState(),"Gravar snapshot");
 PersistedState recovered;
 string latest=stateBase+((S.sequence%2)==0 ? ".a" : ".b");
 Check(ReadSnapshot(latest,recovered) && recovered.GridJaTeveEntrada &&
    recovered.UltimoCandleValidacaoTime==1700000200 && recovered.levels[2].cicloIntento==42 &&
    recovered.pendingSignalTime==1700000100,"Restaurar primeira entrada, validacao, sinal e intento");
 Check(SaveGridState(),"Segunda copia de snapshot");
 latest=stateBase+((S.sequence%2)==0 ? ".a" : ".b");
 string backup=stateBase+((S.sequence%2)==0 ? ".b" : ".a");
 int f=FileOpen(latest,FILE_WRITE|FILE_BIN); if(f!=INVALID_HANDLE) { FileWriteInteger(f,0); FileClose(f); }
 Check(!ReadSnapshot(latest,recovered) && ReadSnapshot(backup,recovered),"Detectar snapshot truncado e preservar backup");
 FileDelete(stateBase+".a"); FileDelete(stateBase+".b");
 PrintFormat("IMPULSE GRID TESTS: %d PASS, %d FAIL",passed,failed);
}
