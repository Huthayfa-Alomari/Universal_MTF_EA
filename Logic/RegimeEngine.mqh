//+------------------------------------------------------------------+
//| Logic/RegimeEngine.mqh                                           |
//| Dual-State Logic with ML-based Regime Detection                  |
//+------------------------------------------------------------------+
#ifndef __REGIME_ENGINE_MQH__
#define __REGIME_ENGINE_MQH__

#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Core/Logger.mqh"
#include "../Execution/TradeManager.mqh"

extern CLogger g_logger;
extern CTradeManager g_tradeManager;

struct MLFeatureVector
{
   double atrRatio;
   double adx;
   double bbWidth;
   double volumeRatio;
   double priceMomentum;
};

struct MLRegimeSample
{
   MLFeatureVector features;
   ENUM_REGIME regime;
};

class CMLRegimeClassifier
{
private:
   MLRegimeSample m_trainingData[];
   int m_k;
   bool m_initialized;

public:
   CMLRegimeClassifier() : m_k(5), m_initialized(false) {}

   bool Init()
   {
      LoadDefaultTrainingData();
      m_initialized = true;
      Print("[MLRegimeClassifier] KNN initialized with ", ArraySize(m_trainingData), " samples");
      return true;
   }

   ENUM_REGIME Predict(const MLFeatureVector &features)
   {
      if(!m_initialized || ArraySize(m_trainingData) == 0) return REGIME_RANGE;
      double distances[];
      ArrayResize(distances, ArraySize(m_trainingData));
      for(int i = 0; i < ArraySize(m_trainingData); i++)
         distances[i] = CalculateDistance(features, m_trainingData[i].features);
      int trendVotes = 0, rangeVotes = 0, chopVotes = 0;
      for(int k = 0; k < m_k; k++)
      {
         int nearestIdx = FindMinIndex(distances);
         if(nearestIdx < 0) break;
         ENUM_REGIME vote = m_trainingData[nearestIdx].regime;
         if(vote == REGIME_TREND) trendVotes++;
         else if(vote == REGIME_RANGE) rangeVotes++;
         else chopVotes++;
         distances[nearestIdx] = DBL_MAX;
      }
      if(trendVotes >= rangeVotes && trendVotes >= chopVotes) return REGIME_TREND;
      if(rangeVotes >= trendVotes && rangeVotes >= chopVotes) return REGIME_RANGE;
      return REGIME_CHOP;
   }

   double GetConfidence(const MLFeatureVector &features)
   {
      if(!m_initialized || ArraySize(m_trainingData) == 0) return 0.5;
      double distances[];
      ArrayResize(distances, ArraySize(m_trainingData));
      for(int i = 0; i < ArraySize(m_trainingData); i++)
         distances[i] = CalculateDistance(features, m_trainingData[i].features);
      int trendVotes = 0, rangeVotes = 0, chopVotes = 0;
      for(int k = 0; k < m_k; k++)
      {
         int nearestIdx = FindMinIndex(distances);
         if(nearestIdx < 0) break;
         ENUM_REGIME vote = m_trainingData[nearestIdx].regime;
         if(vote == REGIME_TREND) trendVotes++;
         else if(vote == REGIME_RANGE) rangeVotes++;
         else chopVotes++;
         distances[nearestIdx] = DBL_MAX;
      }
      int maxVotes = MathMax(trendVotes, MathMax(rangeVotes, chopVotes));
      return (double)maxVotes / m_k;
   }

private:
   double CalculateDistance(const MLFeatureVector &a, const MLFeatureVector &b)
   {
      double d1 = (a.atrRatio - b.atrRatio) / 2.0;
      double d2 = (a.adx - b.adx) / 50.0;
      double d3 = (a.bbWidth - b.bbWidth) / 0.1;
      double d4 = (a.volumeRatio - b.volumeRatio) / 2.0;
      double d5 = (a.priceMomentum - b.priceMomentum) / 0.05;
      return MathSqrt(d1*d1 + d2*d2 + d3*d3 + d4*d4 + d5*d5);
   }

   int FindMinIndex(double &arr[])
   {
      if(ArraySize(arr) == 0) return -1;
      int minIdx = 0;
      for(int i = 1; i < ArraySize(arr); i++)
         if(arr[i] < arr[minIdx]) minIdx = i;
      return arr[minIdx] == DBL_MAX ? -1 : minIdx;
   }

   void LoadDefaultTrainingData()
   {
      AddSample(2.0, 35.0, 0.08, 1.5, 0.03, REGIME_TREND);
      AddSample(1.5, 28.0, 0.06, 1.3, 0.02, REGIME_TREND);
      AddSample(3.0, 40.0, 0.12, 2.0, 0.05, REGIME_TREND);
      AddSample(0.5, 15.0, 0.02, 0.8, 0.01, REGIME_RANGE);
      AddSample(0.7, 18.0, 0.03, 0.9, -0.01, REGIME_RANGE);
      AddSample(0.4, 12.0, 0.015, 0.6, 0.005, REGIME_RANGE);
      AddSample(0.3, 8.0, 0.01, 0.5, 0.002, REGIME_CHOP);
      AddSample(0.6, 10.0, 0.025, 0.7, -0.005, REGIME_CHOP);
      AddSample(0.8, 14.0, 0.04, 0.8, 0.008, REGIME_CHOP);
      AddSample(1.8, 22.0, 0.05, 1.1, 0.015, REGIME_TREND);
      AddSample(0.9, 16.0, 0.035, 0.85, -0.003, REGIME_RANGE);
      AddSample(0.2, 5.0, 0.008, 0.4, 0.001, REGIME_CHOP);
   }

   void AddSample(double atr, double adx, double bbw, double vol, double mom, ENUM_REGIME regime)
   {
      int idx = ArraySize(m_trainingData);
      ArrayResize(m_trainingData, idx + 1);
      m_trainingData[idx].features.atrRatio = atr;
      m_trainingData[idx].features.adx = adx;
      m_trainingData[idx].features.bbWidth = bbw;
      m_trainingData[idx].features.volumeRatio = vol;
      m_trainingData[idx].features.priceMomentum = mom;
      m_trainingData[idx].regime = regime;
   }
};

class CRegimeEngine
{
private:
   ENUM_REGIME m_lastRegime;
   bool m_initialized;
   CMLRegimeClassifier m_mlClassifier;
   double m_mlConfidence;

public:
   bool Init()
   {
      m_lastRegime = REGIME_RANGE;
      m_initialized = true;
      m_mlConfidence = 0.0;
      if(!m_mlClassifier.Init())
         Print("[RegimeEngine] ML classifier init failed. Using traditional method only.");
      Print("[RegimeEngine] Dual-state logic initialized (v2.0 with ML)");
      return true;
   }
   void Release() {}

   void UpdateState(EAState &state)
   {
      ENUM_REGIME newRegime = state.currentRegime;
      ENUM_REGIME mlRegime = GetMLPrediction(state);
      double mlConfidence = m_mlClassifier.GetConfidence(GetCurrentFeatures(state));
      if(mlConfidence > 0.6 && mlRegime != newRegime)
      {
         if(mlRegime == REGIME_CHOP && newRegime != REGIME_CHOP)
         {
            g_logger.LogEvent("REGIME", StringFormat("ML override: %s -> CHOP (conf: %.2f)", EnumToString(newRegime), mlConfidence));
            newRegime = REGIME_CHOP;
         }
         else if(mlRegime == REGIME_TREND && newRegime == REGIME_RANGE && mlConfidence > 0.75)
         {
            g_logger.LogEvent("REGIME", StringFormat("ML override: RANGE -> TREND (conf: %.2f)", mlConfidence));
            newRegime = REGIME_TREND;
         }
      }
      if(!m_initialized) return;
      if(newRegime != m_lastRegime)
      {
         HandleRegimeChange(m_lastRegime, newRegime, state);
         m_lastRegime = newRegime;
      }
      m_mlConfidence = mlConfidence;
   }

   string GetStrategyName(const EAState &state) const
   {
      if(state.currentRegime == REGIME_TREND && state.currentBias != BIAS_NEUTRAL)
         return "MOMENTUM (Trend Following)";
      else if(state.currentRegime == REGIME_RANGE && state.currentBias == BIAS_NEUTRAL)
         return "MEAN REVERSION (Range Trading)";
      else if(state.currentRegime == REGIME_CHOP)
         return "CAPITAL PRESERVATION (No Trade)";
      else
         return "MIXED (Caution)";
   }

   double GetMLConfidence() const { return m_mlConfidence; }

private:
   void HandleRegimeChange(ENUM_REGIME oldRegime, ENUM_REGIME newRegime, EAState &state)
   {
      string msg = StringFormat("REGIME CHANGE: %s -> %s", EnumToString(oldRegime), EnumToString(newRegime));
      g_logger.LogEvent("REGIME", msg);
      if(newRegime == REGIME_CHOP)
      {
         g_logger.LogEvent("REGIME", "CHOP detected. Capital preservation mode. Closing ALL.");
         g_tradeManager.CloseAllPositions(state, EXIT_REGIME_CHANGE);
         return;
      }
      if(oldRegime == REGIME_TREND && newRegime == REGIME_RANGE)
      {
         g_logger.LogEvent("REGIME", "Trend->Range. Tightening trailing stops.");
         g_tradeManager.TightenStops(state);
      }
      if(oldRegime == REGIME_RANGE && newRegime == REGIME_TREND)
      {
         g_logger.LogEvent("REGIME", "Range->Trend. Closing mean-reversion trades.");
         g_tradeManager.CloseRangeTrades(state);
      }
   }

   ENUM_REGIME GetMLPrediction(const EAState &state)
   {
      MLFeatureVector features = GetCurrentFeatures(state);
      return m_mlClassifier.Predict(features);
   }

   MLFeatureVector GetCurrentFeatures(const EAState &state)
   {
      MLFeatureVector fv;
      double atr = g_volatility.GetATR();
      double atrBaseline = 0;
      int atrHandle = iATR(_Symbol, InpMTF, 14);
      if(atrHandle != INVALID_HANDLE)
      {
         double atrBuf[];
         ArraySetAsSeries(atrBuf, true);
         if(CopyBuffer(atrHandle, 0, 1, 50, atrBuf) >= 50)
         {
            double sum = 0;
            for(int i = 0; i < 50; i++) sum += atrBuf[i];
            atrBaseline = sum / 50.0;
         }
         IndicatorRelease(atrHandle);
      }
      fv.atrRatio = (atrBaseline > 0) ? atr / atrBaseline : 1.0;
      fv.adx = g_volatility.GetADX();
      fv.bbWidth = g_volatility.GetBBWidth();
      fv.volumeRatio = state.volumeConfirmed ? 1.2 : 0.8;
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, InpMTF, 1, 6, rates) >= 6)
         fv.priceMomentum = (rates[0].close - rates[5].close) / rates[5].close;
      else
         fv.priceMomentum = 0;
      return fv;
   }
};

#endif // __REGIME_ENGINE_MQH__
