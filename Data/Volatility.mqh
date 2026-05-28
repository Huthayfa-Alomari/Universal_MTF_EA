//+------------------------------------------------------------------+
//| Data/Volatility.mqh                                              |
//+------------------------------------------------------------------+
#ifndef __VOLATILITY_MQH__
#define __VOLATILITY_MQH__

#include "../Core/Config.mqh"

class CVolatility
{
private:
   int m_atrPeriod;
   int m_atrBaseline;
   ENUM_TIMEFRAMES m_htf;
   ENUM_TIMEFRAMES m_mtf;
   int m_handleATR;
   int m_handleADX;
   int m_handleBB;
   double m_atrCurrent;
   double m_atrBaselineValue;
   double m_atrRelative;
   double m_adxValue;
   double m_bbWidth;

public:
   bool Init(int atrPeriod, int atrBaseline, ENUM_TIMEFRAMES htf, ENUM_TIMEFRAMES mtf)
   {
      m_atrPeriod = atrPeriod; m_atrBaseline = atrBaseline; m_htf = htf; m_mtf = mtf;
      m_handleATR = iATR(_Symbol, m_mtf, m_atrPeriod);
      m_handleADX = iADX(_Symbol, m_mtf, ADX_PERIOD);
      m_handleBB = iBands(_Symbol, m_mtf, BB_PERIOD, 0, BB_DEVIATIONS, PRICE_CLOSE);
      if(m_handleATR == INVALID_HANDLE || m_handleADX == INVALID_HANDLE || m_handleBB == INVALID_HANDLE)
      {
         Print("[Volatility] Indicator creation failed");
         return false;
      }
      int warmup = MathMax(atrBaseline, BB_PERIOD) + 10;
      double dummy[]; ArraySetAsSeries(dummy, true);
      CopyBuffer(m_handleATR, 0, 1, warmup, dummy);
      Print("[Volatility] Indicators initialized on ", EnumToString(m_mtf));
      return true;
   }
   void Release()
   {
      RELEASE_HANDLE(m_handleATR);
      RELEASE_HANDLE(m_handleADX);
      RELEASE_HANDLE(m_handleBB);
   }
   void Update()
   {
      double atrBuf[], adxBuf[], bbUp[], bbLow[], bbMid[];
      ArraySetAsSeries(atrBuf, true); ArraySetAsSeries(adxBuf, true);
      ArraySetAsSeries(bbUp, true); ArraySetAsSeries(bbLow, true); ArraySetAsSeries(bbMid, true);
      if(CopyBuffer(m_handleATR, 0, 1, 1, atrBuf) <= 0) return;
      m_atrCurrent = atrBuf[0];
      if(CopyBuffer(m_handleADX, 0, 1, 1, adxBuf) <= 0) return;
      m_adxValue = adxBuf[0];
      if(CopyBuffer(m_handleBB, UPPER_BAND, 1, 1, bbUp) <= 0 ||
         CopyBuffer(m_handleBB, LOWER_BAND, 1, 1, bbLow) <= 0 ||
         CopyBuffer(m_handleBB, BASE_LINE, 1, 1, bbMid) <= 0) return;
      if(bbMid[0] != 0) m_bbWidth = (bbUp[0] - bbLow[0]) / bbMid[0]; else m_bbWidth = 0;
      CalculateATRBaseline();
   }
   double GetRelativeATR() const { return m_atrRelative; }
   double GetATR() const { return m_atrCurrent; }
   double GetADX() const { return m_adxValue; }
   double GetBBWidth() const { return m_bbWidth; }
   ENUM_REGIME DetectRegime() const
   {
      if(m_atrRelative >= ATR_TREND_RATIO && m_adxValue >= ADX_TREND_LEVEL) return REGIME_TREND;
      else if(m_atrRelative < ATR_CHOP_RATIO && m_adxValue < ADX_CHOP_LEVEL) return REGIME_CHOP;
      else if(m_atrRelative < ATR_TREND_RATIO && m_adxValue < ADX_RANGE_LEVEL) return REGIME_RANGE;
      return REGIME_RANGE;
   }

private:
   void CalculateATRBaseline()
   {
      double atrValues[]; ArraySetAsSeries(atrValues, true);
      if(CopyBuffer(m_handleATR, 0, 1, m_atrBaseline, atrValues) < m_atrBaseline)
      { m_atrRelative = 1.0; return; }
      double sum = 0;
      for(int i = 0; i < m_atrBaseline; i++) sum += atrValues[i];
      m_atrBaselineValue = sum / m_atrBaseline;
      if(m_atrBaselineValue > 0) m_atrRelative = m_atrCurrent / m_atrBaselineValue;
      else m_atrRelative = 1.0;
   }
};

#endif // __VOLATILITY_MQH__
