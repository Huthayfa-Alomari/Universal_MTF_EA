//+------------------------------------------------------------------+
//| Universal_MTF_EA.mq5                                             |
//| Universal Multi-Timeframe Expert Advisor v2.0                    |
//+------------------------------------------------------------------+
#property strict
#property copyright "Institutional Quantitative Systems"
#property version   "2.000"
#property description "Universal MTF EA v2.0"

//--- Input for magic number
input group "=== EA IDENTIFICATION ==="
input ulong InpMagicNumber = 20250625;
input string InpEALabel = "Universal_MTF";

//+------------------------------------------------------------------+
//| MODULE INCLUDES                                                  |
//+------------------------------------------------------------------+
input group "=== RISK MANAGEMENT ==="
input double InpMaxRiskPerTrade = 0.5;
input double InpMaxDailyLoss = 2.0;
input double InpMaxWeeklyLoss = 5.0;
input int InpMaxConsecLosses = 3;
input int InpMaxPositions = 5;
input double InpMaxTotalRisk = 3.0;

input group "=== TIME FRAME CONFIGURATION ==="
input ENUM_TIMEFRAMES InpHTF = PERIOD_H4;
input ENUM_TIMEFRAMES InpMTF = PERIOD_M15;
input ENUM_TIMEFRAMES InpLTF = PERIOD_M5;

input group "=== ATR & VOLATILITY ==="
input int InpATRPeriod = 14;
input int InpATRBaseline = 50;
input double InpTrendATRMult = 1.5;
input double InpRangeATRMult = 1.0;
input double InpTrailingMult = 2.0;

input group "=== SESSION & SYMBOL ==="
input bool InpUseSessionFilter = true;
input bool InpUseSpreadFilter = true;
input bool InpUseCorrelationFilter = true;

input group "=== NEWS FILTER ==="
input bool InpUseNewsFilter = true;
input int InpNewsBlockMinutes = 30;
input int InpNewsResumeMinutes = 15;

input group "=== ORDER EXECUTION ==="
input bool InpUseLimitOrders = true;
input int InpLimitOrderExpiry = 30;

input group "=== TELEGRAM/DISCORD ALERTS ==="
input string InpTelegramBotToken = "";
input string InpTelegramChatId = "";
input string InpDiscordWebhook = "";
input bool InpAlertOnTrade = true;
input bool InpAlertOnCircuitBreaker = true;
input bool InpAlertOnRegimeChange = true;
input bool InpSendDailySummary = true;

input group "=== LOGGING & AUDIT ==="
input string InpLogPath = "Universal_MTF_EA/";
input bool InpDebugMode = false;
input int InpDashboardUpdateSec = 5;

#include "Core/Config.mqh"
#include "Core/State.mqh"
#include "Core/Logger.mqh"
#include "Core/SymbolProfiler.mqh"
#include "Core/TelegramNotifier.mqh"
#include "Data/PriceEngine.mqh"
#include "Data/VWAP_Engine.mqh"
#include "Data/Volatility.mqh"
#include "Execution/OrderManager.mqh"
#include "Execution/TradeManager.mqh"
#include "Logic/MacroAudit.mqh"
#include "Logic/ContextFilter.mqh"
#include "Logic/MicroTrigger.mqh"
#include "Logic/RegimeEngine.mqh"
#include "Logic/NewsFilter.mqh"
#include "Risk/PositionSizer.mqh"
#include "Risk/Protection.mqh"
#include "Risk/PortfolioManager.mqh"

//+------------------------------------------------------------------+
//| MODULE INSTANCES                                                 |
//+------------------------------------------------------------------+
CLogger g_logger;
CSymbolProfiler g_profiler;
CTelegramNotifier g_notifier;
CPriceEngine g_priceEngine;
CVWAPEngine g_vwapEngine;
CVolatility g_volatility;
CMacroAudit g_macroAudit;
CContextFilter g_contextFilter;
CMicroTrigger g_microTrigger;
CRegimeEngine g_regimeEngine;
CNewsFilter g_newsFilter;
CPositionSizer g_positionSizer;
CProtection g_protection;
CPortfolioManager g_portfolio;
COrderManager g_orderManager;
CTradeManager g_tradeManager;

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("============================================================");
   Print("[Universal_MTF_EA] Initializing v2.000...");
   Print("============================================================");

   if(!g_logger.Init(InpLogPath, InpEALabel, InpMagicNumber))
   {
      Print("[CRITICAL] Logger init failed. EA halted.");
      return INIT_FAILED;
   }
   g_logger.LogEvent("SYSTEM", "EA Initialization started v2.0");

   if(!g_session.Init())
   {
      g_logger.LogError("OnInit", 0, "SessionManager init failed", 0);
      return INIT_FAILED;
   }

   if(!g_profiler.Init(g_state.assetProfile))
   {
      g_logger.LogError("OnInit", 0, "SymbolProfiler init failed", 0);
      return INIT_FAILED;
   }
   g_logger.LogEvent("SYSTEM", StringFormat("Asset: %s", g_state.assetProfile.description));

   if(!g_priceEngine.Init(InpHTF, InpMTF, InpLTF))
   {
      g_logger.LogError("OnInit", 0, "PriceEngine init failed", 0);
      return INIT_FAILED;
   }

   if(!g_vwapEngine.Init(g_state.assetProfile))
   {
      g_logger.LogError("OnInit", 0, "VWAPEngine init failed", 0);
      return INIT_FAILED;
   }

   if(!g_volatility.Init(InpATRPeriod, InpATRBaseline, InpHTF, InpMTF))
   {
      g_logger.LogError("OnInit", 0, "Volatility init failed", 0);
      return INIT_FAILED;
   }

   if(!g_macroAudit.Init(InpHTF, g_vwapEngine))
   {
      g_logger.LogError("OnInit", 0, "MacroAudit init failed", 0);
      return INIT_FAILED;
   }

   if(!g_contextFilter.Init(InpMTF, g_volatility))
   {
      g_logger.LogError("OnInit", 0, "ContextFilter init failed", 0);
      return INIT_FAILED;
   }

   if(!g_microTrigger.Init(InpLTF, g_priceEngine))
   {
      g_logger.LogError("OnInit", 0, "MicroTrigger init failed", 0);
      return INIT_FAILED;
   }

   if(!g_regimeEngine.Init())
   {
      g_logger.LogError("OnInit", 0, "RegimeEngine init failed", 0);
      return INIT_FAILED;
   }

   if(!g_newsFilter.Init(InpNewsBlockMinutes, InpNewsResumeMinutes))
   {
      g_logger.LogError("OnInit", 0, "NewsFilter init failed", 0);
      return INIT_FAILED;
   }

   if(!g_positionSizer.Init(g_state.assetProfile, InpMaxRiskPerTrade))
   {
      g_logger.LogError("OnInit", 0, "PositionSizer init failed", 0);
      return INIT_FAILED;
   }

   if(!g_protection.Init(InpMaxDailyLoss, InpMaxWeeklyLoss, InpMaxConsecLosses,
                           InpMaxPositions, InpMaxTotalRisk))
   {
      g_logger.LogError("OnInit", 0, "Protection init failed", 0);
      return INIT_FAILED;
   }

   if(!g_portfolio.Init(CORR_LOOKBACK, InpMTF))
   {
      g_logger.LogError("OnInit", 0, "PortfolioManager init failed", 0);
      return INIT_FAILED;
   }

   if(!g_orderManager.Init(InpMagicNumber, g_state.assetProfile))
   {
      g_logger.LogError("OnInit", 0, "OrderManager init failed", 0);
      return INIT_FAILED;
   }

   if(!g_tradeManager.Init(g_state.assetProfile, g_orderManager))
   {
      g_logger.LogError("OnInit", 0, "TradeManager init failed", 0);
      return INIT_FAILED;
   }

   if(!g_notifier.Init(InpTelegramBotToken, InpTelegramChatId, InpDiscordWebhook))
   {
      g_logger.LogEvent("SYSTEM", "TelegramNotifier init failed or disabled.");
   }

   g_state.equityAtStart = AccountInfoDouble(ACCOUNT_EQUITY);
   g_state.equityAtWeekStart = AccountInfoDouble(ACCOUNT_EQUITY);
   g_state.circuitBreakerUntil = 0;
   g_state.circuitBreakerReason = "";
   g_state.loggerReady = true;
   g_state.lastDashboardUpdate = 0;

   EventSetMillisecondTimer(30000);
   EventSetMillisecondTimer(5000);
   EventSetMillisecondTimer(InpDashboardUpdateSec * 1000);
   EventSetMillisecondTimer(3600000);
   EventSetMillisecondTimer(900000);

   g_priceEngine.RefreshAll();
   g_vwapEngine.Calculate(g_state.vwapState);
   g_volatility.Update();
   g_macroAudit.Analyze(g_state);
   g_contextFilter.Analyze(g_state);

   g_logger.LogEvent("SYSTEM", "EA Initialization completed successfully v2.0");
   g_logger.LogEvent("SYSTEM", StringFormat("Symbol: %s | Class: %s | HTF: %s | MTF: %s | LTF: %s",
                     _Symbol, g_state.assetProfile.description, EnumToString(InpHTF),
                     EnumToString(InpMTF), EnumToString(InpLTF)));

   if(InpAlertOnTrade)
   {
      g_notifier.SendMessage("*Universal MTF EA v2.0 Started*\n\nSymbol: " + _Symbol + 
                             "\nAsset: " + g_state.assetProfile.description +
                             "\nTime: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   }

   Print("[Universal_MTF_EA] Initialization complete. Ready for trading.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("============================================================");
   Print("[Universal_MTF_EA] Deinitializing... Reason: ", reason);
   Print("============================================================");
   EventKillTimer();
   g_logger.Shutdown();
   g_priceEngine.Release();
   g_vwapEngine.Release();
   g_volatility.Release();
   g_macroAudit.Release();
   g_contextFilter.Release();
   g_microTrigger.Release();

   if(InpAlertOnTrade)
   {
      g_notifier.SendMessage("*Universal MTF EA v2.0 Stopped*\n\nSymbol: " + _Symbol +
                             "\nReason: " + IntegerToString(reason) +
                             "\nDaily PnL: " + StringFormat("%.2f", g_state.dailyPnL) +
                             "\nTime: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   }

   g_logger.LogEvent("SYSTEM", StringFormat("EA Stopped. Daily: %.2f | Weekly: %.2f | Trades: %d",
                     g_state.dailyPnL, g_state.weeklyPnL, g_state.totalTradesToday));
   Print("[Universal_MTF_EA] Deinitialization complete.");
}

//+------------------------------------------------------------------+
//| EXPERT TICK HANDLER                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_protection.IsCircuitBreakerActive(g_state))
   {
      g_tradeManager.ManageOpenPositions(g_state, g_volatility);
      return;
   }
   if(InpUseSessionFilter && !g_session.IsSessionValid(g_state.assetProfile))
      return;
   if(g_session.IsRolloverTime())
      return;
   if(InpUseNewsFilter && !g_newsFilter.IsTradingAllowed())
      return;

   static datetime lastLTFTime = 0;
   datetime currentLTFTime = iTime(_Symbol, InpLTF, 0);
   if(currentLTFTime != lastLTFTime)
   {
      if(g_priceEngine.IsBarClosed(InpLTF))
      {
         g_state.isBarClosedLTF = true;
         g_state.lastLTFBarTime = currentLTFTime;
         g_priceEngine.RefreshLTF();
         if(g_state.currentBias != BIAS_NEUTRAL || g_state.currentRegime == REGIME_RANGE)
         {
            SignalData signal;
            g_microTrigger.GenerateSignal(signal, g_state, g_priceEngine);
            g_logger.LogSignal(signal, g_state);
            if(signal.isValid) ProcessSignal(signal);
         }
      }
      lastLTFTime = currentLTFTime;
   }
   g_tradeManager.ManageOpenPositions(g_state, g_volatility);
   g_portfolio.UpdateState(g_state);
   if(InpUseLimitOrders)
   {
      static datetime lastOrderCheck = 0;
      if(TimeCurrent() - lastOrderCheck > 300)
      {
         g_orderManager.CancelStaleOrders(InpLimitOrderExpiry);
         lastOrderCheck = TimeCurrent();
      }
   }
}

//+------------------------------------------------------------------+
//| TIMER HANDLER                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   static int timerCount = 0;
   timerCount++;
   if(timerCount % 6 == 0)
   {
      if(g_priceEngine.IsBarClosed(InpHTF))
      {
         g_state.isBarClosedHTF = true;
         g_state.lastHTFBarTime = iTime(_Symbol, InpHTF, 0);
         g_vwapEngine.Calculate(g_state.vwapState);
         g_macroAudit.Analyze(g_state);
      }
   }
   if(timerCount % 1 == 0)
   {
      if(g_priceEngine.IsBarClosed(InpMTF))
      {
         g_state.isBarClosedMTF = true;
         g_state.lastMTFBarTime = iTime(_Symbol, InpMTF, 0);
         g_volatility.Update();
         g_contextFilter.Analyze(g_state);
         g_regimeEngine.UpdateState(g_state);
      }
   }
   if(TimeCurrent() - g_state.lastDashboardUpdate >= InpDashboardUpdateSec)
   {
      g_logger.UpdateDashboard(g_state);
      g_state.lastDashboardUpdate = TimeCurrent();
   }
   g_protection.CheckDailyReset(g_state);
   if(InpSendDailySummary)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      static bool summarySentToday = false;
      if(dt.hour == 23 && !summarySentToday)
      {
         g_notifier.SendDailySummary(g_state);
         summarySentToday = true;
      }
      if(dt.hour == 0) summarySentToday = false;
   }
}

//+------------------------------------------------------------------+
//| SIGNAL PROCESSING                                                |
//+------------------------------------------------------------------+
void ProcessSignal(const SignalData &signal)
{
   if(InpUseSpreadFilter && !g_protection.IsSpreadAcceptable(g_state.assetProfile))
   {
      g_logger.LogEvent("FILTER", "Signal rejected: Spread too wide");
      return;
   }
   if(g_state.openPositions >= InpMaxPositions)
   {
      g_logger.LogEvent("FILTER", StringFormat("Max positions reached (%d)", g_state.openPositions));
      return;
   }
   if(InpUseCorrelationFilter && g_portfolio.IsCorrelated(signal, g_state))
   {
      g_logger.LogEvent("FILTER", "High correlation");
      return;
   }
   TradeParams tradeParams;
   g_positionSizer.Calculate(tradeParams, signal, g_state);
   if(!tradeParams.isValid)
   {
      g_logger.LogEvent("FILTER", StringFormat("Sizing failed: %s", tradeParams.rejectReason));
      return;
   }
   if(!g_portfolio.CheckExposure(tradeParams, g_state))
   {
      g_logger.LogEvent("FILTER", "Portfolio risk limit exceeded");
      return;
   }
   if(!g_protection.PreTradeCheck(g_state))
   {
      g_logger.LogEvent("FILTER", StringFormat("Circuit breaker: %s", g_state.circuitBreakerReason));
      return;
   }
   ulong ticket = 0;
   bool executed = g_orderManager.ExecuteOrder(signal, tradeParams, g_state, ticket);
   if(executed && ticket > 0)
   {
      g_state.openPositions++;
      g_logger.LogTradeOpen(signal, tradeParams, ticket);
      g_logger.LogEvent("EXECUTE", StringFormat("Order Ticket=%llu | %s | Lots: %.2f",
                          ticket, signal.isBuy ? "BUY" : "SELL", tradeParams.lotSize));
      if(InpAlertOnTrade) g_notifier.SendTradeOpen(signal, tradeParams, ticket);
   }
   else
   {
      g_logger.LogEvent("EXECUTE", "Order execution failed");
   }
}

//+------------------------------------------------------------------+
//| TRADE EVENT HANDLER                                              |
//+------------------------------------------------------------------+
void OnTrade()
{
   g_tradeManager.CheckClosedTrades(g_state);
   g_protection.UpdateState(g_state);
   if(g_state.lastTradeClose > 0)
   {
      g_logger.LogTradeClose(g_state);
      if(InpAlertOnTrade) g_notifier.SendTradeClose(g_state);
      if(g_state.dailyLimitHit || g_state.weeklyLimitHit || g_state.consecLossHalted)
      {
         if(InpAlertOnCircuitBreaker) g_notifier.SendCircuitBreaker(g_state);
      }
   }
}

//+------------------------------------------------------------------+
