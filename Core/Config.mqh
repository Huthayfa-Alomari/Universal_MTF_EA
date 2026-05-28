//+------------------------------------------------------------------+
//| Core/Config.mqh                                                  |
//| Universal Multi-Timeframe EA - Configuration & Type Definitions|
//+------------------------------------------------------------------+
#ifndef __CONFIG_MQH__
#define __CONFIG_MQH__

#property strict

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                     |
//+------------------------------------------------------------------+
enum ENUM_BIAS
{
   BIAS_BULL,
   BIAS_BEAR,
   BIAS_NEUTRAL
};

enum ENUM_REGIME
{
   REGIME_TREND,
   REGIME_RANGE,
   REGIME_CHOP
};

enum ENUM_PATTERN
{
   PATTERN_PIN_BAR,
   PATTERN_ENGULFING,
   PATTERN_INSIDE_BAR,
   PATTERN_NONE
};

enum ENUM_EXIT_REASON
{
   EXIT_TP1,
   EXIT_TP2,
   EXIT_SL,
   EXIT_BE,
   EXIT_TIME,
   EXIT_REGIME_CHANGE,
   EXIT_MANUAL,
   EXIT_TRAILING_STOP
};

enum ENUM_ASSET_CLASS
{
   ASSET_FOREX_MAJOR,
   ASSET_FOREX_CROSS,
   ASSET_METAL,
   ASSET_INDEX,
   ASSET_COMMODITY,
   ASSET_CRYPTO
};

//+------------------------------------------------------------------+
//| DATA STRUCTURES                                                  |
//+------------------------------------------------------------------+
struct SignalData
{
   bool isValid;
   bool isBuy;
   double entryPrice;
   double slPrice;
   double tp1Price;
   double tp2Price;
   ENUM_PATTERN pattern;
   string patternName;
   string rejectionReason;
   datetime signalTime;
   double atrValue;
};

struct TradeParams
{
   double lotSize;
   double riskAmount;
   double riskPercent;
   double slDistance;
   double tp1Distance;
   double tp2Distance;
   double marginRequired;
   bool isValid;
   string rejectReason;
};

struct AssetProfile
{
   ENUM_ASSET_CLASS assetClass;
   double atrMultiplierSL;
   double maxSpreadPoints;
   int londonOpenHour;
   int nyOpenHour;
   bool trade24_7;
   bool skipWeekend;
   int sessionStartHour;
   int sessionEndHour;
   double minVolumeRatio;
   double partialCloseRatio;
   double beBufferPoints;
   double trailingATRMult;
   int maxTradeDuration;
   string description;
};

struct VWAPState
{
   double vwapValue;
   double vwapSlope;
   datetime sessionStart;
   double sumPV;
   double sumV;
   bool isValid;
};

struct CorrelationData
{
   string symbol;
   double correlation;
   int barsUsed;
   datetime calcTime;
};

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+








//+------------------------------------------------------------------+
//| CONSTANTS                                                        |
//+------------------------------------------------------------------+
#define MAX_RETRIES 3
#define RETRY_BASE_MS 500
#define CORR_LOOKBACK 50
#define VWAP_SLOPE_BARS 5
#define SWING_LOOKBACK 20
#define VOLUME_MA_PERIOD 20
#define BB_PERIOD 20
#define BB_DEVIATIONS 2.0
#define ADX_PERIOD 14
#define ADX_TREND_LEVEL 25.0
#define ADX_RANGE_LEVEL 20.0
#define ADX_CHOP_LEVEL 15.0
#define ATR_TREND_RATIO 1.0
#define ATR_CHOP_RATIO 0.8
#define VOLUME_CONFIRM 1.2
#define MIN_VOLUME_RATIO 0.8
#define PIN_BAR_WICK_MULT 2.0
#define ENGULF_VOLUME_MULT 1.2
#define PARTIAL_CLOSE_R 1.5
#define BE_BUFFER_ATR_MULT 0.2
#define SLIPPAGE_ATR_MULT 0.5
#define MIN_SLIPPAGE_PTS 10
#define MAX_SLIPPAGE_PTS 50

#define ATR_TO_POINTS(atrValue) ((int)MathRound((atrValue) / _Point))
#define VALIDATE_SHIFT(shift, context) ((shift) >= 1 ? true : (Print("[REPAINT_GUARD] Violation in ", (context), ": shift=", (shift), " < 1. Using shift=1."), false))
#define RELEASE_HANDLE(handle) do { if((handle) != INVALID_HANDLE) { IndicatorRelease(handle); (handle) = INVALID_HANDLE; } } while(0)

//+------------------------------------------------------------------+
#endif // __CONFIG_MQH__
