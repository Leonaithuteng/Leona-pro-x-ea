#property strict
#property version "3.2"
#property description "Leona Pro X EA LIVE v3.2 - API-connected adaptive synthetic scalper"

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

input group "Trading Parameters"
input double LotSize = 0.01;
input double RiskPercent = 1.0;
input int MaxSpread = 0; // Legacy fixed-point filter disabled by default
input bool UseSmartSpreadFilter = true;
input double MaxSpreadATRPercent = 75.0;
input double MaxSpreadPricePercent = 0.020;
input bool ShowSpreadDiagnostics = true;
input int SL_Points = 150;
input int TP_Points = 250;
input bool UseATRStops = true;
input double ATR_SL_Multiplier = 1.20;
input int ATR_MinSLPoints = 150;
input int ATR_MaxSLPoints = 5000;
input double ATR_RiskReward = 1.80;
input bool EA_Active = true;

input group "Filters"
input int MinVolatility = 60;
input int MaxVolatility = 300;
input bool UseAdaptiveVolatilityFilter = true;
input double MinATRPricePercent = 0.01;
input double MaxATRPricePercent = 1.00;
input double MinSyntheticATRPrice = 0.0;
input double MaxSyntheticATRPrice = 1000000.0;
input double MinTrendStrength = 2.5;
input int AIScoreThreshold = 2; // Aggressive default: low threshold for frequent synthetic scalping entries

input group "Time & Cooldown"
input int CooldownSeconds = 1;
input int MaxTradesPerHour = 100;
input bool TradeDuringNews = false;
input int StartHour = 0;
input int EndHour = 23;

input group "Exit Strategies"
input bool UseTrailingStop = true;
input int TrailingStart = 80;
input int TrailingStep = 20;
input bool UseBreakEven = true;
input int BreakEvenTrigger = 50;

input group "Risk Management"
input double MaxDailyLoss = 3.0;
input double MaxDrawdown = 10.0;
input bool UseEquityProtection = true;
input int MaxConsecutiveLosses = 10;

input group "Local Control"
input bool StartOnAttach = true;
input bool ShowChartControls = true;
input bool AggressiveScalping = true;
input int MaxOpenPositions = 100;
input double MinimumAccountBalance = 2.0;
input int MinimumProfitScalePositions = 5;
input double ProfitRequiredToScale = 0.01;
input double MinimumMarginLevelToAdd = 300.0;
input double MinMarginLevel = 300.0;
input double MaxLotPercentOfBalance = 5.0;
input double BalancePerOpenTrade = 100.0;
input int MaxSlippagePoints = 20;
input int MaxOpenPositions = 100;
input double MinimumAccountBalance = 2.0;
input int MinimumProfitScalePositions = 5;
input double ProfitRequiredToScale = 0.01;
input double MinimumMarginLevelToAdd = 300.0;
input double MinMarginLevel = 300.0;
input double MaxLotPercentOfBalance = 5.0;
input double BalancePerOpenTrade = 100.0;
input int MaxSlippagePoints = 20;

// Live remote risk settings and bounded adaptive-learning state
double lotSizeLive=0.01;
bool useRiskSizingLive=true;
int learningTrades=0;
int learningWins=0;
int learningLosses=0;
double learningNetProfit=0.0;
double adaptiveThreshold=6.0;
string diagnosticBlocker="STARTING";
double diagnosticSpreadPoints=0.0;
double diagnosticATR=0.0;
int diagnosticScore=0;
double diagnosticADX=0.0;
input bool EnableAdaptiveLearning = true;
input int LearningWindowTrades = 30;
input double AdaptiveThresholdMin = 4.0;
input double AdaptiveThresholdMax = 9.0;
input double LearningStep = 0.25;

CTrade trade;
CAccountInfo accountInfo;

int handleMA = INVALID_HANDLE;
int handleRSI = INVALID_HANDLE;
int handleADX = INVALID_HANDLE;
int handleATR = INVALID_HANDLE;
int handleMACD = INVALID_HANDLE;

datetime lastTradeTime = 0;
int tradesThisHour = 0;
int currentHour = -1;
int consecutiveLosses = 0;
double startingBalance = 0.0;
double equityPeak = 0.0;
datetime lastResetDate = 0;
bool isTradingPaused = false;
bool remoteTradingEnabled = true;
double riskPercentLive = 1.0;
int slPointsLive = 150;
int tpPointsLive = 250;
double maxDailyLossLive = 3.0;
double maxDrawdownLive = 10.0;

string LearningKey(){ return "LeonaPX_Learn_"+IntegerToString((int)ChartID()); }

void LoadLearningState(){ string k=LearningKey(); if(GlobalVariableCheck(k)) adaptiveThreshold=GlobalVariableGet(k); adaptiveThreshold=MathMax(AdaptiveThresholdMin,MathMin(AdaptiveThresholdMax,adaptiveThreshold)); }
void SaveLearningState(){ GlobalVariableSet(LearningKey(),adaptiveThreshold); }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   long magic=HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   if(magic!=123456) return;
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) return;
   double pnl=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)
             +HistoryDealGetDouble(trans.deal,DEAL_SWAP)
             +HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   if(pnl<0) consecutiveLosses++;
   else if(pnl>0) consecutiveLosses=0;
   learningTrades++;
   learningNetProfit+=pnl;
   if(pnl>0) learningWins++; else if(pnl<0) learningLosses++;
   if(EnableAdaptiveLearning && learningTrades>=LearningWindowTrades)
   {
      double winRate=(double)learningWins/(double)MathMax(learningTrades,1);
      if(winRate<0.40) adaptiveThreshold=MathMin(AdaptiveThresholdMax,adaptiveThreshold+LearningStep);
      else if(winRate>0.60) adaptiveThreshold=MathMax(AdaptiveThresholdMin,adaptiveThreshold-LearningStep);
      learningTrades=0; learningWins=0; learningLosses=0; learningNetProfit=0.0;
      SaveLearningState();
      Print("Leona Learning: adjusted entry threshold to ",DoubleToString(adaptiveThreshold,2));
   }
   Print("Leona: closed trade P/L=",DoubleToString(pnl,2)," consecutive losses=",consecutiveLosses);
}

bool CloseAllPositions(string &message)
{
   int found=0;
   int closed=0;
   int failed=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;

      long magic=PositionGetInteger(POSITION_MAGIC);
      if(magic!=123456) continue;

      found++;
      string symbol=PositionGetString(POSITION_SYMBOL);

      ResetLastError();
      bool sent=trade.PositionClose(ticket);
      uint rc=trade.ResultRetcode();

      if(sent && (rc==TRADE_RETCODE_DONE ||
                  rc==TRADE_RETCODE_DONE_PARTIAL ||
                  rc==TRADE_RETCODE_PLACED))
      {
         closed++;
         Print("Leona CLOSE EXECUTED: ticket=",ticket,
               " symbol=",symbol," retcode=",rc);
      }
      else
      {
         failed++;
         Print("Leona CLOSE REJECTED: ticket=",ticket,
               " symbol=",symbol,
               " sent=",sent,
               " retcode=",rc,
               " description=",trade.ResultRetcodeDescription(),
               " error=",GetLastError());
      }
   }

   int remaining=CountLeonaPositions();
   if(found==0)
      message="No Leona EA positions were open.";
   else if(remaining==0)
      message=StringFormat("Closed %d of %d Leona EA positions successfully.",closed,found);
   else
      message=StringFormat("Closed %d of %d positions; %d failed. %d remain open.",
                           closed,found,failed,remaining);

   return remaining==0;
}

bool BrokerAndSymbolOK()
{
   if(RequireSupportedBroker)
   {
      string company=AccountInfoString(ACCOUNT_COMPANY);
      StringToLower(company);
      bool brokerOk=false;
      string allowed=AllowedBrokers;
      StringToLower(allowed);
      string parts[];
      int count=StringSplit(allowed,',',parts);
      for(int i=0;i<count;i++)
      {
         string name=parts[i];
         StringTrimLeft(name);
         StringTrimRight(name);
         if(name!="" && StringFind(company,name)>=0)
         {
            brokerOk=true;
            break;
         }
      }
      if(!brokerOk) return false;
   }

   if(!SyntheticOnly) return true;

   string symbol=_Symbol;
   StringToLower(symbol);
   bool synthetic=
      StringFind(symbol,"vol")>=0 ||
      StringFind(symbol,"volatility")>=0;

   return synthetic;
}

bool SpreadOK()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0 || tick.bid<=0 || tick.ask<=0)
      return false;

   double spreadPrice=tick.ask-tick.bid;
   double spreadPoints=spreadPrice/point;
   diagnosticSpreadPoints=spreadPoints;

   double atr=BufferValue(handleATR,0,0);
   diagnosticATR=(atr==EMPTY_VALUE ? 0.0 : atr);

   // Optional legacy guard. Zero means disabled.
   if(MaxSpread>0 && spreadPoints>MaxSpread)
      return false;

   if(!UseSmartSpreadFilter)
      return true;

   if(atr<=0)
      return false;

   double allowedByATR=atr*(MaxSpreadATRPercent/100.0);
   double allowedByPrice=tick.bid*(MaxSpreadPricePercent/100.0);
   double allowedPrice=0.0;

   if(allowedByATR>0 && allowedByPrice>0)
      allowedPrice=MathMin(allowedByATR,allowedByPrice);
   else if(allowedByATR>0)
      allowedPrice=allowedByATR;
   else
      allowedPrice=allowedByPrice;

   bool ok=(allowedPrice>0 && spreadPrice<=allowedPrice);

   if(ShowSpreadDiagnostics)
   {
      static datetime lastLog=0;
      if(TimeCurrent()!=lastLog)
      {
         lastLog=TimeCurrent();
         PrintFormat("Leona SPREAD %s | spread=%.1f points (%.5f price) | ATR=%.5f | ATR%%=%.1f | allowed=%.5f",
                     ok ? "OK" : "BLOCKED",
                     spreadPoints,spreadPrice,atr,
                     atr>0 ? spreadPrice/atr*100.0 : 0.0,
                     allowedPrice);
      }
   }

   return ok;
}

bool TimeOK()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(StartHour<=EndHour) return t.hour>=StartHour && t.hour<=EndHour;
   return t.hour>=StartHour || t.hour<=EndHour;
}

void ResetDaily()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   datetime day=StringToTime(StringFormat("%04d.%02d.%02d",t.year,t.mon,t.day));
   if(lastResetDate!=day)
   {
      lastResetDate=day;
      startingBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      consecutiveLosses=0;
      isTradingPaused=false;
   }
}

bool RiskManagementOK()
{
   // Risk-management blocking has been intentionally disabled for the
   // aggressive scalping build. Trading is no longer stopped by daily loss,
   // drawdown, consecutive-loss, equity, margin, balance, position-count,
   // or hourly-trade risk gates.
   return true;
}
double BufferValue(int handle,int buffer,int shift)
{
   double a[];
   ArraySetAsSeries(a,true);
   if(CopyBuffer(handle,buffer,shift,1,a)!=1) return EMPTY_VALUE;
   return a[0];
}

int AIScore()
{
   double ma=BufferValue(handleMA,0,0);
   double maPrev=BufferValue(handleMA,0,1);
   double rsi=BufferValue(handleRSI,0,0);
   double rsiPrev=BufferValue(handleRSI,0,1);
   double macd=BufferValue(handleMACD,0,0);
   double signal=BufferValue(handleMACD,1,0);
   double macdPrev=BufferValue(handleMACD,0,1);
   double signalPrev=BufferValue(handleMACD,1,1);
   double adx=BufferValue(handleADX,0,0);
   double atr=BufferValue(handleATR,0,0);

   if(ma==EMPTY_VALUE || rsi==EMPTY_VALUE || macd==EMPTY_VALUE || signal==EMPTY_VALUE || adx==EMPTY_VALUE || atr==EMPTY_VALUE) return 0;

   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   int score=0;
   score += price>ma ? 2 : -2;
   score += ma>maPrev ? 1 : -1;
   score += rsi>50 && rsi>rsiPrev ? 1 : -1;
   if(macd>signal && macdPrev<=signalPrev) score+=3;
   else if(macd<signal && macdPrev>=signalPrev) score-=3;
   if(adx>25) score += price>ma ? 2 : -2;
   if(adx>40) score += price>ma ? 1 : -1;
   if(atr>100*_Point) score += price>ma ? 1 : -1;
   if(atr>150*_Point) score += price>ma ? 1 : -1;

   double o1=iOpen(_Symbol,PERIOD_M5,1),c1=iClose(_Symbol,PERIOD_M5,1);
   double o2=iOpen(_Symbol,PERIOD_M5,2),c2=iClose(_Symbol,PERIOD_M5,2);
   if(c1>o1 && c2<o2 && c1>o2 && o1<c2) score+=2;
   if(c1<o1 && c2>o2 && c1<o2 && o1>c2) score-=2;

   return score;
}

bool VolatilityOK()
{
   double atr=BufferValue(handleATR,0,0);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(atr==EMPTY_VALUE || atr<=0 || bid<=0) return false;

   // Synthetic indices can have large price-unit ATR values, so using
   // forex-style fixed points (ATR/_Point) can incorrectly block valid markets.
   if(UseAdaptiveVolatilityFilter)
   {
      double atrPercent=(atr/bid)*100.0;
      bool percentOK=(atrPercent>=MinATRPricePercent && atrPercent<=MaxATRPricePercent);
      bool absoluteOK=(atr>=MinSyntheticATRPrice && atr<=MaxSyntheticATRPrice);
      if(DebugTrading)
      {
         static datetime lastVolLog=0;
         if(TimeCurrent()!=lastVolLog)
         {
            lastVolLog=TimeCurrent();
            PrintFormat("Leona VOLATILITY %s | ATR=%.5f | ATR%%=%.4f | range=%.4f-%.4f%%",
                        (percentOK && absoluteOK) ? "OK" : "BLOCKED",
                        atr,atrPercent,MinATRPricePercent,MaxATRPricePercent);
         }
      }
      return percentOK && absoluteOK;
   }

   // Legacy fixed-point mode remains available for symbols where it is appropriate.
   double points=atr/_Point;
   return points>=MinVolatility && points<=MaxVolatility;
}

bool MultiTimeframeConfirm(bool buy)
{
   ENUM_TIMEFRAMES frames[3]={PERIOD_M5,PERIOD_M15,PERIOD_H1};
   int confirmed=0;
   for(int i=0;i<3;i++)
   {
      int h=iMA(_Symbol,frames[i],20,0,MODE_SMA,PRICE_CLOSE);
      if(h==INVALID_HANDLE) continue;
      double b[];
      ArraySetAsSeries(b,true);
      if(CopyBuffer(h,0,0,1,b)==1)
      {
         double p=iClose(_Symbol,frames[i],0);
         if((buy && p>b[0]) || (!buy && p<b[0])) confirmed++;
      }
      IndicatorRelease(h);
   }
   // Aggressive mode needs only one of M5/M15/H1 aligned;
   // standard mode keeps the stronger 2-of-3 confirmation.
   return AggressiveScalping ? confirmed>=1 : confirmed>=2;
}


bool MarginAllowsNewTrade(ENUM_ORDER_TYPE orderType,double volume,double price)
{
   // Keep only the broker's fundamental free-margin requirement.
   // The previous 300% future-margin gate prevented aggressive scaling.
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin<=0) return false;

   double required=0.0;
   if(!OrderCalcMargin(orderType,_Symbol,volume,price,required))
   {
      if(DebugTrading) Print("Leona DEBUG: OrderCalcMargin failed. Error=",GetLastError(),
                             " free margin=",DoubleToString(freeMargin,2),
                             " lot=",DoubleToString(volume,2));
      return false;
   }

   if(required<=0)
   {
      if(DebugTrading) Print("Leona DEBUG: broker returned zero required margin. Free margin=",
                             DoubleToString(freeMargin,2));
      return false;
   }

   bool ok=(required < freeMargin);
   if(!ok && DebugTrading)
      Print("Leona DEBUG: insufficient free margin. Required=",DoubleToString(required,2),
            " Free=",DoubleToString(freeMargin,2));
   return ok;
}

double CalculateLotSize(double stopDistancePrice=0.0)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0) minLot=0.01;
   if(maxLot<=0) maxLot=100.0;
   if(step<=0) step=minLot;

   if(!useRiskSizingLive)
   {
      double lot=MathMax(minLot,MathMin(maxLot,lotSizeLive));
      lot=MathFloor(lot/step)*step;
      return NormalizeDouble(MathMax(minLot,lot),2);
   }

   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney=balance*MathMax(0.01,riskPercentLive)/100.0;
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double distance=(stopDistancePrice>0 ? stopDistancePrice : slPointsLive*_Point);

   if(tickValue<=0 || tickSize<=0 || distance<=0)
      return NormalizeDouble(MathMax(minLot,MathMin(maxLot,LotSize)),2);

   double valuePerPriceUnit=tickValue/tickSize;
   double lot=riskMoney/(distance*valuePerPriceUnit);
   lot=MathMax(minLot,MathMin(maxLot,lot));
   lot=MathFloor(lot/step)*step;
   return NormalizeDouble(MathMax(minLot,lot),2);
}

void OpenBuy()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double atr=BufferValue(handleATR,0,0);
   if(atr==EMPTY_VALUE || atr<=0) return;

   double slDistance=UseATRStops ? atr*ATR_SL_Multiplier : slPointsLive*_Point;
   slDistance=MathMax(slDistance,ATR_MinSLPoints*_Point);
   slDistance=MathMin(slDistance,ATR_MaxSLPoints*_Point);

   double tpDistance=UseATRStops ? slDistance*ATR_RiskReward : tpPointsLive*_Point;
   double lot=CalculateLotSize(slDistance);
   if(DebugTrading) Print("Leona BUY PRECHECK: lot=",DoubleToString(lot,2),
                          " ask=",DoubleToString(ask,_Digits),
                          " SLdist=",DoubleToString(slDistance,_Digits),
                          " TPdist=",DoubleToString(tpDistance,_Digits));

   if(!MarginAllowsNewTrade(ORDER_TYPE_BUY,lot,ask)) { if(DebugTrading) Print("Leona DEBUG: BUY blocked by available margin."); return; }

   double sl=NormalizeDouble(ask-slDistance,_Digits);
   double tp=NormalizeDouble(ask+tpDistance,_Digits);
   bool sent=trade.Buy(lot,_Symbol,ask,sl,tp,"Leona Pro X BUY");
   uint rc=trade.ResultRetcode();
   if(sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED))
   {
      lastTradeTime=TimeCurrent(); tradesThisHour++;
      diagnosticBlocker="BUY EXECUTED";
      Print("Leona BUY EXECUTED. lot=",lot," SL=",sl," TP=",tp," retcode=",rc);
   }
   else
   {
      diagnosticBlocker="BUY REJECTED";
      Print("Leona BUY REJECTED. sent=",sent," retcode=",rc," description=",trade.ResultRetcodeDescription(),
            " lot=",lot," spread=",SymbolInfoInteger(_Symbol,SYMBOL_SPREAD));
   }
}

void OpenSell()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double atr=BufferValue(handleATR,0,0);
   if(atr==EMPTY_VALUE || atr<=0) return;

   double slDistance=UseATRStops ? atr*ATR_SL_Multiplier : slPointsLive*_Point;
   slDistance=MathMax(slDistance,ATR_MinSLPoints*_Point);
   slDistance=MathMin(slDistance,ATR_MaxSLPoints*_Point);

   double tpDistance=UseATRStops ? slDistance*ATR_RiskReward : tpPointsLive*_Point;
   double lot=CalculateLotSize(slDistance);
   if(DebugTrading) Print("Leona SELL PRECHECK: lot=",DoubleToString(lot,2),
                          " bid=",DoubleToString(bid,_Digits),
                          " SLdist=",DoubleToString(slDistance,_Digits),
                          " TPdist=",DoubleToString(tpDistance,_Digits));

   if(!MarginAllowsNewTrade(ORDER_TYPE_SELL,lot,bid)) { if(DebugTrading) Print("Leona DEBUG: SELL blocked by available margin."); return; }

   double sl=NormalizeDouble(bid+slDistance,_Digits);
   double tp=NormalizeDouble(bid-tpDistance,_Digits);
   bool sent=trade.Sell(lot,_Symbol,bid,sl,tp,"Leona Pro X SELL");
   uint rc=trade.ResultRetcode();
   if(sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED))
   {
      lastTradeTime=TimeCurrent(); tradesThisHour++;
      diagnosticBlocker="SELL EXECUTED";
      Print("Leona SELL EXECUTED. lot=",lot," SL=",sl," TP=",tp," retcode=",rc);
   }
   else
   {
      diagnosticBlocker="SELL REJECTED";
      Print("Leona SELL REJECTED. sent=",sent," retcode=",rc," description=",trade.ResultRetcodeDescription(),
            " lot=",lot," spread=",SymbolInfoInteger(_Symbol,SYMBOL_SPREAD));
   }
}

void ManagePositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=123456) continue;
      string symbol=PositionGetString(POSITION_SYMBOL);
      if(symbol!=_Symbol) continue;

      long type=PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double price=type==POSITION_TYPE_BUY?SymbolInfoDouble(symbol,SYMBOL_BID):SymbolInfoDouble(symbol,SYMBOL_ASK);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0) point=_Point;
      double profitPoints=(type==POSITION_TYPE_BUY?(price-open):(open-price))/point;

      if(UseBreakEven && profitPoints>=BreakEvenTrigger)
      {
         double newSL=NormalizeDouble(open,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
         if((type==POSITION_TYPE_BUY && (sl<newSL || sl==0)) || (type==POSITION_TYPE_SELL && (sl>newSL || sl==0)))
            trade.PositionModify(ticket,newSL,tp);
      }

      if(UseTrailingStop && profitPoints>=TrailingStart)
      {
         double newSL=type==POSITION_TYPE_BUY?price-TrailingStep*point:price+TrailingStep*point;
         newSL=NormalizeDouble(newSL,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
         if((type==POSITION_TYPE_BUY && newSL>sl) || (type==POSITION_TYPE_SELL && (newSL<sl || sl==0)))
            trade.PositionModify(ticket,newSL,tp);
      }
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(123456);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(MaxSlippagePoints);
   handleMA=iMA(_Symbol,PERIOD_M5,20,0,MODE_SMA,PRICE_CLOSE);
   handleRSI=iRSI(_Symbol,PERIOD_M5,14,PRICE_CLOSE);
   handleADX=iADX(_Symbol,PERIOD_M5,14);
   handleATR=iATR(_Symbol,PERIOD_M5,14);
   handleMACD=iMACD(_Symbol,PERIOD_M5,12,26,9,PRICE_CLOSE);

   if(handleMA==INVALID_HANDLE || handleRSI==INVALID_HANDLE || handleADX==INVALID_HANDLE || handleATR==INVALID_HANDLE || handleMACD==INVALID_HANDLE)
      return INIT_FAILED;

   startingBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   equityPeak=AccountInfoDouble(ACCOUNT_EQUITY);
   riskPercentLive=RiskPercent;
   slPointsLive=SL_Points;
   tpPointsLive=TP_Points;
   maxDailyLossLive=MaxDailyLoss;
   maxDrawdownLive=MaxDrawdown;
   remoteTradingEnabled=StartOnAttach && EA_Active;
   adaptiveThreshold=MathMax(AdaptiveThresholdMin,MathMin(AdaptiveThresholdMax,(double)AIScoreThreshold));
   LoadLearningState();
   CreateChartControls();
   diagnosticBlocker="INITIALIZED - WAITING FOR MARKET";
   UpdateChartStatus();
   Print("Leona Pro X initialized in LOCAL CONTROL mode. StartOnAttach=",StartOnAttach);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteChartControls();
   Comment("");
   IndicatorRelease(handleMA); IndicatorRelease(handleRSI); IndicatorRelease(handleADX);
   IndicatorRelease(handleATR); IndicatorRelease(handleMACD);
}

void OnTick()
{
   ManagePositions();

   diagnosticScore=0;
   diagnosticADX=0.0;

   if(!EA_Active || !remoteTradingEnabled || isTradingPaused)
   {
      diagnosticBlocker="ROBOT PAUSED";
      UpdateChartStatus();
      return;
   }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      diagnosticBlocker="MT5 AUTO TRADING DISABLED";
      if(DebugTrading) Print("Leona DEBUG: automated trading permission is disabled in terminal, EA settings, or account.");
      UpdateChartStatus();
      return;
   }


   if(!BrokerAndSymbolOK())
   {
      diagnosticBlocker="BROKER/SYMBOL FILTER";
      if(DebugTrading) Print("Leona DEBUG: blocked by broker/symbol filter. Company=",AccountInfoString(ACCOUNT_COMPANY)," Symbol=",_Symbol);
      UpdateChartStatus();
      return;
   }

   if(!SpreadOK())
   {
      diagnosticBlocker="SPREAD TOO HIGH";
      if(DebugTrading)
         PrintFormat("Leona DEBUG: blocked by smart spread. spread=%.1f points ATR=%.5f",
                     diagnosticSpreadPoints,diagnosticATR);
      UpdateChartStatus();
      return;
   }

   if(!TimeOK())
   {
      diagnosticBlocker="OUTSIDE TRADING HOURS";
      if(DebugTrading) Print("Leona DEBUG: blocked by trading hours.");
      UpdateChartStatus();
      return;
   }

   if(!RiskManagementOK())
   {
      diagnosticBlocker="RISK/MARGIN PROTECTION";
      if(DebugTrading) Print("Leona DEBUG: blocked by risk management.");
      UpdateChartStatus();
      return;
   }

   if(!VolatilityOK())
   {
      diagnosticBlocker="VOLATILITY FILTER";
      if(DebugTrading)
      {
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double atrPct=(bid>0 && diagnosticATR>0) ? (diagnosticATR/bid)*100.0 : 0.0;
         PrintFormat("Leona DEBUG: blocked by volatility. ATR=%.5f ATR%%=%.4f allowed=%.4f-%.4f%%",
                     diagnosticATR,atrPct,MinATRPricePercent,MaxATRPricePercent);
      }
      UpdateChartStatus();
      return;
   }

   if(TimeCurrent()-lastTradeTime<CooldownSeconds)
   {
      diagnosticBlocker="COOLDOWN";
      UpdateChartStatus();
      return;
   }

   double adx=BufferValue(handleADX,0,0);
   diagnosticADX=(adx==EMPTY_VALUE ? 0.0 : adx);
   // ADX is retained as an informational/AI input, but is no longer a hard
   // entry blocker for the aggressive scalping build.

   int score=AIScore();
   diagnosticScore=score;
   int threshold=(int)MathRound(EnableAdaptiveLearning ? adaptiveThreshold : (double)AIScoreThreshold);
   if(AggressiveScalping) threshold=MathMax(1,threshold-1);

   bool buyConfirm=MultiTimeframeConfirm(true);
   bool sellConfirm=MultiTimeframeConfirm(false);

   if(DebugTrading)
      Print("Leona SIGNAL CHECK: score=",score,
            " threshold=",threshold,
            " buyConfirm=",buyConfirm,
            " sellConfirm=",sellConfirm,
            " ADX=",DoubleToString(adx,2),
            " ATR=",DoubleToString(diagnosticATR,_Digits));

   if(score>=threshold && buyConfirm)
   {
      diagnosticBlocker="BUY SIGNAL - SENDING";
      if(DebugTrading) Print("Leona DEBUG: BUY signal score=",score," threshold=",threshold," ADX=",adx);
      OpenBuy();
   }
   else if(score<=-threshold && sellConfirm)
   {
      diagnosticBlocker="SELL SIGNAL - SENDING";
      if(DebugTrading) Print("Leona DEBUG: SELL signal score=",score," threshold=",threshold," ADX=",adx);
      OpenSell();
   }
   else if(score>=threshold || score<=-threshold)
   {
      diagnosticBlocker="AI SCORE OK - MTF CONFIRMATION";
   }
   else
   {
      diagnosticBlocker="WAITING FOR AI SCORE";
   }

   UpdateChartStatus();
}
