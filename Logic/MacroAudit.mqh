//+------------------------------------------------------------------+
//| Logic/MacroAudit.mqh                                             |
//+------------------------------------------------------------------+
#ifndef __MACRO_AUDIT_MQH__
#define __MACRO_AUDIT_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Core/Logger.mqh"
#include "../Data/VWAP_Engine.mqh"
#include "../Data/PriceEngine.mqh"

extern CLogger g_logger;
extern CPriceEngine g_priceEngine;

class CMacroAudit
{
private:
   ENUM_TIMEFRAMES m_htf;
   CVWAPEngine *m_vwap;

public:
   bool Init(ENUM_TIMEFRAMES htf, CVWAPEngine &vwap)
   {
      m_htf = htf; m_vwap = GetPointer(vwap);
      Print("[MacroAudit] HTF analysis initialized on ", EnumToString(htf));
      return true;
   }
   void Release() {}
   void Analyze(EAState &state)
   {
      if(!state.vwapState.isValid) { state.currentBias = BIAS_NEUTRAL; return; }
      MqlRates currentBar;
      if(!g_priceEngine.GetClosedBar(m_htf, 1, currentBar)) { state.currentBias = BIAS_NEUTRAL; return; }
      double price = currentBar.close;
      double vwap = state.vwapState.vwapValue;
      double slope = state.vwapState.vwapSlope;
      bool aboveVWAP = (price > vwap * 1.005);
      bool belowVWAP = (price < vwap * 0.995);
      bool risingVWAP = (slope > 0);
      bool fallingVWAP = (slope < 0);
      int highestIdx = iHighest(_Symbol, m_htf, MODE_HIGH, SWING_LOOKBACK, 1);
      int lowestIdx = iLowest(_Symbol, m_htf, MODE_LOW, SWING_LOOKBACK, 1);
      if(highestIdx < 0 || lowestIdx < 0) { state.currentBias = BIAS_NEUTRAL; return; }
      double swingHigh = iHigh(_Symbol, m_htf, highestIdx);
      double swingLow = iLow(_Symbol, m_htf, lowestIdx);
      state.swingHigh = swingHigh; state.swingLow = swingLow;
      bool bullBOS = (currentBar.close > swingHigh);
      bool bearBOS = (currentBar.close < swingLow);
      bool volConfirmed = false;
      int volHandle = iMA(_Symbol, m_htf, 20, 0, MODE_SMA, VOLUME_TICK);
      if(volHandle != INVALID_HANDLE)
      {
         double volMABuf[]; ArraySetAsSeries(volMABuf, true);
         if(CopyBuffer(volHandle, 0, 1, 1, volMABuf) > 0)
         {
            double avgVol = volMABuf[0];
            if(avgVol > 0) volConfirmed = (currentBar.tick_volume >= avgVol * VOLUME_CONFIRM);
         }
         IndicatorRelease(volHandle);
      }
      state.bosBullish = bullBOS && volConfirmed;
      state.bosBearish = bearBOS && volConfirmed;
      if(aboveVWAP && risingVWAP && state.bosBullish) state.currentBias = BIAS_BULL;
      else if(belowVWAP && fallingVWAP && state.bosBearish) state.currentBias = BIAS_BEAR;
      else if((aboveVWAP && risingVWAP) || state.bosBullish) state.currentBias = BIAS_BULL;
      else if((belowVWAP && fallingVWAP) || state.bosBearish) state.currentBias = BIAS_BEAR;
      else state.currentBias = BIAS_NEUTRAL;
   }
};

#endif // __MACRO_AUDIT_MQH__
