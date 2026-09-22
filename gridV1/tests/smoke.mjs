// Portable smoke tests of selected PRODUCTION function bodies, not a second EA.
// Only scalar declarations/casts are translated to JS. Terminal APIs are stubs.
// This is not an MQL compiler or a substitute for MetaEditor/Strategy Tester.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const modules = ['Types', 'Signals', 'Ledger', 'Execution', 'Manager'];
const source = modules.map(n => fs.readFileSync(path.join(root, 'ImpulseGrid', n + '.mqh'), 'utf8')).join('\n');
const clean = source.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, '');
const context = {
  MathAbs: Math.abs, MathMax: Math.max, MathMin: Math.min, MathFloor: Math.floor, MathRound: Math.round,
  NormalizeDouble: (x, n) => Number(x.toFixed(n)), symbolDigits: 0,
  _Symbol: 'WIN_TEST', SYMBOL_DIGITS: 0, MAX_LEVELS: 100,
  Print() {}, TimeToString: String, EnumToString: String,
  now: 2000, SaveGridState: () => true,
  ZeroMemory: object => { for (const key of Object.keys(object)) object[key] = 0; },
};
for (const match of clean.matchAll(/enum\s+\w+\s*\{([^}]+)\}/g)) {
  match[1].split(',').map(x => x.trim()).filter(Boolean).forEach((name, i) => { context[name] = i; });
}
for (const match of clean.matchAll(/input\s+\w+\s+(\w+)\s*=\s*([^;]+);/g)) {
  const [, name, value] = match;
  context[name] = Object.hasOwn(context, value) ? context[value] :
    value === 'true' ? true : value === 'false' ? false : /^"/.test(value) ? JSON.parse(value) : Number(value);
}
const empty = () => new Proxy({}, { get: (o, key) => Object.hasOwn(o, key) ? o[key] : 0 });
context.TimeCurrent = () => context.now;
context.SymbolInfoInteger = () => context.symbolDigits;
context.HasIntents = () => context.S.levels.some(l => l.intento !== 0);
context.LevelHasPendingOrder = i => Boolean(context.S.levels[i].ticketOrdem);
context.LevelHasOpenPosition = i => Boolean(context.legs[i].ativa);
vm.createContext(context);
const selected = ['PointsToPrice', 'NormalizePriceToTick', 'NormalizeVolume', 'IsActive', 'IsClosing',
  'ClassifyCandle', 'BuildGridLevels', 'ConfirmFirstGridExecution', 'BeginClose',
  'CancelUnconfirmedGrid', 'HandleOppositeTrigger', 'ValidateUnconfirmedCandle', 'LevelCanBeRearmed'];
function loadFunctions(names) { for (const name of names) {
  const regex = new RegExp('(?:bool|double|void|int|TipoGatilho)\\s+' + name + '\\s*\\(([^)]*)\\)\\s*\\{');
  const m = regex.exec(clean);
  assert(m, 'Missing production function ' + name);
  const begin = m.index + m[0].length;
  let depth = 1, end = begin;
  while (depth > 0 && end < clean.length) {
    if (clean[end] === '{') depth++;
    if (clean[end] === '}') depth--;
    end++;
  }
  const args = m[1].split(',').filter(s => s.trim()).map(s => s.trim().match(/(\w+)(?:\[\])?$/)[1]).join(',');
  const body = clean.slice(begin, end - 1)
    .replace('arr[(left+right)/2]', 'arr[Math.floor((left+right)/2)]')
    .replace(/\((?:int|long|double|ulong|uint|datetime|TipoGatilho|ENUM_DEAL_ENTRY|ENUM_DEAL_TYPE)\)/g, '')
    .replace(/\b(?:ulong|EntryMap)\s+(\w+)\[\]/g, 'let $1 = []')
    .replace(/\b(?:bool|double|int|long|string|datetime|ulong|TipoGatilho|ENUM_DEAL_ENTRY|ENUM_DEAL_TYPE)\s+(\w+)/g, 'let $1')
    .replace(/ParseCurrent\((.*?),i,a,c\)/g, 'ParseRef($1, v => i=v, v => a=v, v => c=v)')
    .replace('EvaluateSignal(shift,available)', 'EvaluateSignalRef(shift, v => available=v)');
  vm.runInContext(`function ${name}(${args}) {${body}}`, context, { filename: name + '.production.mqh' });
} }
loadFunctions(selected);
function reset() {
  const s = context.S = empty();
  s.levels = Array.from({ length: 100 }, empty);
  context.legs = Array.from({ length: 100 }, empty);
  Object.assign(s, { GridID: 1700000000, direcao: context.GATILHO_COMPRA, niveis: 4,
    CandleGatilhoClose: 190600, CandleGatilhoTime: 1000, UltimoCandleValidacaoTime: 1000,
    PermitirRearmeGrid: true, EstadoAtual: context.GRID_AGUARDANDO_PRIMEIRA_ENTRADA_COMPRA });
  Object.assign(context, { tickSize: 5, pointSize: 1, volStep: 1, volMin: 1, volMax: 100, symbolDigits: 0,
    historyReady: true, ioFailure: false, ledgerError: false, MaximoExecucoesPorNivel: 0, DelayReentradaSegundos: 0,
    UsarConfirmacaoContinuaGatilho: true, MaximoCandlesSemEntrada: 0, RearmarAposStopIndividual: false });
  context.BuildGridLevels();
  return s;
}
let passed = 0;
function test(name, fn) { reset(); fn(); passed++; console.log('PASS ' + name); }
const c = context;
test('WIN price units and tick normalization', () => {
  assert.equal(c.PointsToPrice(100), 100);
  assert.equal(c.NormalizePriceToTick(190502), 190500);
  c.tickSize = 0.25; c.symbolDigits = 2; assert.equal(c.NormalizePriceToTick(100.38), 100.5);
});
test('valid volume and nondecimal step', () => {
  assert.equal(c.NormalizeVolume(0.5), 0); assert.equal(c.NormalizeVolume(101), 0);
  c.volMin = c.volStep = 0.25; assert.equal(c.NormalizeVolume(1.39), 1.25);
});
test('fixed BUY levels and individual targets', () => {
  assert.deepEqual(c.S.levels.slice(0, 4).map(l => l.precoEntrada), [190500,190450,190400,190350]);
  assert.deepEqual(c.S.levels.slice(0, 4).map(l => l.precoAlvo), [190550,190500,190450,190400]);
});
test('SELL direction and targets', () => {
  c.S.direcao = c.GATILHO_VENDA; c.BuildGridLevels();
  assert.deepEqual(c.S.levels.slice(0, 4).map(l => l.precoEntrada), [190700,190750,190800,190850]);
  assert.equal(c.S.levels[0].precoAlvo, 190650);
});
test('signal requires volume, range, body and direction', () => {
  const b = { open: 100, close: 180, high: 200, low: 100 };
  assert.equal(c.ClassifyCandle(b, 200, 100, 50), c.GATILHO_COMPRA);
  assert.equal(c.ClassifyCandle(b, 199, 100, 50), c.SEM_GATILHO);
  assert.equal(c.ClassifyCandle(b, 200, 100, 100), c.SEM_GATILHO);
  b.close = 159; assert.equal(c.ClassifyCandle(b, 200, 100, 50), c.SEM_GATILHO);
  b.close = 160; assert.equal(c.ClassifyCandle(b, 200, 100, 50), c.GATILHO_COMPRA);
  b.open = 200; b.close = 120; assert.equal(c.ClassifyCandle(b, 200, 100, 50), c.GATILHO_VENDA);
  b.close = 200; assert.equal(c.ClassifyCandle(b, 200, 100, 50), c.SEM_GATILHO);
  b.high = b.low; assert.equal(c.ClassifyCandle(b, 200, 100, 50), c.SEM_GATILHO);
});
test('original candle is not its own confirmation', () => {
  c.ValidateUnconfirmedCandle(c.SEM_GATILHO, 1000);
  assert.equal(c.S.candlesEspera, 0); assert.equal(c.IsClosing(), false);
});
test('consecutive triggers keep prices; no trigger cancels', () => {
  c.ValidateUnconfirmedCandle(c.GATILHO_COMPRA, 1100);
  c.ValidateUnconfirmedCandle(c.GATILHO_COMPRA, 1200);
  assert.equal(c.S.mantidos, 2); assert.equal(c.S.levels[1].precoEntrada, 190450);
  c.ValidateUnconfirmedCandle(c.SEM_GATILHO, 1300);
  assert.equal(c.IsClosing(), true); assert.equal(c.S.PermitirRearmeGrid, false);
});
test('same closed candle cannot increment twice', () => {
  c.ValidateUnconfirmedCandle(c.GATILHO_COMPRA, 1100);
  c.ValidateUnconfirmedCandle(c.GATILHO_COMPRA, 1100);
  assert.equal(c.S.candlesEspera, 1); assert.equal(c.S.mantidos, 1);
});
test('first fill permanently disables trigger cancellation', () => {
  c.ConfirmFirstGridExecution(); c.ConfirmFirstGridExecution();
  c.ValidateUnconfirmedCandle(c.SEM_GATILHO, 1100);
  c.ValidateUnconfirmedCandle(c.GATILHO_VENDA, 1200);
  assert.equal(c.S.EstadoAtual, c.GRID_COMPRA_ATIVO); assert.equal(c.S.comEntrada, 1);
  assert.equal(c.S.pendingSignalTime, 0);
});
test('opposite trigger retained during cancellation', () => {
  c.ValidateUnconfirmedCandle(c.GATILHO_VENDA, 1100);
  assert.equal(c.S.pendingSignalTime, 1100); assert.equal(c.S.pendingSignalDirection, c.GATILHO_VENDA);
  assert.equal(c.IsClosing(), true); assert.equal(c.LevelCanBeRearmed(0), false);
});
test('disabling continuous confirmation retains unfilled grid', () => {
  c.UsarConfirmacaoContinuaGatilho = false;
  c.ValidateUnconfirmedCandle(c.SEM_GATILHO, 1100);
  assert.equal(c.IsClosing(), false);
});
test('secondary candle limit does not replace confirmation', () => {
  c.MaximoCandlesSemEntrada = 2;
  c.ValidateUnconfirmedCandle(c.GATILHO_COMPRA, 1100);
  c.ValidateUnconfirmedCandle(c.GATILHO_COMPRA, 1200);
  assert.equal(c.S.motivo, c.LIMITE_CANDLES);
});
test('one exposure per level and unresolved send barrier', () => {
  assert.equal(c.LevelCanBeRearmed(0), true);
  c.S.levels[0].ticketOrdem = 99; assert.equal(c.LevelCanBeRearmed(0), false);
  c.S.levels[0].ticketOrdem = 0; c.legs[0].ativa = true; assert.equal(c.LevelCanBeRearmed(0), false);
  c.legs[0].ativa = false; c.S.levels[2].intento = 1; assert.equal(c.LevelCanBeRearmed(0), false);
});
test('only normal TP rearms by default', () => {
  c.S.levels[0].quantidadeExecucoes = 1;
  for (const reason of [0, 2, 3]) { c.legs[0].ultimaSaida = reason; assert.equal(c.LevelCanBeRearmed(0), false); }
  c.legs[0].ultimaSaida = 1; assert.equal(c.LevelCanBeRearmed(0), true);
  c.legs[0].ultimaSaida = 2; c.RearmarAposStopIndividual = true; assert.equal(c.LevelCanBeRearmed(0), true);
});
test('reentry delay and execution cap', () => {
  c.S.levels[0].quantidadeExecucoes = 2; c.legs[0].ultimaSaida = 1;
  c.S.levels[0].horarioPermitidoRearme = 2001; assert.equal(c.LevelCanBeRearmed(0), false);
  c.S.levels[0].horarioPermitidoRearme = 2000; assert.equal(c.LevelCanBeRearmed(0), true);
  c.MaximoExecucoesPorNivel = 2; assert.equal(c.LevelCanBeRearmed(0), false);
});
// Replay the actual ledger against a deterministic fake broker. No orders are sent.
const properties = `DEAL_SYMBOL DEAL_MAGIC DEAL_ENTRY DEAL_POSITION_ID DEAL_ORDER DEAL_COMMENT DEAL_TIME_MSC
DEAL_TIME DEAL_PROFIT DEAL_COMMISSION DEAL_SWAP DEAL_FEE DEAL_VOLUME DEAL_PRICE DEAL_TYPE DEAL_REASON
ORDER_MAGIC ORDER_SYMBOL ORDER_COMMENT ORDER_STATE ORDER_VOLUME_INITIAL ORDER_VOLUME_CURRENT
POSITION_SYMBOL POSITION_MAGIC POSITION_IDENTIFIER POSITION_VOLUME POSITION_TYPE POSITION_TICKET
POSITION_PROFIT POSITION_SWAP`;
for (const key of properties.split(/\s+/)) c[key] = key;
for (const key of ['DEAL_ENTRY_IN','DEAL_ENTRY_OUT','DEAL_ENTRY_INOUT','DEAL_ENTRY_OUT_BY',
  'DEAL_TYPE_BUY','DEAL_TYPE_SELL','DEAL_REASON_TP','ORDER_STATE_FILLED','ORDER_STATE_CANCELED',
  'ORDER_STATE_REJECTED','ORDER_STATE_EXPIRED','POSITION_TYPE_BUY','POSITION_TYPE_SELL']) c[key] = key;
c.ArraySize = a => a.length;
c.ArrayResize = (a, n) => { while (a.length < n) a.push(empty()); a.length = n; return n; };
c.HistorySelect = () => { c.book.selectedDeals = c.book.deals; return true; };
c.HistorySelectByPosition = id => { c.book.selectedDeals = c.book.deals.filter(d => d.DEAL_POSITION_ID === id); return true; };
c.HistoryDealsTotal = () => c.book.selectedDeals.length;
c.HistoryDealGetTicket = i => c.book.selectedDeals[i].id;
const dealProperty = (id, prop) => c.book.deals.find(d => d.id === id)?.[prop] ?? 0;
c.HistoryDealGetInteger = c.HistoryDealGetDouble = dealProperty;
c.HistoryDealGetString = (id, prop) => dealProperty(id, prop) || '';
c.HistoryOrdersTotal = () => c.book.historyOrders.length;
c.HistoryOrderGetTicket = i => c.book.historyOrders[i].id;
const orderProperty = (id, prop) => c.book.historyOrders.find(o => o.id === id)?.[prop] ?? 0;
c.HistoryOrderGetInteger = c.HistoryOrderGetDouble = orderProperty;
c.HistoryOrderGetString = (id, prop) => orderProperty(id, prop) || '';
c.OrdersTotal = () => c.book.orders.length;
c.OrderGetTicket = i => { c.book.selectedOrder = c.book.orders[i]; return c.book.selectedOrder?.id ?? 0; };
c.OrderSelect = id => { c.book.selectedOrder = c.book.orders.find(o => o.id === id); return !!c.book.selectedOrder; };
c.OrderGetInteger = c.OrderGetDouble = p => c.book.selectedOrder?.[p] ?? 0;
c.OrderGetString = p => c.book.selectedOrder?.[p] ?? '';
c.PositionsTotal = () => c.book.positions.length;
c.PositionGetTicket = i => { c.book.selectedPosition = c.book.positions[i]; return c.book.selectedPosition?.id ?? 0; };
c.PositionSelect = symbol => { c.book.selectedPosition = c.book.positions.find(p => p.POSITION_SYMBOL === symbol); return !!c.book.selectedPosition; };
c.PositionGetInteger = c.PositionGetDouble = p => c.book.selectedPosition?.[p] ?? 0;
c.PositionGetString = p => c.book.selectedPosition?.[p] ?? '';
c.Tag = (i, action, cycle) => `G:${c.S.GridID}:${i+1}:${action}:${cycle}`;
c.ParseRef = (tag, index, action, cycle) => {
  const match = /^G:(\d+):(\d+):([A-Z]):(\d+)$/.exec(tag);
  if (!match || Number(match[1]) !== c.S.GridID) return false;
  index(Number(match[2])-1); action(match[3]); cycle(Number(match[4])); return true;
};
c.DealTag = id => c.HistoryDealGetString(id, 'DEAL_COMMENT') ||
  c.HistoryOrderGetString(dealProperty(id, 'DEAL_ORDER'), 'ORDER_COMMENT');
c.entryMap = []; c.ownedPositionIds = []; c.seenDeals = [];
loadFunctions(['Contains','AddUnique','PositionLevel','DealBefore','SortDeals','IsTerminalOrder',
  'OwnOrder','OwnPosition','IsEntryAction','ExitCode','ResolveIntent','RebuildGridState','NettingExclusive',
  'CalculateGridRealizedResult','CalculateGridFloatingResult','CalculateGridTotalResult','LevelHasPendingOrder']);
function broker() {
  c.book = { deals: [], historyOrders: [], orders: [], positions: [], selectedDeals: [] };
  c.hedging = false; c.dirty = true;
}
function order(id, level, action, initial = 1, remaining = 0, state = 'ORDER_STATE_FILLED') {
  const o = { id, ORDER_SYMBOL: c._Symbol, ORDER_MAGIC: c.MagicNumber, ORDER_COMMENT: c.Tag(level, action, id),
    ORDER_STATE: state, ORDER_VOLUME_INITIAL: initial, ORDER_VOLUME_CURRENT: remaining };
  c.book.historyOrders.push(o); return o;
}
function deal(id, orderId, price, volume = 1, out = false, profit = 0, pid = 101) {
  const d = { id, DEAL_SYMBOL: c._Symbol, DEAL_MAGIC: c.MagicNumber, DEAL_ENTRY: out ? c.DEAL_ENTRY_OUT : c.DEAL_ENTRY_IN,
    DEAL_POSITION_ID: pid, DEAL_ORDER: orderId, DEAL_TIME: 1200 + id, DEAL_TIME_MSC: (1200 + id) * 1000,
    DEAL_VOLUME: volume, DEAL_PRICE: price, DEAL_TYPE: out ? c.DEAL_TYPE_SELL : c.DEAL_TYPE_BUY, DEAL_PROFIT: profit };
  c.book.deals.push(d); return d;
}
function position(volume, profit = 0, pid = 101) {
  const p = { id: pid, POSITION_TICKET: pid, POSITION_SYMBOL: c._Symbol, POSITION_MAGIC: c.MagicNumber,
    POSITION_IDENTIFIER: pid, POSITION_VOLUME: volume, POSITION_TYPE: c.POSITION_TYPE_BUY, POSITION_PROFIT: profit };
  c.book.positions.push(p); return p;
}
test('ledger replay is idempotent with out-of-order deal enumeration', () => {
  broker(); order(11, 0, 'B'); order(12, 1, 'B');
  deal(2, 12, 190450); deal(1, 11, 190500); position(2);
  assert.equal(c.RebuildGridState(), true); assert.equal(c.ledgerError, false);
  assert.equal(c.S.comEntrada, 1); assert.equal(c.S.levels[1].quantidadeExecucoes, 1);
  c.RebuildGridState();
  assert.equal(c.S.comEntrada, 1); assert.equal(c.S.levels[1].quantidadeExecucoes, 1);
  assert.equal(c.legs[1].volume, 1); assert.equal(c.NettingExclusive(), true);
});
test('NETTING L2 TP leaves L1 active and uses actual broker PnL', () => {
  broker(); order(11, 0, 'B'); order(12, 1, 'B'); order(21, 1, 'T');
  deal(1, 11, 190500); deal(2, 12, 190450); deal(3, 21, 190500, 1, true, 5); position(1, 5);
  c.RebuildGridState();
  assert.equal(c.ledgerError, false); assert.equal(c.legs[0].volume, 1); assert.equal(c.legs[1].volume, 0);
  assert.equal(c.legs[1].ultimaSaida, 1); assert.equal(c.CalculateGridTotalResult(), 10);
  assert.equal(c.LevelCanBeRearmed(1), true); assert.equal(c.LevelCanBeRearmed(0), false);
  order(13, 1, 'B'); deal(4, 13, 190450); c.book.positions[0].POSITION_VOLUME = 2;
  c.RebuildGridState();
  assert.equal(c.ledgerError, false); assert.equal(c.S.levels[1].quantidadeExecucoes, 2);
  assert.equal(c.S.levels[1].precoEntrada, 190450);
});
test('partial fills of the same entry count only once', () => {
  broker(); order(11, 0, 'B', 2); deal(1, 11, 190500); deal(2, 11, 190495); position(2);
  c.RebuildGridState();
  assert.equal(c.ledgerError, false); assert.equal(c.S.levels[0].quantidadeExecucoes, 1);
  assert.equal(c.legs[0].volume, 2); assert.equal(c.legs[0].precoEntradaReal, 190497.5);
});
test('ORDER_DELETE before DEAL_ADD cannot cause duplicate reentry', () => {
  broker(); order(11, 0, 'B'); c.S.levels[0].ultimaOrdemEntrada = 11;
  c.RebuildGridState();
  assert.equal(c.ledgerError, true); assert.equal(c.LevelCanBeRearmed(0), false);
  deal(1, 11, 190500); position(1); c.RebuildGridState();
  assert.equal(c.ledgerError, false); assert.equal(c.legs[0].ativa, true);
});
test('manual pending cancellation persists across another replay', () => {
  broker(); order(11, 0, 'B', 1, 1, 'ORDER_STATE_CANCELED'); c.S.levels[0].ultimaOrdemEntrada = 11;
  c.RebuildGridState(); c.RebuildGridState();
  assert.equal(c.S.manualDetected, true); assert.equal(c.LevelCanBeRearmed(0), false);
});
test('manual NETTING partial exit disables recycling and reconciles volume', () => {
  broker(); order(11, 0, 'B'); order(12, 1, 'B');
  deal(1, 11, 190500); deal(2, 12, 190450);
  const exit = deal(3, 99, 190490, 1, true, 3); exit.DEAL_MAGIC = 0;
  position(1); c.RebuildGridState();
  assert.equal(c.ledgerError, false); assert.equal(c.externalExit, true);
  assert.equal(c.legs[0].volume + c.legs[1].volume, 1); assert.equal(c.NettingExclusive(), true);
  assert.equal(c.LevelCanBeRearmed(0), false);
});
test('HEDGING server TP maps by position identifier', () => {
  broker(); c.hedging = true; order(11, 0, 'B'); deal(1, 11, 190500);
  const exit = deal(2, 99, 190550, 1, true, 10); exit.DEAL_REASON = c.DEAL_REASON_TP;
  c.RebuildGridState();
  assert.equal(c.ledgerError, false); assert.equal(c.legs[0].ultimaSaida, 1);
  assert.equal(c.LevelCanBeRearmed(0), true); assert.equal(c.realized, 10);
});
test('foreign NETTING entry prevents automatic management', () => {
  broker(); order(11, 0, 'B'); deal(1, 11, 190500);
  const foreign = deal(2, 99, 190450); foreign.DEAL_MAGIC = 999;
  position(2); c.RebuildGridState();
  assert.equal(c.ledgerError, true); assert.equal(c.NettingExclusive(), false);
});
loadFunctions(['ProcessNewClosedBar']);
c.signalTF = 'M5';
c.iTime = (_, __, shift) => c.bars[shift]?.time ?? 0;
c.iBarShift = (_, __, time) => c.bars.findIndex(b => b.time === time);
c.EvaluateSignalRef = (shift, available) => { available(c.bars[shift].available !== false); return c.bars[shift].signal; };
c.StartGrid = () => { throw new Error('Unexpected new grid before pending reversal validation'); };
test('queued reversal is revalidated even after old grid already finished', () => {
  c.S.GridID = 0; c.S.EstadoAtual = c.AGUARDANDO_SINAL;
  c.S.pendingSignalTime = 1100; c.S.pendingSignalDirection = c.GATILHO_VENDA; c.S.lastBar = 1200;
  c.bars = [{ time: 1300 }, { time: 1200, signal: c.SEM_GATILHO }, { time: 1100, signal: c.GATILHO_VENDA }];
  c.ProcessNewClosedBar(); assert.equal(c.S.pendingSignalTime, 0); assert.equal(c.S.lastBar, 1300);
});
test('missing indicator history is not a failed confirmation', () => {
  c.S.lastBar = 1100;
  c.bars = [{ time: 1200 }, { time: 1100, signal: c.SEM_GATILHO, available: false }];
  c.ProcessNewClosedBar(); assert.equal(c.IsClosing(), false); assert.equal(c.S.lastBar, 1100);
});
test('restart validates every missed closed candle in chronological order', () => {
  c.S.lastBar = 1100;
  c.bars = [{ time: 1400 }, { time: 1300, signal: c.GATILHO_COMPRA },
    { time: 1200, signal: c.SEM_GATILHO }, { time: 1100, signal: c.GATILHO_COMPRA }];
  c.ProcessNewClosedBar(); assert.equal(c.IsClosing(), true); assert.equal(c.S.candlesEspera, 2);
  assert.equal(c.S.mantidos, 1); assert.equal(c.S.pendingSignalTime, 0);
});
console.log(`${passed} portable smoke scenarios passed. Native compilation/backtest NOT performed.`);
