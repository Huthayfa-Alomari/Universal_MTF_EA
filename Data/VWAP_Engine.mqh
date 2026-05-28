//+------------------------------------------------------------------+
//| Data/VWAP_Engine.mqh                                             |
//+------------------------------------------------------------------+
#ifndef __VWAP_ENGINE_MQH__
#define __VWAP_ENGINE_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"

class CVWAPEngine
{
private:
   AssetProfile m_profile;
   datetime m_lastSessionStart;
   double m_cachedVWAP;
   double m_cachedSlope;

public:
   bool Init(const AssetProfile &profile)
   {
      m_profile = profile;
      m_lastSessionStart = 0;
      m_cachedVWAP = 0;
      m_cachedSlope = 0;
      return true;
   }
   void Release() {}
   void Calculate(VWAPState &state)
   {
      datetime sessionStart = g_session.GetSessionStart(m_profile);
      if(sessionStart != m_lastSessionStart)
      {
         m_lastSessionStart = sessionStart;
         state.sumPV = 0; state.sumV = 0; state.sessionStart = sessionStart;
         m_cachedVWAP = 0; m_cachedSlope = 0;
      }
      MqlTick ticks[];
      int copied = CopyTicksRange(_Symbol, ticks, COPY_TICKS_TRADE, sessionStart, TimeCurrent());
      if(copied <= 0) { state.isValid = false; return; }
      double sumPV = 0; long sumV = 0;
      for(int i = 0; i < copied; i++)
      {
         double price = (ticks[i].bid + ticks[i].ask) / 2.0;
         long volume = (long)ticks[i].volume;
         if(volume > 0 && price > 0) { sumPV += price * (double)volume; sumV += volume; }
      }
      if(sumV > 0)
      {
         state.vwapValue = sumPV / (double)sumV;
         state.sumPV = sumPV; state.sumV = (double)sumV; state.isValid = true;
         m_cachedVWAP = state.vwapValue;
         CalculateSlope(state);
      }
      else { state.isValid = false; state.vwapValue = m_cachedVWAP; }
   }

private:
   void CalculateSlope(VWAPState &state)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(_Symbol, PERIOD_M15, 0, VWAP_SLOPE_BARS + 2, rates);
      if(copied < VWAP_SLOPE_BARS + 2) { state.vwapSlope = m_cachedSlope; return; }
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      int n = VWAP_SLOPE_BARS;
      for(int i = 1; i <= n; i++)
      {
         double x = (double)i;
         double y = rates[i].close - state.vwapValue;
         sumX += x; sumY += y; sumXY += x * y; sumX2 += x * x;
      }
      double denominator = (n * sumX2 - sumX * sumX);
      if(denominator != 0) { state.vwapSlope = (n * sumXY - sumX * sumY) / denominator; m_cachedSlope = state.vwapSlope; }
      else { state.vwapSlope = m_cachedSlope; }
   }
};

#endif // __VWAP_ENGINE_MQH__
