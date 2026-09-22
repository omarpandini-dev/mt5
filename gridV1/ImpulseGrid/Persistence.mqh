#ifndef IMPULSE_PERSISTENCE_MQH
#define IMPULSE_PERSISTENCE_MQH
uint ConfigHash()
{
 // Alteracoes de parametros durante grid ativo exigem concluir o grid com a configuracao original.
 string t=(string)signalTF+"|"+(string)PeriodoMediaVolume+"|"+(string)MultiplicadorVolume+
 "|"+(string)MetodoVolume+"|"+(string)PeriodoMediaAmplitude+"|"+(string)MultiplicadorAmplitude+
 "|"+(string)MetodoCalculoAmplitude+"|"+(string)PeriodoATR+"|"+(string)MultiplicadorATR+
 "|"+(string)PercentualMinimoCorpo+"|"+(string)DistanciaPrimeiraEntrada+"|"+(string)DistanciaEntreEntradas+
 "|"+(string)MaximoNiveisGrid+"|"+(string)LotePadrao+"|"+(string)ModoGrid+"|"+(string)AlvoPontosPorEntrada+
 "|"+(string)MaximoExecucoesPorNivel+"|"+(string)DelayReentradaSegundos+"|"+(string)UsarStopFinanceiroPorEntrada+
 "|"+(string)StopFinanceiroPorEntrada+"|"+(string)RearmarAposStopIndividual+"|"+(string)StopFinanceiroGlobal+
 "|"+(string)AlvoFinanceiroGlobal+"|"+(string)UsarConfirmacaoContinuaGatilho+"|"+(string)MaximoCandlesSemEntrada+
 "|"+(string)UsarStopDiario+"|"+(string)StopFinanceiroDiario+"|"+(string)UsarAlvoDiario+
 "|"+(string)AlvoFinanceiroDiario+"|"+(string)MaximoGridsPorDia+"|"+(string)UsarFiltroHorario+
 "|"+HorarioInicio+"|"+HorarioFinal+"|"+(string)RegraFimHorario;
 return HashText(t);
}
uint BytesHash(uchar &bytes[])
{ uint h=2166136261; for(int i=0;i<ArraySize(bytes);i++) { h^=bytes[i]; h*=16777619; } return h; }
bool ReadSnapshot(string path,PersistedState &out)
{
 int f=FileOpen(path,FILE_READ|FILE_BIN|storageFlags);
 if(f==INVALID_HANDLE) return false;
 bool ok=(FileSize(f)==sizeof(PersistedState)+8);
 uchar raw[]; ArrayResize(raw,sizeof(PersistedState));
 if(ok) ok=(FileReadArray(f,raw,0,ArraySize(raw))==(uint)ArraySize(raw));
 uint checksum=0; int trailer=0;
 if(ok) { checksum=(uint)FileReadInteger(f,INT_VALUE); trailer=FileReadInteger(f,INT_VALUE); }
 if(ok) ok=(checksum==BytesHash(raw) && trailer==0x47524944);
 if(ok) { FileSeek(f,0,SEEK_SET); ok=(FileReadStruct(f,out)==sizeof(PersistedState)); }
 FileClose(f);
 return ok && out.version==STATE_VERSION && out.account==AccountInfoInteger(ACCOUNT_LOGIN) &&
   out.magic==MagicNumber && out.symbolHash==HashText(_Symbol) &&
   out.serverHash==HashText(AccountInfoString(ACCOUNT_SERVER)) && out.niveis>=0 && out.niveis<=MAX_LEVELS;
}
bool SaveGridState()
{
 if(ioFailure) return false;
 S.version=STATE_VERSION; S.account=AccountInfoInteger(ACCOUNT_LOGIN); S.magic=MagicNumber;
 S.symbolHash=HashText(_Symbol); S.serverHash=HashText(AccountInfoString(ACCOUNT_SERVER));
 S.configHash=ConfigHash(); S.timeframe=(int)signalTF;
 S.accountMode=(int)AccountInfoInteger(ACCOUNT_MARGIN_MODE); S.sequence++;
 string path=stateBase+((S.sequence%2)==0 ? ".a" : ".b");
 int f=FileOpen(path,FILE_READ|FILE_WRITE|FILE_BIN|storageFlags);
 bool ok=(f!=INVALID_HANDLE);
 if(ok)
 {
   FileSeek(f,0,SEEK_SET); ok=(FileWriteStruct(f,S)==sizeof(PersistedState));
   FileFlush(f); FileSeek(f,0,SEEK_SET);
   uchar raw[]; ArrayResize(raw,sizeof(PersistedState));
   if(ok) ok=(FileReadArray(f,raw,0,ArraySize(raw))==(uint)ArraySize(raw));
   if(ok) ok=(FileWriteInteger(f,(int)BytesHash(raw),INT_VALUE)==4 && FileWriteInteger(f,0x47524944,INT_VALUE)==4);
   FileFlush(f); FileClose(f);
 }
 if(!ok) { ioFailure=true; fault="Falha de persistencia. Novos envios bloqueados."; Print(fault," erro=",GetLastError()); }
 return ok;
}
bool InitStorage()
{
 bool tester=(bool)MQLInfoInteger(MQL_TESTER);
 storageFlags=tester ? 0 : FILE_COMMON;
 stateBase=StringFormat("ImpulseGrid_%I64d_%u_%u_%I64d",AccountInfoInteger(ACCOUNT_LOGIN),
   HashText(AccountInfoString(ACCOUNT_SERVER)),HashText(_Symbol),MagicNumber);
 // Sem FILE_SHARE_*: apenas uma instancia por conta/servidor/simbolo/magic.
 lockHandle=FileOpen(stateBase+".lock",FILE_READ|FILE_WRITE|FILE_BIN|storageFlags);
 if(lockHandle==INVALID_HANDLE) { Print("Outra instancia possui o lock, ou arquivo indisponivel."); return false; }
 if(tester)
 {
   FileDelete(stateBase+".a",storageFlags); FileDelete(stateBase+".b",storageFlags);
   return true; // Cada passe de teste comeca limpo.
 }
 PersistedState a,b; bool aa=ReadSnapshot(stateBase+".a",a),bb=ReadSnapshot(stateBase+".b",b);
 if(aa || bb)
 {
   if(aa && (!bb || a.sequence>b.sequence)) S=a; else S=b;
   if(IsActive() && (S.configHash!=ConfigHash() || S.accountMode!=(int)AccountInfoInteger(ACCOUNT_MARGIN_MODE)))
   { Print("Grid persistido exige os parametros e tipo de conta originais."); return false; }
   Print("Snapshot restaurado: grid=",S.GridID," primeira entrada=",S.GridJaTeveEntrada);
 }
 else if(FileIsExist(stateBase+".a",storageFlags) || FileIsExist(stateBase+".b",storageFlags))
 { Print("Ambos snapshots invalidos. Recuperacao automatica bloqueada para preservar exposicao."); return false; }
 return true;
}
#endif
