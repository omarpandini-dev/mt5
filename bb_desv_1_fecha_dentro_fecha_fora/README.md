# Bollinger desvio 1 — sinais e robô MT5

Arquivos:

- `BB_Desvio1_Sinais.mq5`: indicador que desenha as três linhas de Bollinger e setas de compra/venda.
- `BB_Desvio1_Robo.mq5`: Expert Advisor que executa os mesmos sinais.
- Os respectivos arquivos `.ex5` são as versões compiladas no MetaEditor.

## Regras implementadas

- Bollinger de 20 períodos, desvio padrão 1, média aritmética dos fechamentos (`iBands` do MT5).
- Compra: o penúltimo candle fechou **abaixo** da banda inferior daquele candle; o último candle fechado fechou **acima** da banda inferior dele, fechou acima da abertura e tem `máxima - mínima <= 500` pontos do índice.
- Venda: o penúltimo candle fechou **acima** da banda superior; o último fechou **abaixo** da banda superior, fechou abaixo da abertura e tem `máxima - mínima <= 500`.
- O sinal é confirmado no fechamento do último candle. O robô envia ordem a mercado no primeiro tick do candle seguinte, somente de 13:00 (inclusive) até 15:00 (exclusive), pelo horário do servidor do MT5. O indicador marca a seta no candle de sinal.
- O robô abre somente **uma operação por vez**: não entra se já houver posição do próprio robô em qualquer símbolo da conta, nem se houver outra posição no símbolo do gráfico.
- O período gráfico é escolhido ao anexar os arquivos ao gráfico. Os parâmetros podem ser alterados nas entradas.

## Saída e controle de posições

O padrão usa **alvo de 50 pontos** e **stop de 400 pontos** do índice, calculados a partir do preço de entrada. Outros modos configuráveis permitem usar alvo na linha central da Bollinger com stop na máxima/mínima do candle de sinal, ou operar sem stop/alvo. Se uma posição do robô continuar aberta **às 16:00 ou depois**, o robô envia uma ordem a mercado para encerrá-la, pelo horário do servidor MT5. Essa regra vale mesmo no modo sem alvo/stop. O robô confere isso a cada 10 segundos e a cada novo tick, tentando novamente se a corretora rejeitar o fechamento. Uma posição remanescente de um dia anterior também é encerrada ao religar o robô. O encerramento efetivo depende de o MT5 estar ligado, conectado e de a corretora aceitar a ordem naquele momento.

O robô ignora uma entrada se o stop ou alvo não respeitar o lado correto do preço e a distância mínima exigida pela corretora. Os 500 pontos de amplitude são a diferença direta entre preços do índice, não `500 * _Point`.

## Uso

Copie o indicador para `MQL5/Indicators` e o robô para `MQL5/Experts` da pasta de dados do seu MT5. No Navegador, atualize a lista e anexe ambos ao gráfico do contrato de mini índice desejado. Ajuste lote, horário e modo de saída nas entradas do robô. Faça um teste no Testador de Estratégias antes de habilitar negociação automática.

## Como fazer o backtest

1. No MT5, abra **Arquivo > Abrir Pasta de Dados**. Copie `BB_Desvio1_Robo.ex5` para `MQL5/Experts` dessa pasta. Para usar o indicador separadamente, copie também `BB_Desvio1_Sinais.ex5` para `MQL5/Indicators`. Volte ao MT5 e atualize o **Navegador** (ou reinicie a plataforma).
2. Abra o **Testador de Estratégias** com `Ctrl+R`. Escolha **Teste único** e selecione o Expert `BB_Desvio1_Robo`.
3. Selecione o **símbolo do contrato de mini índice** com histórico disponível na sua corretora, o **período gráfico** desejado (por exemplo, M5) e as **datas** dentro da vigência desse contrato. O robô usa o período selecionado no teste para calcular candles e bandas.
4. Em **Modelagem**, selecione **Cada tick baseado em ticks reais**, se houver histórico de ticks da corretora. Defina o depósito e confira as condições de negociação do símbolo, inclusive custos. O primeiro teste pode levar mais tempo para baixar o histórico.
5. Em **Parâmetros de entrada**, confira `PeriodoBB=20`, `DesvioBB=1`, `MaxAmplitude=500`, `HoraInicio=13`, `HoraFim=15`, `ModoSaida=SAIDA_PONTOS_FIXOS`, `StopPontos=400`, `AlvoPontos=50` e o volume em `Lotes`. O encerramento obrigatório ocorre às 16h. Os horários são os **do servidor usado no teste**; confira a diferença para o horário de Brasília antes de interpretar os resultados.
6. Para acompanhar as operações no gráfico, habilite **Visualização** e deixe a otimização desligada. Clique em **Iniciar**.
7. Ao terminar, confira **Backtest/Resultados**, **Gráfico** e **Diário**: número de operações, lucro líquido, rebaixamento, custos, horários das entradas e eventuais mensagens de ordem rejeitada. Repita o teste em outros períodos e contratos para avaliar a consistência.

O indicador de setas é opcional para executar o robô: o Expert calcula as bandas por conta própria. O backtest é uma simulação baseada no histórico e nas condições configuradas no testador.
