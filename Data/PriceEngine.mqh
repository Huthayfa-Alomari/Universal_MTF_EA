//+------------------------------------------------------------------+
//| Data/PriceEngine.mqh                                             |
//+------------------------------------------------------------------+
#ifndef __PRICE_ENGINE_MQH__
#define __PRICE_ENGINE_MQH__

#include "../Core/Config.mqh"

class CRepaintGuard
{
public:
   static bool ValidateShift(int shift, string context)
   {
      if(shift < 1)
      {
         Print("[REPAINT_GUARD] BLOCKED in ", context, ": shift=", shift, " < 1.");
         return false;
      }
      return true;
   }
};

class CPriceEngine
{
private:
   ENUM_TIMEFRAMES m_htf;
   ENUM_TIMEFRAMES m_mtf;
   ENUM_TIMEFRAMES m_ltf;
   MqlRates m_cacheHTF[];
   MqlRates m_cacheMTF[];
   MqlRates m_cacheLTF[];
   datetime m_lastHTFTime;
   datetime m_lastMTFTime;
   datetime m_lastLTFTime;
   int m_cacheSize;

public:
   bool Init(ENUM_TIMEFRAMES htf, ENUM_TIMEFRAMES mtf, ENUM_TIMEFRAMES ltf)
   {
      m_htf = htf; m_mtf = mtf; m_ltf = ltf; m_cacheSize = 100;
      ArraySetAsSeries(m_cacheHTF, true);
      ArraySetAsSeries(m_cacheMTF, true);
      ArraySetAsSeries(m_cacheLTF, true);
      m_lastHTFTime = 0; m_lastMTFTime = 0; m_lastLTFTime = 0;
      Print("[PriceEngine] Initialized | HTF:", EnumToString(htf), " MTF:", EnumToString(mtf), " LTF:", EnumToString(ltf));
      return true;
   }
   void Release()
   {
      ArrayFree(m_cacheHTF); ArrayFree(m_cacheMTF); ArrayFree(m_cacheLTF);
   }
   bool GetClosedBar(ENUM_TIMEFRAMES period, int shift, MqlRates &outRate)
   {
      if(!CRepaintGuard::ValidateShift(shift, "GetClosedBar")) shift = 1;
      MqlRates temp[];
      ArraySetAsSeries(temp, true);
      int copied = CopyRates(_Symbol, period, 0, shift + 1, temp);
      if(copied <= shift || ArraySize(temp) <= shift) return false;
      outRate = temp[shift];
      return true;
   }
   bool GetIndicatorBuffer(int handle, int bufferIndex, int shift, int count, double &buffer[])
   {
      if(handle == INVALID_HANDLE) return false;
      if(shift < 1) { CRepaintGuard::ValidateShift(shift, "GetIndicatorBuffer"); shift = 1; }
      ArraySetAsSeries(buffer, true);
      int copied = CopyBuffer(handle, bufferIndex, shift, count, buffer);
      return (copied > 0);
   }
   bool IsBarClosed(ENUM_TIMEFRAMES period) const
   {
      datetime currTime = iTime(_Symbol, period, 0);
      datetime prevTime = iTime(_Symbol, period, 1);
      return (currTime > 0 && prevTime > 0 && currTime != prevTime);
   }
   void RefreshAll() { RefreshHTF(); RefreshMTF(); RefreshLTF(); }
   void RefreshHTF()
   {
      int copied = CopyRates(_Symbol, m_htf, 0, m_cacheSize, m_cacheHTF);
      if(copied > 0) m_lastHTFTime = m_cacheHTF[0].time;
   }
   void RefreshMTF()
   {
      int copied = CopyRates(_Symbol, m_mtf, 0, m_cacheSize, m_cacheMTF);
      if(copied > 0) m_lastMTFTime = m_cacheMTF[0].time;
   }
   void RefreshLTF()
   {
      int copied = CopyRates(_Symbol, m_ltf, 0, m_cacheSize, m_cacheLTF);
      if(copied > 0) m_lastLTFTime = m_cacheLTF[0].time;
   }
   bool GetHTFBar(int shift, MqlRates &rate)
   {
      if(ArraySize(m_cacheHTF) > shift && shift >= 0) { rate = m_cacheHTF[shift]; return true; }
      return GetClosedBar(m_htf, shift, rate);
   }
   bool GetMTFBar(int shift, MqlRates &rate)
   {
      if(ArraySize(m_cacheMTF) > shift && shift >= 0) { rate = m_cacheMTF[shift]; return true; }
      return GetClosedBar(m_mtf, shift, rate);
   }
   bool GetLTFBar(int shift, MqlRates &rate)
   {
      if(ArraySize(m_cacheLTF) > shift && shift >= 0) { rate = m_cacheLTF[shift]; return true; }
      return GetClosedBar(m_ltf, shift, rate);
   }
};

#endif // __PRICE_ENGINE_MQH__
