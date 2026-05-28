//+------------------------------------------------------------------+
//| Risk/PortfolioManager.mqh                                        |
//+------------------------------------------------------------------+
#ifndef __PORTFOLIO_MANAGER_MQH__
#define __PORTFOLIO_MANAGER_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Core/Logger.mqh"

extern CLogger g_logger;

class CPortfolioManager
{
private:
   int m_corrLookback;
   ENUM_TIMEFRAMES m_mtf;
   double m_maxTotalRiskPercent;

public:
   bool Init(int lookback, ENUM_TIMEFRAMES mtf)
   {
      m_corrLookback = lookback; m_mtf = mtf; m_maxTotalRiskPercent = InpMaxTotalRisk;
      Print("[PortfolioManager] Correlation lookback: ", lookback, " bars");
      return true;
   }
   void UpdateState(EAState &state)
   {
      state.openPositions = 0; double totalRiskAmount = 0;
      int posTotal = PositionsTotal();
      for(int i = posTotal - 1; i >= 0; i--)
      {
         string sym = PositionGetSymbol(i);
         if(sym != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         state.openPositions++;
         double lots = PositionGetDouble(POSITION_VOLUME);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double slDist = MathAbs(entry - sl);
         double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         if(tickSize > 0) { double ticks = slDist / tickSize; totalRiskAmount += lots * ticks * tickValue; }
      }
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > 0) state.totalOpenRisk = (totalRiskAmount / equity) * 100.0;
      else state.totalOpenRisk = 0;
   }
   bool IsCorrelated(const SignalData &signal, const EAState &state)
   {
      if(!InpUseCorrelationFilter) return false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         string posSymbol = PositionGetSymbol(i);
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(posSymbol == _Symbol) continue;
         double corr = CalculateCorrelation(_Symbol, posSymbol);
         if(MathAbs(corr) > 0.7)
         {
            g_logger.LogEvent("PORTFOLIO", StringFormat("REJECTED: Correlation %.2f with %s", corr, posSymbol));
            return true;
         }
      }
      return false;
   }
   bool CheckExposure(const TradeParams &params, const EAState &state)
   {
      double projectedRisk = state.totalOpenRisk + params.riskPercent;
      if(projectedRisk > m_maxTotalRiskPercent)
      {
         g_logger.LogEvent("PORTFOLIO", StringFormat("REJECTED: Risk %.2f%% > max %.2f%%", projectedRisk, m_maxTotalRiskPercent));
         return false;
      }
      int forexCount = 0, metalCount = 0, indexCount = 0, cryptoCount = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string sym = PositionGetSymbol(i);
         if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "XAG") >= 0) metalCount++;
         else if(StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0) cryptoCount++;
         else if(StringFind(sym, "US30") >= 0 || StringFind(sym, "NAS") >= 0 || StringFind(sym, "GER") >= 0) indexCount++;
         else forexCount++;
      }
      ENUM_ASSET_CLASS cls = state.assetProfile.assetClass;
      if((cls == ASSET_FOREX_MAJOR || cls == ASSET_FOREX_CROSS) && forexCount >= 2) { g_logger.LogEvent("PORTFOLIO", "REJECTED: Max 2 Forex"); return false; }
      if(cls == ASSET_METAL && metalCount >= 1) { g_logger.LogEvent("PORTFOLIO", "REJECTED: Max 1 Metal"); return false; }
      if(cls == ASSET_INDEX && indexCount >= 1) { g_logger.LogEvent("PORTFOLIO", "REJECTED: Max 1 Index"); return false; }
      if(cls == ASSET_CRYPTO && cryptoCount >= 1) { g_logger.LogEvent("PORTFOLIO", "REJECTED: Max 1 Crypto"); return false; }
      return true;
   }

private:
   double CalculateCorrelation(string sym1, string sym2)
   {
      double c1[], c2[]; ArraySetAsSeries(c1, true); ArraySetAsSeries(c2, true);
      if(CopyClose(sym1, m_mtf, 1, m_corrLookback, c1) < m_corrLookback) return 0;
      if(CopyClose(sym2, m_mtf, 1, m_corrLookback, c2) < m_corrLookback) return 0;
      double mean1 = 0, mean2 = 0;
      for(int i = 0; i < m_corrLookback; i++) { mean1 += c1[i]; mean2 += c2[i]; }
      mean1 /= m_corrLookback; mean2 /= m_corrLookback;
      double cov = 0, var1 = 0, var2 = 0;
      for(int i = 0; i < m_corrLookback; i++)
      { double d1 = c1[i] - mean1; double d2 = c2[i] - mean2; cov += d1 * d2; var1 += d1 * d1; var2 += d2 * d2; }
      double std1 = MathSqrt(var1); double std2 = MathSqrt(var2);
      if(std1 * std2 == 0) return 0;
      return cov / (std1 * std2);
   }
};

#endif // __PORTFOLIO_MANAGER_MQH__
