//+------------------------------------------------------------------+
//| Core/SymbolProfiler.mqh                                          |
//+------------------------------------------------------------------+
#ifndef __SYMBOL_PROFILER_MQH__
#define __SYMBOL_PROFILER_MQH__

#include "Config.mqh"

class CSymbolProfiler
{
public:
   bool Init(AssetProfile &profile)
   {
      string sym = _Symbol;
      profile.description = sym;
      if(IsMetal(sym))
      {
         profile.assetClass = ASSET_METAL;
         profile.atrMultiplierSL = 2.5;
         profile.maxSpreadPoints = 30.0 * _Point * 10;
         profile.londonOpenHour = 8;
         profile.nyOpenHour = 13;
         profile.trade24_7 = false;
         profile.skipWeekend = true;
         profile.sessionStartHour = 0;
         profile.sessionEndHour = 23;
         profile.minVolumeRatio = 0.7;
         profile.partialCloseRatio = 0.5;
         profile.beBufferPoints = 20.0 * _Point * 10;
         profile.trailingATRMult = 2.0;
         profile.maxTradeDuration = 360;
         profile.description = "Precious Metal (XAU/XAG)";
      }
      else if(IsIndex(sym))
      {
         profile.assetClass = ASSET_INDEX;
         profile.atrMultiplierSL = 3.0;
         profile.maxSpreadPoints = 5.0 * _Point;
         profile.londonOpenHour = 8;
         profile.nyOpenHour = 13;
         profile.trade24_7 = false;
         profile.skipWeekend = true;
         profile.sessionStartHour = 14;
         profile.sessionEndHour = 21;
         profile.minVolumeRatio = 0.6;
         profile.partialCloseRatio = 0.5;
         profile.beBufferPoints = 10.0 * _Point;
         profile.trailingATRMult = 2.5;
         profile.maxTradeDuration = 240;
         profile.description = "Equity Index";
      }
      else if(IsCrypto(sym))
      {
         profile.assetClass = ASSET_CRYPTO;
         profile.atrMultiplierSL = 2.0;
         profile.maxSpreadPoints = 50.0 * _Point;
         profile.londonOpenHour = 0;
         profile.nyOpenHour = 0;
         profile.trade24_7 = true;
         profile.skipWeekend = false;
         profile.sessionStartHour = 0;
         profile.sessionEndHour = 23;
         profile.minVolumeRatio = 0.5;
         profile.partialCloseRatio = 0.5;
         profile.beBufferPoints = 50.0 * _Point;
         profile.trailingATRMult = 1.5;
         profile.maxTradeDuration = 720;
         profile.description = "Cryptocurrency";
      }
      else if(IsCommodity(sym))
      {
         profile.assetClass = ASSET_COMMODITY;
         profile.atrMultiplierSL = 2.0;
         profile.maxSpreadPoints = 20.0 * _Point;
         profile.londonOpenHour = 8;
         profile.nyOpenHour = 13;
         profile.trade24_7 = false;
         profile.skipWeekend = true;
         profile.sessionStartHour = 0;
         profile.sessionEndHour = 22;
         profile.minVolumeRatio = 0.7;
         profile.partialCloseRatio = 0.5;
         profile.beBufferPoints = 15.0 * _Point;
         profile.trailingATRMult = 2.0;
         profile.maxTradeDuration = 360;
         profile.description = "Commodity (Oil)";
      }
      else if(IsForexMajor(sym))
      {
         profile.assetClass = ASSET_FOREX_MAJOR;
         profile.atrMultiplierSL = 1.5;
         profile.maxSpreadPoints = 2.0 * _Point * 10;
         profile.londonOpenHour = 8;
         profile.nyOpenHour = 13;
         profile.trade24_7 = false;
         profile.skipWeekend = true;
         profile.sessionStartHour = 0;
         profile.sessionEndHour = 23;
         profile.minVolumeRatio = 0.8;
         profile.partialCloseRatio = 0.5;
         profile.beBufferPoints = 5.0 * _Point * 10;
         profile.trailingATRMult = 1.5;
         profile.maxTradeDuration = 300;
         profile.description = "Forex Major";
      }
      else
      {
         profile.assetClass = ASSET_FOREX_CROSS;
         profile.atrMultiplierSL = 1.5;
         profile.maxSpreadPoints = 3.0 * _Point * 10;
         profile.londonOpenHour = 8;
         profile.nyOpenHour = 13;
         profile.trade24_7 = false;
         profile.skipWeekend = true;
         profile.sessionStartHour = 0;
         profile.sessionEndHour = 23;
         profile.minVolumeRatio = 0.8;
         profile.partialCloseRatio = 0.5;
         profile.beBufferPoints = 5.0 * _Point * 10;
         profile.trailingATRMult = 1.5;
         profile.maxTradeDuration = 300;
         profile.description = "Forex Cross";
      }
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(tickSize > 0 && point > 0)
      {
         double pipMultiplier = (tickSize / point);
         profile.maxSpreadPoints *= pipMultiplier;
         profile.beBufferPoints *= pipMultiplier;
      }
      Print("[SymbolProfiler] ", sym, " classified as: ", profile.description);
      return true;
   }

private:
   bool IsMetal(string sym) const
   {
      return (StringFind(sym, "XAU") >= 0 || StringFind(sym, "XAG") >= 0 ||
              StringFind(sym, "GOLD") >= 0 || StringFind(sym, "SILVER") >= 0);
   }
   bool IsIndex(string sym) const
   {
      return (StringFind(sym, "US30") >= 0 || StringFind(sym, "NAS") >= 0 ||
              StringFind(sym, "SPX") >= 0 || StringFind(sym, "GER") >= 0 ||
              StringFind(sym, "UK100") >= 0 || StringFind(sym, "JP225") >= 0 ||
              StringFind(sym, "AUS") >= 0);
   }
   bool IsCrypto(string sym) const
   {
      return (StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0 ||
              StringFind(sym, "XRP") >= 0 || StringFind(sym, "LTC") >= 0 ||
              StringFind(sym, "SOL") >= 0);
   }
   bool IsCommodity(string sym) const
   {
      return (StringFind(sym, "OIL") >= 0 || StringFind(sym, "BRENT") >= 0 ||
              StringFind(sym, "WTI") >= 0 || StringFind(sym, "GAS") >= 0);
   }
   bool IsForexMajor(string sym) const
   {
      string majors[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD",
                         "USDCAD", "NZDUSD", "EURJPY", "GBPJPY"};
      for(int i = 0; i < ArraySize(majors); i++)
         if(sym == majors[i]) return true;
      return false;
   }
};

#endif // __SYMBOL_PROFILER_MQH__
