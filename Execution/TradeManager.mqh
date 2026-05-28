//+------------------------------------------------------------------+
//| Execution/TradeManager.mqh                                       |
//| Trade Lifecycle: Partial Close, BE, Trailing Stop, Time Exit     |
//| MODIFIED: Added TP2 Full Close support                          |
//+------------------------------------------------------------------+
#ifndef __TRADE_MANAGER_MQH__
#define __TRADE_MANAGER_MQH__

#include <Trade\Trade.mqh>
#include "../Core/Config.mqh"
#include "../Core/State.mqh"
#include "../Core/Logger.mqh"
#include "../Data/Volatility.mqh"
#include "OrderManager.mqh"

extern CLogger g_logger;
extern CVolatility g_volatility;
extern EAState g_state;

class CTradeManager
{
private:
   CTrade m_trade;
   AssetProfile m_profile;
   COrderManager *m_orderMgr;

   struct TradeTracking
   {
      ulong ticket;
      datetime openTime;
      double entryPrice;
      double tp1Price;
      double tp2Price;
      double initialSL;
      double partialLot;
      bool tp1Hit;
      bool tp2Hit;
      bool beSet;
      bool trailingActive;
      ENUM_REGIME openRegime;
   };

   TradeTracking m_trades[];
   int m_tradeCount;

public:
   bool Init(const AssetProfile &profile, COrderManager &orderMgr)
   {
      m_profile = profile;
      m_orderMgr = GetPointer(orderMgr);
      m_tradeCount = 0;
      ArrayResize(m_trades, 10);
      Print("[TradeManager] Lifecycle manager initialized (v2.0 with TP2)");
      return true;
   }

   void ManageOpenPositions(EAState &state, CVolatility &vol)
   {
      int posTotal = PositionsTotal();
      if(posTotal == 0) { state.openPositions = 0; return; }
      double atr = vol.GetATR();
      if(atr <= 0) atr = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 10;
      for(int i = posTotal - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         double lots = PositionGetDouble(POSITION_VOLUME);
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         int type = (int)PositionGetInteger(POSITION_TYPE);
         int idx = FindTradeIndex(ticket);
         if(idx < 0) idx = RegisterTrade(ticket, entry, tp, sl, openTime);
         double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(!m_trades[idx].tp1Hit && m_trades[idx].tp1Price > 0)
         {
            bool hitTP1 = (type == POSITION_TYPE_BUY && currentPrice >= m_trades[idx].tp1Price) ||
                          (type == POSITION_TYPE_SELL && currentPrice <= m_trades[idx].tp1Price);
            if(hitTP1) { m_trades[idx].tp1Hit = true; PartialClose(idx, lots, ticket); }
         }
         if(m_trades[idx].tp1Hit && !m_trades[idx].tp2Hit && m_trades[idx].tp2Price > 0)
         {
            bool hitTP2 = (type == POSITION_TYPE_BUY && currentPrice >= m_trades[idx].tp2Price) ||
                          (type == POSITION_TYPE_SELL && currentPrice <= m_trades[idx].tp2Price);
            if(hitTP2)
            {
               m_trades[idx].tp2Hit = true;
               ClosePosition(ticket, EXIT_TP2);
               g_logger.LogEvent("TRADE", StringFormat("TP2 Full Close ticket %llu at %.5f", ticket, currentPrice));
               RemoveTrade(idx);
               continue;
            }
         }
         if(m_trades[idx].tp1Hit && !m_trades[idx].beSet)
            SetBreakEven(idx, entry, sl, type, atr);
         if(m_trades[idx].beSet && m_trades[idx].trailingActive)
            UpdateTrailingStop(idx, currentPrice, type, atr, sl);
         if(m_trades[idx].openRegime == REGIME_RANGE)
         {
            int elapsed = (int)(TimeCurrent() - openTime);
            if(elapsed >= m_profile.maxTradeDuration * 60)
            {
               g_logger.LogEvent("TRADE", StringFormat("Time exit ticket %llu after %d min", ticket, elapsed/60));
               ClosePosition(ticket, EXIT_TIME);
               RemoveTrade(idx);
               continue;
            }
         }
      }
      state.openPositions = CountOurPositions();
   }

   void CheckClosedTrades(EAState &state)
   {
      for(int i = m_tradeCount - 1; i >= 0; i--)
      {
         if(!PositionSelectByTicket(m_trades[i].ticket))
         {
            state.lastTradeClose = TimeCurrent();
            state.totalTradesToday++;
            state.totalTradesWeek++;
            RemoveTrade(i);
         }
      }
   }

   void CloseAllPositions(EAState &state, ENUM_EXIT_REASON reason)
   {
      int posTotal = PositionsTotal();
      for(int i = posTotal - 1; i >= 0; i--)
      {
         if(PositionGetSymbol(i) != _Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         ClosePosition(ticket, reason);
      }
      ArrayResize(m_trades, 10);
      m_tradeCount = 0;
      state.openPositions = 0;
   }

   void CloseRangeTrades(EAState &state)
   {
      for(int i = m_tradeCount - 1; i >= 0; i--)
      {
         if(m_trades[i].openRegime == REGIME_RANGE)
         {
            if(PositionSelectByTicket(m_trades[i].ticket))
               ClosePosition(m_trades[i].ticket, EXIT_REGIME_CHANGE);
            RemoveTrade(i);
         }
      }
   }

   void TightenStops(EAState &state)
   {
      double atr = g_volatility.GetATR();
      for(int i = 0; i < m_tradeCount; i++)
      {
         if(!PositionSelectByTicket(m_trades[i].ticket)) continue;
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         int type = (int)PositionGetInteger(POSITION_TYPE);
         double newSL;
         double buffer = atr * 0.5;
         if(type == POSITION_TYPE_BUY)
         {
            newSL = entry + buffer;
            if(newSL > currentSL || currentSL == 0)
               m_trade.PositionModify(m_trades[i].ticket, newSL, PositionGetDouble(POSITION_TP));
         }
         else
         {
            newSL = entry - buffer;
            if(newSL < currentSL || currentSL == 0)
               m_trade.PositionModify(m_trades[i].ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      }
   }

private:
   int FindTradeIndex(ulong ticket) const
   {
      for(int i = 0; i < m_tradeCount; i++)
         if(m_trades[i].ticket == ticket) return i;
      return -1;
   }

   int RegisterTrade(ulong ticket, double entry, double tp1, double sl, datetime time)
   {
      if(m_tradeCount >= ArraySize(m_trades)) ArrayResize(m_trades, ArraySize(m_trades) + 10);
      int idx = m_tradeCount++;
      m_trades[idx].ticket = ticket;
      m_trades[idx].entryPrice = entry;
      m_trades[idx].tp1Price = tp1;
      m_trades[idx].initialSL = sl;
      m_trades[idx].openTime = time;
      m_trades[idx].tp1Hit = false;
      m_trades[idx].tp2Hit = false;
      m_trades[idx].beSet = false;
      m_trades[idx].trailingActive = true;
      m_trades[idx].openRegime = g_state.currentRegime;
      m_trades[idx].partialLot = 0;
      return idx;
   }

   void RemoveTrade(int idx)
   {
      if(idx < 0 || idx >= m_tradeCount) return;
      for(int i = idx; i < m_tradeCount - 1; i++)
         m_trades[i] = m_trades[i + 1];
      m_tradeCount--;
   }

   void PartialClose(int idx, double totalLots, ulong ticket)
   {
      double closeLots = NormalizeDouble(totalLots * m_profile.partialCloseRatio, 2);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(closeLots < minLot) closeLots = minLot;
      if(closeLots >= totalLots) closeLots = totalLots * 0.5;
      m_trades[idx].partialLot = closeLots;
      if(m_trade.PositionClosePartial(ticket, closeLots))
         g_logger.LogEvent("TRADE", StringFormat("Partial close %.2f lots ticket %llu", closeLots, ticket));
      else
         g_logger.LogEvent("TRADE", StringFormat("Partial close FAILED ticket %llu", ticket));
   }

   void SetBreakEven(int idx, double entry, double currentSL, int type, double atr)
   {
      double buffer = atr * BE_BUFFER_ATR_MULT;
      double newSL;
      if(type == POSITION_TYPE_BUY) newSL = entry + buffer;
      else newSL = entry - buffer;
      bool shouldMove = (type == POSITION_TYPE_BUY && (newSL > currentSL || currentSL == 0)) ||
                        (type == POSITION_TYPE_SELL && (newSL < currentSL || currentSL == 0));
      if(shouldMove)
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         if(m_trade.PositionModify(m_trades[idx].ticket, newSL, currentTP))
         {
            m_trades[idx].beSet = true;
            g_logger.LogEvent("TRADE", StringFormat("BE set ticket %llu at %.5f", m_trades[idx].ticket, newSL));
         }
      }
   }

   void UpdateTrailingStop(int idx, double currentPrice, int type, double atr, double currentSL)
   {
      double trailDist = atr * m_profile.trailingATRMult;
      double newSL;
      if(type == POSITION_TYPE_BUY)
      {
         newSL = currentPrice - trailDist;
         if(newSL > currentSL)
         {
            double currentTP = PositionGetDouble(POSITION_TP);
            m_trade.PositionModify(m_trades[idx].ticket, newSL, currentTP);
         }
      }
      else
      {
         newSL = currentPrice + trailDist;
         if(newSL < currentSL || currentSL == 0)
         {
            double currentTP = PositionGetDouble(POSITION_TP);
            m_trade.PositionModify(m_trades[idx].ticket, newSL, currentTP);
         }
      }
   }

   void ClosePosition(ulong ticket, ENUM_EXIT_REASON reason)
   {
      if(m_trade.PositionClose(ticket))
         g_logger.LogEvent("TRADE", StringFormat("Closed ticket %llu. Reason: %s", ticket, EnumToString(reason)));
   }

   int CountOurPositions() const
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
         if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
      return count;
   }
};

#endif // __TRADE_MANAGER_MQH__
