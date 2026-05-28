//+------------------------------------------------------------------+
//| Risk/Protection.mqh                                              |
//| Circuit Breakers: Daily/Weekly Loss, Consecutive Loss, Spread     |
//| MODIFIED: Completed UpdateState with live statistics tracking   |
//+------------------------------------------------------------------+
#ifndef __PROTECTION_MQH__
#define __PROTECTION_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Core/Logger.mqh"

extern CLogger g_logger;

class CProtection
{
private:
   double m_maxDailyLoss;
   double m_maxWeeklyLoss;
   int m_maxConsecLosses;
   int m_maxPositions;
   double m_maxTotalRisk;
   datetime m_lastDailyReset;
   datetime m_lastWeeklyReset;
   double m_lastEquity;
   int m_consecLossCounter;
   datetime m_lastTradeTime;

public:
   bool Init(double dailyLoss, double weeklyLoss, int consecLoss, int maxPos, double maxRisk)
   {
      m_maxDailyLoss = dailyLoss;
      m_maxWeeklyLoss = weeklyLoss;
      m_maxConsecLosses = consecLoss;
      m_maxPositions = maxPos;
      m_maxTotalRisk = maxRisk;
      m_lastDailyReset = 0;
      m_lastWeeklyReset = 0;
      m_lastEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_consecLossCounter = 0;
      m_lastTradeTime = 0;
      Print("[Protection] Circuit breakers active. Daily:", dailyLoss, "% Weekly:", weeklyLoss, "% Consec:", consecLoss);
      return true;
   }

   bool IsCircuitBreakerActive(EAState &state) const
   {
      if(TimeCurrent() < state.circuitBreakerUntil)
         return true;
      if(state.circuitBreakerUntil > 0 && TimeCurrent() >= state.circuitBreakerUntil)
      {
         g_logger.LogEvent("PROTECTION", "Circuit breaker expired. Trading resumed.");
         state.circuitBreakerUntil = 0;
         state.circuitBreakerReason = "";
         state.dailyLimitHit = false;
         state.weeklyLimitHit = false;
         state.consecLossHalted = false;
      }
      return false;
   }

   bool PreTradeCheck(EAState &state) const
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0) return false;
      double dailyLimit = equity * (m_maxDailyLoss / 100.0);
      if(state.dailyPnL <= -dailyLimit)
      {
         ActivateBreaker(state, "Daily Loss Limit", 86400);
         state.dailyLimitHit = true;
         return false;
      }
      double weeklyLimit = equity * (m_maxWeeklyLoss / 100.0);
      if(state.weeklyPnL <= -weeklyLimit)
      {
         ActivateBreaker(state, "Weekly Loss Limit", 7 * 86400);
         state.weeklyLimitHit = true;
         return false;
      }
      if(state.consecutiveLosses >= m_maxConsecLosses)
      {
         ActivateBreaker(state, "Consecutive Losses", 86400);
         state.consecLossHalted = true;
         return false;
      }
      if(state.openPositions >= m_maxPositions)
         return false;
      return true;
   }

   bool IsSpreadAcceptable(const AssetProfile &profile) const
   {
      if(!InpUseSpreadFilter) return true;
      long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      double spreadPrice = spreadPoints * _Point;
      return (spreadPrice <= profile.maxSpreadPoints);
   }

   void UpdateState(EAState &state)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_lastEquity > 0 && currentEquity != m_lastEquity)
      {
         double equityChange = currentEquity - m_lastEquity;
         state.dailyPnL += equityChange;
         state.weeklyPnL += equityChange;
         if(equityChange < 0)
         {
            if(TimeCurrent() != m_lastTradeTime)
            {
               m_consecLossCounter++;
               state.consecutiveLosses = m_consecLossCounter;
               m_lastTradeTime = TimeCurrent();
               g_logger.LogEvent("PROTECTION", StringFormat("Loss detected. Consecutive: %d/%d", m_consecLossCounter, m_maxConsecLosses));
            }
         }
         else if(equityChange > 0)
         {
            if(m_consecLossCounter > 0)
            {
               m_consecLossCounter = 0;
               state.consecutiveLosses = 0;
               g_logger.LogEvent("PROTECTION", "Profit detected. Consecutive loss counter reset.");
            }
         }
      }
      m_lastEquity = currentEquity;
      if(InpDebugMode)
      {
         g_logger.LogEvent("PROTECTION", StringFormat("State | Daily: %.2f | Weekly: %.2f | Consec: %d | Equity: %.2f",
             state.dailyPnL, state.weeklyPnL, state.consecutiveLosses, currentEquity));
      }
   }

   void CheckDailyReset(EAState &state)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      datetime todayStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00", dt.year, dt.mon, dt.day));
      if(todayStart > m_lastDailyReset)
      {
         state.dailyPnL = 0;
         state.totalTradesToday = 0;
         state.consecutiveLosses = 0;
         m_consecLossCounter = 0;
         m_lastDailyReset = todayStart;
         state.equityAtStart = AccountInfoDouble(ACCOUNT_EQUITY);
         m_lastEquity = state.equityAtStart;
         g_logger.LogEvent("PROTECTION", "Daily counters reset");
      }
      if(dt.day_of_week == 1 && todayStart > m_lastWeeklyReset)
      {
         state.weeklyPnL = 0;
         state.totalTradesWeek = 0;
         m_lastWeeklyReset = todayStart;
         state.equityAtWeekStart = AccountInfoDouble(ACCOUNT_EQUITY);
         g_logger.LogEvent("PROTECTION", "Weekly counters reset");
      }
   }

private:
   void ActivateBreaker(EAState &state, string reason, int seconds) const
   {
      state.circuitBreakerUntil = TimeCurrent() + seconds;
      state.circuitBreakerReason = reason;
      g_logger.LogEvent("PROTECTION", StringFormat("CIRCUIT BREAKER: %s. Halted for %d sec.", reason, seconds));
   }
};

#endif // __PROTECTION_MQH__
