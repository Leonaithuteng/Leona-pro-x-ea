#property strict
#property version "3.5"
#property description "Leona Pro X EA v3.5 - professional M5 aggressive scalper with SMC/ICT chart intelligence"

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
input bool UseDollarTP = true;
input double MinTPProfitUSD = 1.0;
input double MaxTPProfitUSD = 100.0;
input double TPProfitUSDPerLot = 25.0;
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
input int AIScoreThreshold = 0; // Informational only: AI score is NOT an entry blocker

input group "Time & Cooldown"
input int CooldownSeconds = 0; // 0 = no software delay between signal bursts
input int MaxTradesPerHour = 0; // 0 = unlimited trades per hour
input bool TradeDuringNews = false;
input int StartHour = 0;
input int EndHour = 23;

input group "Exit Strategies"
input bool UseTrailingStop = false;
input int TrailingStart = 80;
input int TrailingStep = 20;
input bool UseBreakEven = false;
input int BreakEvenTrigger = 50;

input group "Risk Management"
input double MaxDailyLoss = 3.0;
input double MaxDrawdown = 10.0;
input bool UseEquityProtection = true;
input int MaxConsecutiveLosses = 10;

input group "Chart Controls"
input bool StartOnAttach = false; // First-trade gate: wait for START command once
input bool ShowChartControls = true; // START once; then autonomous
input bool ShowSignalDisplay = true;
input bool ShowSignalMarkers = true;

input group "SMC / ICT Chart Intelligence"
input bool ShowSMCStructure = true;
input bool ShowFVG = true;
input bool ShowOrderBlocks = true;
input bool ShowBreakerBlocks = true;
input bool ShowPremiumDiscount = true;
input bool ShowLiquidityHighsLows = true;
input bool ShowReentryZones = true;
input int SMCStructureLookback = 80;
input int SMCSwingStrength = 2;
input int SMCZoneExtendBars = 35;
input bool UseSMCForDirectionOnly = false; // SMC is visual/advisory; it never blocks an aggressive trade

input bool DebugTrading = true;
input bool AggressiveScalping = true;
input int MaxOpenPositions = 0; // 0 = no EA position cap; broker free margin/position limits decide
input int BurstOrderCap = 0; // 0 = no software burst cap; stop only when broker rejects or margin is insufficient
input int MaxBurstAttempts = 1000; // per-burst safety guard; broker/margin rejection remains the hard execution limit
input group "Profit Lot Scaling"
input bool EnableProfitLotScaling = true;
input double ProfitStepAmount = 1.0;
input double LotIncreasePerProfitStep = 0.01;
input double ProfitLotMax = 100.0;
input double MinimumAccountBalance = 2.0;
input int MinimumProfitScalePositions = 5;
input double ProfitRequiredToScale = 0.01;
input double MinimumMarginLevelToAdd = 300.0;
input double MinMarginLevel = 300.0;
input double MaxLotPercentOfBalance = 5.0;
input double BalancePerOpenTrade = 100.0;
input int MaxSlippagePoints = 20;
input group "Fast Execution Engine"
input bool UseFastMomentumBias = true;
input int FastEMAPeriod = 5;
input int FastRSIPeriod = 7;
input int MomentumLookbackBars = 3;
input double MomentumMinPercent = 0.0; // 0 = directional bias only, never a blocker
input bool RecalculateDirectionBeforeEachBurst = true;
input bool EnableMarketFilters = false; // false = no EA-imposed spread/time/volatility entry filters

// Live remote risk settings and bounded adaptive-learning state
double lotSizeLive=0.01;
bool useRiskSizingLive=true;
int learningTrades=0;
int learningWins=0;
int learningLosses=0;
double learningNetProfit=0.0;
string lastDisplayedSignal="WAITING";
datetime lastSignalBar=0;
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
int handleFastEMA = INVALID_HANDLE;
int handleFastRSI = INVALID_HANDLE;

datetime lastTradeTime = 0;
int tradesThisHour = 0;
int currentHour = -1;
int consecutiveLosses = 0;
double startingBalance = 0.0;
double equityPeak = 0.0;
datetime lastResetDate = 0;
bool isTradingPaused = false;
bool remoteTradingEnabled = false;
double riskPercentLive = 1.0;
int slPointsLive = 150;
int tpPointsLive = 250;
double maxDailyLossLive = 3.0;
double maxDrawdownLive = 10.0;

const string BTN_START="LEONA_BTN_START";
const string BTN_STOP="LEONA_BTN_STOP";
const string BTN_CLOSE="LEONA_BTN_CLOSE";
const string SIGNAL_LABEL="LEONA_SIGNAL_LABEL";

const string SMC_PREFIX="LEONA_SMC_";
datetime lastSMCBar=0;
string smcStructureState="NEUTRAL";
string smcZoneState="NONE";
double smcRangeHigh=0.0;
double smcRangeLow=0.0;
double smcPremium=0.0;
double smcDiscount=0.0;

void CreateControlButton(const string name,const string text,const int x,const int y,const color bg)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ResetLastError();
   if(!ObjectCreate(0,name,OBJ_BUTTON,0,0,0))
   {
      Print("Leona: failed to create chart button ",name," error=",GetLastError());
      return;
   }
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,125);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,34);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,11);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,100);
}

void CreateSignalDisplay()
{
   if(!ShowSignalDisplay) return;
   if(ObjectFind(0,SIGNAL_LABEL)>=0) ObjectDelete(0,SIGNAL_LABEL);
   if(!ObjectCreate(0,SIGNAL_LABEL,OBJ_LABEL,0,0,0))
   {
      Print("Leona: failed to create signal label error=",GetLastError());
      return;
   }
   ObjectSetInteger(0,SIGNAL_LABEL,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,SIGNAL_LABEL,OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,SIGNAL_LABEL,OBJPROP_YDISTANCE,25);
   ObjectSetString(0,SIGNAL_LABEL,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,SIGNAL_LABEL,OBJPROP_FONTSIZE,18);
   ObjectSetInteger(0,SIGNAL_LABEL,OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,SIGNAL_LABEL,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,SIGNAL_LABEL,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,SIGNAL_LABEL,OBJPROP_ZORDER,100);
   ObjectSetString(0,SIGNAL_LABEL,OBJPROP_TEXT,"SIGNAL: WAITING");
}

void UpdateSignalDisplay(const string signal,const int score)
{
   if(!ShowSignalDisplay || ObjectFind(0,SIGNAL_LABEL)<0) return;
   string text="SIGNAL: "+signal+" | SCORE: "+IntegerToString(score);
   color clr=clrSilver;
   if(signal=="BUY") clr=clrLime;
   else if(signal=="SELL") clr=clrRed;
   else if(signal=="PAUSED") clr=clrOrange;
   ObjectSetString(0,SIGNAL_LABEL,OBJPROP_TEXT,text);
   ObjectSetInteger(0,SIGNAL_LABEL,OBJPROP_COLOR,clr);
}

void DrawSignalMarker(const string signal,const datetime barTime,const double price)
{
   if(!ShowSignalMarkers || signal=="WAITING") return;
   if(barTime==lastSignalBar && signal==lastDisplayedSignal) return;
   string name="LEONA_SIGNAL_"+IntegerToString((int)barTime)+"_"+signal;
   if(ObjectFind(0,name)>=0) return;
   ENUM_OBJECT type=(signal=="BUY") ? OBJ_ARROW_BUY : OBJ_ARROW_SELL;
   if(!ObjectCreate(0,name,type,0,barTime,price)) return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,(signal=="BUY") ? clrLime : clrRed);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   lastSignalBar=barTime;
   lastDisplayedSignal=signal;
}

void CreateChartControls()
{
   if(!ShowChartControls) return;
   CreateControlButton(BTN_START,"START TRADING",10,25,clrGreen);
   CreateControlButton(BTN_STOP,"STOP EA",145,25,clrOrangeRed);
   CreateControlButton(BTN_CLOSE,"CLOSE ALL",280,25,clrRed);
   ChartRedraw();
}

void DeleteChartControls()
{
   ObjectDelete(0,BTN_START);
   ObjectDelete(0,BTN_STOP);
   ObjectDelete(0,BTN_CLOSE);
   ObjectDelete(0,SIGNAL_LABEL);
}

void UpdateControlButtons()
{
   if(!ShowChartControls) return;
   bool active=EA_Active && remoteTradingEnabled && !isTradingPaused;
   if(ObjectFind(0,BTN_START)>=0)
      ObjectSetString(0,BTN_START,OBJPROP_TEXT,active ? "TRADING ON" : "START TRADING");
   if(ObjectFind(0,BTN_STOP)>=0)
      ObjectSetString(0,BTN_STOP,OBJPROP_TEXT,active ? "STOP EA" : "EA STOPPED");
   if(ObjectFind(0,BTN_CLOSE)>=0)
      ObjectSetString(0,BTN_CLOSE,OBJPROP_TEXT,"CLOSE ALL");
}

void OnChartEvent(const int id,const long& lparam,const double& dparam,const string& sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK) return;

   if(sparam==BTN_START)
   {
      remoteTradingEnabled=true;
      isTradingPaused=false;
      diagnosticBlocker="STARTED FROM CHART";
      UpdateSignalDisplay("WAITING",diagnosticScore);
      Print("Leona: EA STARTED from chart.");
   }
   else if(sparam==BTN_STOP)
   {
      remoteTradingEnabled=false;
      diagnosticBlocker="STOPPED FROM CHART";
      UpdateSignalDisplay("PAUSED",diagnosticScore);
      Print("Leona: EA STOPPED from chart. Existing positions remain managed.");
   }
   else if(sparam==BTN_CLOSE)
   {
      string msg="";
      bool ok=CloseAllPositions(msg);
      diagnosticBlocker=ok ? "ALL POSITIONS CLOSED" : "CLOSE ALL - CHECK JOURNAL";
      Print("Leona: ",msg);
   }

   UpdateControlButtons();
   UpdateChartStatus();
   ChartRedraw();
}

string LearningKey(){ return "LeonaPX_Learn_"+IntegerToString((int)ChartID()); }

void LoadLearningState(){ string k=LearningKey(); if(GlobalVariableCheck(k)) adaptiveThreshold=GlobalVariableGet(k); adaptiveThreshold=MathMax(AdaptiveThresholdMin,MathMin(AdaptiveThresholdMax,adaptiveThreshold)); }
void SaveLearningState(){ GlobalVariableSet(LearningKey(),adaptiveThreshold); }

int CountLeonaPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetInteger(POSITION_MAGIC)==123456)
         count++;
   }
   return count;
}

void UpdateChartStatus()
{
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   string company=AccountInfoString(ACCOUNT_COMPANY);
   string runState=(!EA_Active || !remoteTradingEnabled || isTradingPaused) ? "PAUSED" : "ACTIVE";
   UpdateControlButtons();
   int threshold=(int)MathRound(EnableAdaptiveLearning ? adaptiveThreshold : (double)AIScoreThreshold);
   if(AggressiveScalping) threshold=MathMax(1,threshold-1);

   Comment(
      "LEONA PRO X EA LIVE v3.3 M5 AUTONOMOUS\n",
      "MODE: ",AggressiveScalping ? "AGGRESSIVE SCALPER" : "STANDARD SCALPER","\n",
      "STATUS: ",runState,"\n",
      "BROKER: ",company,"\n",
      "SYMBOL: ",_Symbol," | M5\n",
      "CONTROL: FULLY AUTONOMOUS | M5 EXECUTION\n",
      "AI SCORE: ",diagnosticScore," | THRESHOLD: ",threshold," | ADX: ",DoubleToString(diagnosticADX,1),"\n",
      "POSITIONS: ",CountLeonaPositions(),"/",MaxOpenPositions," | MARGIN LEVEL: ",DoubleToString(marginLevel,1),"%\n",
      "SPREAD: ",DoubleToString(diagnosticSpreadPoints,1)," pts | ATR: ",DoubleToString(diagnosticATR,_Digits),"\n",
      "BALANCE: ",DoubleToString(balance,2)," | EQUITY: ",DoubleToString(equity,2),"\n",
      "LOT: ",DoubleToString(CalculateLotSize(),2)," | PROFIT SCALE: ",DoubleToString(MathMax(0.0,balance-startingBalance),2),"\n",
      "SMC: ",smcStructureState," | ZONE: ",smcZoneState,"\n",
      "BLOCKER: ",diagnosticBlocker
   );
}

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


void DeleteSMCObjects()
{
   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,SMC_PREFIX)==0) ObjectDelete(0,name);
   }
}

void DrawSMCText(const string name,const datetime t,const double price,const string text,const color clr)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   if(!ObjectCreate(0,name,OBJ_TEXT,0,t,price)) return;
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_CENTER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}

void DrawSMCZone(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,const string label)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2)) return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   DrawSMCText(name+"_TXT",t2,p2,label,clr);
}

bool IsSwingHigh(const int shift,const int strength)
{
   double h=iHigh(_Symbol,PERIOD_M5,shift);
   if(h<=0) return false;
   for(int k=1;k<=strength;k++)
   {
      if(iHigh(_Symbol,PERIOD_M5,shift-k)>=h || iHigh(_Symbol,PERIOD_M5,shift+k)>=h) return false;
   }
   return true;
}

bool IsSwingLow(const int shift,const int strength)
{
   double l=iLow(_Symbol,PERIOD_M5,shift);
   if(l<=0) return false;
   for(int k=1;k<=strength;k++)
   {
      if(iLow(_Symbol,PERIOD_M5,shift-k)<=l || iLow(_Symbol,PERIOD_M5,shift+k)<=l) return false;
   }
   return true;
}

void DrawPremiumDiscount(const datetime newest,const datetime oldest)
{
   if(!ShowPremiumDiscount || smcRangeHigh<=smcRangeLow) return;
   double eq=(smcRangeHigh+smcRangeLow)/2.0;
   smcPremium=(smcRangeHigh+eq)/2.0;
   smcDiscount=(smcRangeLow+eq)/2.0;

   DrawSMCZone(SMC_PREFIX+"PREMIUM",oldest,eq,newest,smcRangeHigh,clrTomato,"PREMIUM");
   DrawSMCZone(SMC_PREFIX+"DISCOUNT",oldest,smcRangeLow,newest,eq,clrDeepSkyBlue,"DISCOUNT");
   DrawSMCText(SMC_PREFIX+"EQ",newest,eq,"EQUILIBRIUM",clrGold);
}

void AnalyzeSMC()
{
   if(!ShowSMCStructure && !ShowFVG && !ShowOrderBlocks && !ShowBreakerBlocks && !ShowPremiumDiscount && !ShowLiquidityHighsLows && !ShowReentryZones)
      return;

   datetime bar=iTime(_Symbol,PERIOD_M5,1);
   if(bar<=0 || bar==lastSMCBar) return;
   lastSMCBar=bar;

   DeleteSMCObjects();

   int bars=MathMin(SMCStructureLookback,Bars(_Symbol,PERIOD_M5));
   if(bars<20) return;

   int hi1=-1,hi2=-1,lo1=-1,lo2=-1;
   double high1=0,high2=0,low1=0,low2=0;
   int strength=MathMax(1,SMCSwingStrength);

   for(int shift=strength+1;shift<bars-strength;shift++)
   {
      if(hi1<0 && IsSwingHigh(shift,strength))
      {
         hi1=shift; high1=iHigh(_Symbol,PERIOD_M5,shift);
      }
      else if(hi2<0 && IsSwingHigh(shift,strength))
      {
         hi2=shift; high2=iHigh(_Symbol,PERIOD_M5,shift);
      }

      if(lo1<0 && IsSwingLow(shift,strength))
      {
         lo1=shift; low1=iLow(_Symbol,PERIOD_M5,shift);
      }
      else if(lo2<0 && IsSwingLow(shift,strength))
      {
         lo2=shift; low2=iLow(_Symbol,PERIOD_M5,shift);
      }

      if(hi2>=0 && lo2>=0) break;
   }

   if(hi1<0 || hi2<0 || lo1<0 || lo2<0) return;

   smcRangeHigh=MathMax(high1,high2);
   smcRangeLow=MathMin(low1,low2);
   datetime newest=iTime(_Symbol,PERIOD_M5,1);
   datetime oldest=iTime(_Symbol,PERIOD_M5,MathMin(bars-1,SMCStructureLookback-1));

   if(ShowPremiumDiscount) DrawPremiumDiscount(newest,oldest);

   if(ShowLiquidityHighsLows)
   {
      DrawSMCText(SMC_PREFIX+"HIGH_1",iTime(_Symbol,PERIOD_M5,hi1),high1,"HIGH",clrRed);
      DrawSMCText(SMC_PREFIX+"HIGH_2",iTime(_Symbol,PERIOD_M5,hi2),high2,"HIGH",clrRed);
      DrawSMCText(SMC_PREFIX+"LOW_1",iTime(_Symbol,PERIOD_M5,lo1),low1,"LOW",clrLime);
      DrawSMCText(SMC_PREFIX+"LOW_2",iTime(_Symbol,PERIOD_M5,lo2),low2,"LOW",clrLime);
   }

   // BOS / CHOCH / market-structure shift from the most recently closed M5 candle.
   double close1=iClose(_Symbol,PERIOD_M5,1);
   bool bullishBreak=(close1>high1);
   bool bearishBreak=(close1<low1);

   bool higherHigh=(high1>high2);
   bool higherLow=(low1>low2);
   bool lowerHigh=(high1<high2);
   bool lowerLow=(low1<low2);

   if(bullishBreak)
   {
      smcStructureState=(lowerHigh || lowerLow) ? "CHOCH / MSS BULLISH" : "BOS BULLISH";
      if(ShowSMCStructure)
      {
         DrawSMCText(SMC_PREFIX+"STRUCTURE",newest,high1,smcStructureState,clrLime);
         DrawSMCZone(SMC_PREFIX+"BOS",iTime(_Symbol,PERIOD_M5,hi1),high1,newest,high1,clrLime,"BOS");
      }
   }
   else if(bearishBreak)
   {
      smcStructureState=(higherHigh || higherLow) ? "CHOCH / MSS BEARISH" : "BOS BEARISH";
      if(ShowSMCStructure)
      {
         DrawSMCText(SMC_PREFIX+"STRUCTURE",newest,low1,smcStructureState,clrTomato);
         DrawSMCZone(SMC_PREFIX+"BOS",iTime(_Symbol,PERIOD_M5,lo1),low1,newest,low1,clrTomato,"BOS");
      }
   }
   else
   {
      if(higherHigh && higherLow) smcStructureState="BULLISH STRUCTURE";
      else if(lowerHigh && lowerLow) smcStructureState="BEARISH STRUCTURE";
      else smcStructureState="MARKET STRUCTURE SHIFT WATCH";
      if(ShowSMCStructure)
         DrawSMCText(SMC_PREFIX+"STRUCTURE",newest,(smcRangeHigh+smcRangeLow)/2.0,smcStructureState,clrGold);
   }

   // Most recent closed-bar Fair Value Gap.
   if(ShowFVG)
   {
      for(int shift=1;shift<MathMin(45,bars-3);shift++)
      {
         double olderHigh=iHigh(_Symbol,PERIOD_M5,shift+2);
         double olderLow=iLow(_Symbol,PERIOD_M5,shift+2);
         double newerHigh=iHigh(_Symbol,PERIOD_M5,shift);
         double newerLow=iLow(_Symbol,PERIOD_M5,shift);
         if(olderHigh<newerLow)
         {
            datetime t1=iTime(_Symbol,PERIOD_M5,shift+2);
            datetime t2=iTime(_Symbol,PERIOD_M5,MathMax(1,shift-SMCZoneExtendBars));
            DrawSMCZone(SMC_PREFIX+"FVG_BULL",t1,olderHigh,t2,newerLow,clrAqua,"BULL FVG");
            break;
         }
         if(olderLow>newerHigh)
         {
            datetime t1=iTime(_Symbol,PERIOD_M5,shift+2);
            datetime t2=iTime(_Symbol,PERIOD_M5,MathMax(1,shift-SMCZoneExtendBars));
            DrawSMCZone(SMC_PREFIX+"FVG_BEAR",t1,olderLow,t2,newerHigh,clrOrange,"BEAR FVG");
            break;
         }
      }
   }

   // Order block + breaker approximation: last opposite candle before displacement,
   // then flag it as a breaker when price subsequently closes through that zone.
   if(ShowOrderBlocks || ShowBreakerBlocks)
   {
      for(int shift=2;shift<MathMin(35,bars-2);shift++)
      {
         double o=iOpen(_Symbol,PERIOD_M5,shift);
         double c=iClose(_Symbol,PERIOD_M5,shift);
         double h=iHigh(_Symbol,PERIOD_M5,shift);
         double l=iLow(_Symbol,PERIOD_M5,shift);
         double nextC=iClose(_Symbol,PERIOD_M5,shift-1);

         bool bearishCandle=(c<o);
         bool bullishCandle=(c>o);
         bool bullishDisplacement=(nextC>h);
         bool bearishDisplacement=(nextC<l);

         if(bearishCandle && bullishDisplacement)
         {
            datetime t1=iTime(_Symbol,PERIOD_M5,shift);
            datetime t2=iTime(_Symbol,PERIOD_M5,MathMax(1,shift-SMCZoneExtendBars));
            bool broken=(close1<l);
            if(broken && ShowBreakerBlocks) DrawSMCZone(SMC_PREFIX+"BREAKER_BULL",t1,l,t2,h,clrMagenta,"BULL BREAKER");
            else if(ShowOrderBlocks) DrawSMCZone(SMC_PREFIX+"OB_BULL",t1,l,t2,h,clrDodgerBlue,"BULL OB");
            break;
         }

         if(bullishCandle && bearishDisplacement)
         {
            datetime t1=iTime(_Symbol,PERIOD_M5,shift);
            datetime t2=iTime(_Symbol,PERIOD_M5,MathMax(1,shift-SMCZoneExtendBars));
            bool broken=(close1>h);
            if(broken && ShowBreakerBlocks) DrawSMCZone(SMC_PREFIX+"BREAKER_BEAR",t1,l,t2,h,clrMagenta,"BEAR BREAKER");
            else if(ShowOrderBlocks) DrawSMCZone(SMC_PREFIX+"OB_BEAR",t1,l,t2,h,clrOrangeRed,"BEAR OB");
            break;
         }
      }
   }

   // Re-entry watch: show when price is back inside the current dealing range
   // around equilibrium after a structure impulse.
   if(ShowReentryZones)
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double eq=(smcRangeHigh+smcRangeLow)/2.0;
      double range=smcRangeHigh-smcRangeLow;
      if(range>0.0)
      {
         double tolerance=range*0.12;
         if(MathAbs(bid-eq)<=tolerance)
         {
            smcZoneState="POSSIBLE RE-ENTRY";
            DrawSMCText(SMC_PREFIX+"REENTRY",newest,bid,"POSSIBLE RE-ENTRY",clrYellow);
         }
         else if(bid>=smcDiscount && bid<=eq)
         {
            smcZoneState="DISCOUNT RE-ENTRY WATCH";
            DrawSMCText(SMC_PREFIX+"REENTRY",newest,bid,"RE-ENTRY: DISCOUNT",clrAqua);
         }
         else if(bid<=smcPremium && bid>=eq)
         {
            smcZoneState="PREMIUM RE-ENTRY WATCH";
            DrawSMCText(SMC_PREFIX+"REENTRY",newest,bid,"RE-ENTRY: PREMIUM",clrOrange);
         }
         else smcZoneState="NONE";
      }
   }
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
   string company=AccountInfoString(ACCOUNT_COMPANY);
   StringToLower(company);

   // Autonomous synthetic-only operation; no broker/API selection is needed.
   bool brokerOk=(StringFind(company,"weltrade")>=0 || StringFind(company,"deriv")>=0);
   if(!brokerOk) return false;

   string symbol=_Symbol;
   StringToLower(symbol);
   return StringFind(symbol,"vol")>=0 || StringFind(symbol,"volatility")>=0;
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

   if(ma==EMPTY_VALUE || rsi==EMPTY_VALUE || macd==EMPTY_VALUE || signal==EMPTY_VALUE || adx==EMPTY_VALUE || atr==EMPTY_VALUE)
      return 0;

   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   int score=0;

   // Core directional structure.
   score += price>ma ? 2 : -2;
   score += ma>maPrev ? 1 : -1;
   score += rsi>50 && rsi>rsiPrev ? 1 : -1;

   if(macd>signal && macdPrev<=signalPrev) score+=3;
   else if(macd<signal && macdPrev>=signalPrev) score-=3;
   else if(macd>signal) score+=1;
   else if(macd<signal) score-=1;

   // ADX is directional information only; it never blocks an entry.
   if(adx>25) score += price>ma ? 2 : -2;
   if(adx>40) score += price>ma ? 1 : -1;

   // Fast M1 momentum layer for earlier scalping entries.
   if(UseFastMomentumBias && handleFastEMA!=INVALID_HANDLE)
   {
      double ema=BufferValue(handleFastEMA,0,0);
      double emaPrev=BufferValue(handleFastEMA,0,1);
      double fastRsi=BufferValue(handleFastRSI,0,0);
      double fastRsiPrev=BufferValue(handleFastRSI,0,1);

      if(ema!=EMPTY_VALUE)
         score += price>ema ? 2 : -2;
      if(ema!=EMPTY_VALUE && emaPrev!=EMPTY_VALUE)
         score += ema>emaPrev ? 2 : -2;
      if(fastRsi!=EMPTY_VALUE && fastRsiPrev!=EMPTY_VALUE)
      {
         if(fastRsi>52 && fastRsi>fastRsiPrev) score+=2;
         else if(fastRsi<48 && fastRsi<fastRsiPrev) score-=2;
      }

      int bars=MathMax(1,MomentumLookbackBars);
      double oldClose=iClose(_Symbol,PERIOD_M5,bars);
      if(oldClose>0 && price>0)
      {
         double momentumPct=((price-oldClose)/oldClose)*100.0;
         if(momentumPct>MomentumMinPercent) score+=2;
         else if(momentumPct<(-MomentumMinPercent)) score-=2;
      }
   }

   // Recent candle structure.
   double o1=iOpen(_Symbol,PERIOD_M5,1),c1=iClose(_Symbol,PERIOD_M5,1);
   double o2=iOpen(_Symbol,PERIOD_M5,2),c2=iClose(_Symbol,PERIOD_M5,2);
   if(c1>o1 && c2<o2 && c1>o2 && o1<c2) score+=2;
   if(c1<o1 && c2>o2 && c1<o2 && o1>c2) score-=2;

   // ATR contributes directionally but is never a gate.
   if(atr>0)
      score += price>ma ? 1 : -1;

   return score;
}

bool FastDirection(bool &buy,bool &sell)
{
   buy=false;
   sell=false;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(bid<=0) return false;

   double fastEMA=BufferValue(handleFastEMA,0,0);
   double fastPrev=BufferValue(handleFastEMA,0,1);
   double fastRSI=BufferValue(handleFastRSI,0,0);
   double fastRSIPrev=BufferValue(handleFastRSI,0,1);

   if(fastEMA==EMPTY_VALUE || fastPrev==EMPTY_VALUE || fastRSI==EMPTY_VALUE || fastRSIPrev==EMPTY_VALUE)
      return false;

   double prevClose=iClose(_Symbol,PERIOD_M5,1);
   double oldClose=iClose(_Symbol,PERIOD_M5,MathMax(2,MomentumLookbackBars));

   double momentumPct=0.0;
   if(oldClose>0.0) momentumPct=((bid-oldClose)/oldClose)*100.0;

   int bias=0;
   if(bid>fastEMA) bias++;
   else if(bid<fastEMA) bias--;

   if(fastEMA>fastPrev) bias++;
   else if(fastEMA<fastPrev) bias--;

   if(fastRSI>52 && fastRSI>fastRSIPrev) bias+=2;
   else if(fastRSI<48 && fastRSI<fastRSIPrev) bias-=2;

   if(prevClose>0.0)
   {
      if(bid>prevClose) bias++;
      else if(bid<prevClose) bias--;
   }

   if(momentumPct>MomentumMinPercent) bias++;
   else if(momentumPct<(-MomentumMinPercent)) bias--;

   if(bias>0) buy=true;
   else if(bias<0) sell=true;
   return true;
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
   ENUM_TIMEFRAMES frames[3]={PERIOD_M5,PERIOD_M55,PERIOD_H1};
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

   double baseLot=0.0;
   if(!useRiskSizingLive)
   {
      baseLot=lotSizeLive;
   }
   else
   {
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      double riskMoney=balance*MathMax(0.01,riskPercentLive)/100.0;
      double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double distance=(stopDistancePrice>0 ? stopDistancePrice : slPointsLive*_Point);

      if(tickValue>0 && tickSize>0 && distance>0)
      {
         double valuePerPriceUnit=tickValue/tickSize;
         baseLot=riskMoney/(distance*valuePerPriceUnit);
      }
      else
         baseLot=LotSize;
   }

   if(baseLot<=0) baseLot=LotSize;

   // Explicit profit-based scaling: realized account profit increases the
   // next trade's lot size in fixed increments. Losses never increase it.
   double profit=AccountInfoDouble(ACCOUNT_BALANCE)-startingBalance;
   double scaleLot=0.0;
   if(EnableProfitLotScaling && ProfitStepAmount>0.0 && LotIncreasePerProfitStep>0.0 && profit>0.0)
   {
      int steps=(int)MathFloor(profit/ProfitStepAmount);
      scaleLot=steps*LotIncreasePerProfitStep;
   }

   double lot=baseLot+scaleLot;
   lot=MathMin(lot,ProfitLotMax);
   lot=MathMax(minLot,MathMin(maxLot,lot));
   lot=MathFloor(lot/step)*step;
   return NormalizeDouble(MathMax(minLot,lot),2);
}

double CalculateTPDistanceForProfit(double lot)
{
   double targetUSD=lot*TPProfitUSDPerLot;
   targetUSD=MathMax(MinTPProfitUSD,MathMin(MaxTPProfitUSD,targetUSD));
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0.0 || tickSize<=0.0 || lot<=0.0) return 0.0;
   double valuePerPriceUnit=tickValue/tickSize;
   double distance=targetUSD/(valuePerPriceUnit*lot);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double minStops=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   if(point>0.0 && distance<minStops) distance=minStops;
   return distance;
}

bool OpenBuy()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double atr=BufferValue(handleATR,0,0);
   if(atr==EMPTY_VALUE || atr<=0) return false;

   double slDistance=UseATRStops ? atr*ATR_SL_Multiplier : slPointsLive*_Point;
   slDistance=MathMax(slDistance,ATR_MinSLPoints*_Point);
   slDistance=MathMin(slDistance,ATR_MaxSLPoints*_Point);

   double lot=CalculateLotSize(slDistance);
   double tpDistance=UseDollarTP ? CalculateTPDistanceForProfit(lot) : (UseATRStops ? slDistance*ATR_RiskReward : tpPointsLive*_Point);
   if(tpDistance<=0.0) return false;
   if(DebugTrading) Print("Leona BUY PRECHECK: lot=",DoubleToString(lot,2),
                          " ask=",DoubleToString(ask,_Digits),
                          " SLdist=",DoubleToString(slDistance,_Digits),
                          " TPdist=",DoubleToString(tpDistance,_Digits));

   if(!MarginAllowsNewTrade(ORDER_TYPE_BUY,lot,ask))
   {
      if(DebugTrading) Print("Leona DEBUG: BUY burst stopped by available margin.");
      return false;
   }

   double sl=NormalizeDouble(ask-slDistance,_Digits);
   double tp=NormalizeDouble(ask+tpDistance,_Digits);
   bool sent=trade.Buy(lot,_Symbol,ask,sl,tp,"Leona Pro X BUY");
   uint rc=trade.ResultRetcode();

   if(sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED))
   {
      lastTradeTime=TimeCurrent();
      tradesThisHour++;
      diagnosticBlocker="BUY EXECUTED";
      Print("Leona BUY EXECUTED. lot=",lot," SL=",sl," TP=",tp," retcode=",rc);
      return true;
   }

   diagnosticBlocker="BUY REJECTED";
   Print("Leona BUY REJECTED. sent=",sent," retcode=",rc," description=",trade.ResultRetcodeDescription(),
         " lot=",lot," spread=",SymbolInfoInteger(_Symbol,SYMBOL_SPREAD));
   return false;
}

bool OpenSell()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double atr=BufferValue(handleATR,0,0);
   if(atr==EMPTY_VALUE || atr<=0) return false;

   double slDistance=UseATRStops ? atr*ATR_SL_Multiplier : slPointsLive*_Point;
   slDistance=MathMax(slDistance,ATR_MinSLPoints*_Point);
   slDistance=MathMin(slDistance,ATR_MaxSLPoints*_Point);

   double lot=CalculateLotSize(slDistance);
   double tpDistance=UseDollarTP ? CalculateTPDistanceForProfit(lot) : (UseATRStops ? slDistance*ATR_RiskReward : tpPointsLive*_Point);
   if(DebugTrading) Print("Leona SELL PRECHECK: lot=",DoubleToString(lot,2),
                          " bid=",DoubleToString(bid,_Digits),
                          " SLdist=",DoubleToString(slDistance,_Digits),
                          " TPdist=",DoubleToString(tpDistance,_Digits));

   if(!MarginAllowsNewTrade(ORDER_TYPE_SELL,lot,bid))
   {
      if(DebugTrading) Print("Leona DEBUG: SELL burst stopped by available margin.");
      return false;
   }

   double sl=NormalizeDouble(bid+slDistance,_Digits);
   double tp=NormalizeDouble(bid-tpDistance,_Digits);
   bool sent=trade.Sell(lot,_Symbol,bid,sl,tp,"Leona Pro X SELL");
   uint rc=trade.ResultRetcode();

   if(sent && (rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED))
   {
      lastTradeTime=TimeCurrent();
      tradesThisHour++;
      diagnosticBlocker="SELL EXECUTED";
      Print("Leona SELL EXECUTED. lot=",lot," SL=",sl," TP=",tp," retcode=",rc);
      return true;
   }

   diagnosticBlocker="SELL REJECTED";
   Print("Leona SELL REJECTED. sent=",sent," retcode=",rc," description=",trade.ResultRetcodeDescription(),
         " lot=",lot," spread=",SymbolInfoInteger(_Symbol,SYMBOL_SPREAD));
   return false;
}

int OpenBuyBurst()
{
   int opened=0;
   int attempts=0;
   while(attempts<MathMax(1,MaxBurstAttempts))
   {
      if(BurstOrderCap>0 && opened>=BurstOrderCap) break;
      if(MaxOpenPositions>0 && CountLeonaPositions()>=MaxOpenPositions) break;

      attempts++;
      if(!OpenBuy()) break;
      opened++;
      // Re-read market price and free margin for the next order.
      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE)<=0.0) break;
   }

   if(opened>0)
      Print("Leona BUY BURST COMPLETE: opened=",opened,
            " attempts=",attempts,
            " total EA positions=",CountLeonaPositions());

   return opened;
}

int OpenSellBurst()
{
   int opened=0;
   int attempts=0;
   while(attempts<MathMax(1,MaxBurstAttempts))
   {
      if(BurstOrderCap>0 && opened>=BurstOrderCap) break;
      if(MaxOpenPositions>0 && CountLeonaPositions()>=MaxOpenPositions) break;

      attempts++;
      if(!OpenSell()) break;
      opened++;
      // Re-read market price and free margin for the next order.
      if(AccountInfoDouble(ACCOUNT_MARGIN_FREE)<=0.0) break;
   }

   if(opened>0)
      Print("Leona SELL BURST COMPLETE: opened=",opened,
            " attempts=",attempts,
            " total EA positions=",CountLeonaPositions());

   return opened;
}

void ManagePositions()
{
   // Fixed initial SL/TP only. Trailing stop and break-even are disabled.
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
   handleFastEMA=iMA(_Symbol,PERIOD_M5,FastEMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   handleFastRSI=iRSI(_Symbol,PERIOD_M5,FastRSIPeriod,PRICE_CLOSE);

   if(handleMA==INVALID_HANDLE || handleRSI==INVALID_HANDLE || handleADX==INVALID_HANDLE || handleATR==INVALID_HANDLE || handleMACD==INVALID_HANDLE || handleFastEMA==INVALID_HANDLE || handleFastRSI==INVALID_HANDLE)
      return INIT_FAILED;

   startingBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   equityPeak=AccountInfoDouble(ACCOUNT_EQUITY);
   riskPercentLive=RiskPercent;
   slPointsLive=SL_Points;
   tpPointsLive=TP_Points;
   maxDailyLossLive=MaxDailyLoss;
   maxDrawdownLive=MaxDrawdown;
   remoteTradingEnabled=false;
   adaptiveThreshold=MathMax(AdaptiveThresholdMin,MathMin(AdaptiveThresholdMax,(double)AIScoreThreshold));
   LoadLearningState();
   EventSetTimer(1);
   diagnosticBlocker="INITIALIZED - WAITING FOR MARKET";
   CreateChartControls();
   CreateSignalDisplay();
   UpdateChartStatus();
   Print("Leona Pro X initialized in FULLY AUTONOMOUS M5 mode. No API, device ID, token, or mobile control required.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteChartControls();
   Comment("");
   EventKillTimer();
   IndicatorRelease(handleMA); IndicatorRelease(handleRSI); IndicatorRelease(handleADX);
   IndicatorRelease(handleATR); IndicatorRelease(handleMACD); IndicatorRelease(handleFastEMA); IndicatorRelease(handleFastRSI);
}

void OnTimer()
{
   UpdateChartStatus();
}

void OnTick()
{
   ManagePositions();
   AnalyzeSMC();

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

   if(EnableMarketFilters && !SpreadOK())
   {
      diagnosticBlocker="SPREAD TOO HIGH";
      if(DebugTrading)
         PrintFormat("Leona DEBUG: blocked by smart spread. spread=%.1f points ATR=%.5f",
                     diagnosticSpreadPoints,diagnosticATR);
      UpdateChartStatus();
      return;
   }

   if(EnableMarketFilters && !TimeOK())
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

   if(EnableMarketFilters && !VolatilityOK())
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

   // Cooldown applies between signal evaluations, not between individual burst orders.
   if(TimeCurrent()-lastTradeTime<CooldownSeconds && CountLeonaPositions()>0)
   {
      diagnosticBlocker="BURST COOLDOWN";
      UpdateChartStatus();
      return;
   }

   double adx=BufferValue(handleADX,0,0);
   diagnosticADX=(adx==EMPTY_VALUE ? 0.0 : adx);

   // HYPERACTIVE MODE: AI score is informational, never an entry blocker.
   // Direction is selected from current M5 momentum/MA bias. MTF confirmation
   // is advisory only; it cannot prevent a trade.
   int score=AIScore();
   diagnosticScore=score;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ma=BufferValue(handleMA,0,0);
   bool buySignal=(score>0);
   bool sellSignal=(score<0);

   // Fast execution bias gets priority for entry direction, while the score
   // remains informational. No AI threshold or MTF confirmation can block it.
   if(UseFastMomentumBias)
   {
      bool fastBuy=false,fastSell=false;
      if(FastDirection(fastBuy,fastSell))
      {
         if(fastBuy) { buySignal=true; sellSignal=false; }
         else if(fastSell) { buySignal=false; sellSignal=true; }
      }
   }

   if(!buySignal && !sellSignal && ma!=EMPTY_VALUE && bid>0)
   {
      buySignal=(bid>=ma);
      sellSignal=(bid<ma);
   }

   string displaySignal="WAITING";
   if(buySignal) displaySignal="BUY";
   else if(sellSignal) displaySignal="SELL";
   else if(!remoteTradingEnabled || isTradingPaused) displaySignal="PAUSED";

   UpdateSignalDisplay(displaySignal,score);
   if(displaySignal=="BUY")
      DrawSignalMarker("BUY",iTime(_Symbol,PERIOD_M5,0),SymbolInfoDouble(_Symbol,SYMBOL_BID));
   else if(displaySignal=="SELL")
      DrawSignalMarker("SELL",iTime(_Symbol,PERIOD_M5,0),SymbolInfoDouble(_Symbol,SYMBOL_ASK));

   if(DebugTrading)
      Print("Leona HYPERACTIVE M5 SIGNAL: score=",score,
            " AI_BLOCKER=OFF",
            " MTF_BLOCKER=OFF",
            " ADX=",DoubleToString(adx,2),
            " ATR=",DoubleToString(diagnosticATR,_Digits));

   if(buySignal)
   {
      if(RecalculateDirectionBeforeEachBurst)
      {
         bool fastBuy=false,fastSell=false;
         if(FastDirection(fastBuy,fastSell))
         {
            if(fastSell && !fastBuy)
            {
               diagnosticBlocker="DIRECTION FLIPPED TO SELL";
               UpdateChartStatus();
               int flipped=OpenSellBurst();
               diagnosticBlocker=(flipped>0) ? "SELL BURST EXECUTED" : "SELL BURST BLOCKED";
               return;
            }
         }
      }
      diagnosticBlocker="BUY - HYPERACTIVE EXECUTION";
      int opened=OpenBuyBurst();
      diagnosticBlocker=(opened>0) ? "BUY BURST EXECUTED" : "BUY BURST BLOCKED";
   }
   else if(sellSignal)
   {
      if(RecalculateDirectionBeforeEachBurst)
      {
         bool fastBuy=false,fastSell=false;
         if(FastDirection(fastBuy,fastSell))
         {
            if(fastBuy && !fastSell)
            {
               diagnosticBlocker="DIRECTION FLIPPED TO BUY";
               UpdateChartStatus();
               int flipped=OpenBuyBurst();
               diagnosticBlocker=(flipped>0) ? "BUY BURST EXECUTED" : "BUY BURST BLOCKED";
               return;
            }
         }
      }
      diagnosticBlocker="SELL - HYPERACTIVE EXECUTION";
      int opened=OpenSellBurst();
      diagnosticBlocker=(opened>0) ? "SELL BURST EXECUTED" : "SELL BURST BLOCKED";
   }

   UpdateChartStatus();
}
