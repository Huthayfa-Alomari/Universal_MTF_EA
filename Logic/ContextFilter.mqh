//+------------------------------------------------------------------+
//| Logic/ContextFilter.mqh                                          |
//+------------------------------------------------------------------+
#ifndef __CONTEXT_FILTER_MQH__
#define __CONTEXT_FILTER_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Data/Volatility.mqh"

class CContextFilter
{
private:
   ENUM_TIMEFRAMES m_mtf;
   CVolatility *m_vol;

public:
   bool Init(ENUM_TIMEFRAMES mtf, CVolatility &vol)
   {
      m_mtf = mtf; m_vol = GetPointer(vol);
      Print("[ContextFilter] MTF analysis initialized on ", EnumToString(mtf));
      return true;
   }
   void Release() {}
   void Analyze(EAState &state)
   {
      state.volumeConfirmed = CheckVolume();
      m_vol.Update();
      state.currentRegime = m_vol.DetectRegime();
   }

private:
   bool CheckVolume()
   {
      MqlRates rates[]; ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, m_mtf, 0, VOLUME_MA_PERIOD + 2, rates) < VOLUME_MA_PERIOD + 2) return false;
      double sumVol = 0;
      for(int i = 1; i <= VOLUME_MA_PERIOD; i++) sumVol += (double)rates[i].tick_volume;
      double volMA = sumVol / VOLUME_MA_PERIOD;
      double currentVol = (double)rates[1].tick_volume;
      if(volMA > 0) return (currentVol >= volMA * MIN_VOLUME_RATIO);
      return false;
   }
};

#endif // __CONTEXT_FILTER_MQH__
