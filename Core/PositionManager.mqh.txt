//+------------------------------------------------------------------+
//|                                             PositionManager.mqh  |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Single source of truth for "what positions does THIS EA        |
//|   currently have open, and what layer is each one?"              |
//|                                                                  |
//|   Rebuilds its internal cache directly from the live terminal    |
//|   position list every time Refresh() is called (no persisted     |
//|   state of its own) — this means the EA can recover its exact    |
//|   basket state after a terminal restart simply by reading the    |
//|   layer number embedded in each position's comment.              |
//+------------------------------------------------------------------+
#ifndef __GHR_POSITIONMANAGER_MQH__
#define __GHR_POSITIONMANAGER_MQH__

#include "../Config/Inputs.mqh"
#include "Logger.mqh"
#include "TradeEngine.mqh" // for CTradeEngine::ParseLayerFromComment (static)

//====================================================================
// CLASS: CPositionManager
//====================================================================
class CPositionManager
  {
private:
   string   m_symbol;
   ulong    m_magic;
   string   m_commentPrefix;
   CLogger *m_logger;

   ulong               m_tickets[];
   ENUM_TRADE_DIRECTION m_directions[];
   double              m_lots[];
   double              m_openPrices[];
   datetime            m_openTimes[];
   int                 m_layers[];
   int                 m_count;

   //-----------------------------------------------------------------
   int FindIndexByTicket(const ulong ticket)
     {
      for(int i = 0; i < m_count; i++)
        {
         if(m_tickets[i] == ticket)
            return i;
        }
      return -1;
     }

public:
   CPositionManager()
     {
      m_magic         = 0;
      m_count         = 0;
      m_commentPrefix = "GoldHedgeRecovery";
      m_logger        = NULL;
     }

   //-----------------------------------------------------------------
   void Init(const string symbol, const ulong magic, const string commentPrefix, CLogger *logger)
     {
      m_symbol        = symbol;
      m_magic         = magic;
      m_commentPrefix = commentPrefix;
      m_logger        = logger;
      m_count         = 0;
     }

   //-----------------------------------------------------------------
   // Rebuilds the internal cache from live terminal positions. Must
   // be called once at the start of every OnTick() before any other
   // method on this class is used.
   //-----------------------------------------------------------------
   void Refresh()
     {
      int total = PositionsTotal();

      ArrayResize(m_tickets, total);
      ArrayResize(m_directions, total);
      ArrayResize(m_lots, total);
      ArrayResize(m_openPrices, total);
      ArrayResize(m_openTimes, total);
      ArrayResize(m_layers, total);

      m_count = 0;

      for(int i = 0; i < total; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;

         if(!PositionSelectByTicket(ticket))
            continue;

         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         string comment = PositionGetString(POSITION_COMMENT);
         int layer = CTradeEngine::ParseLayerFromComment(comment, m_commentPrefix);
         if(layer < 0)
           {
            layer = 0; // defensive fallback if comment was altered/truncated by broker
            if(m_logger != NULL)
               m_logger.Debug(StringFormat("PositionManager - could not parse layer from comment '%s', defaulting to 0", comment));
           }

         long posType = PositionGetInteger(POSITION_TYPE);

         m_tickets[m_count]    = ticket;
         m_directions[m_count] = (posType == POSITION_TYPE_BUY) ? DIRECTION_BUY : DIRECTION_SELL;
         m_lots[m_count]       = PositionGetDouble(POSITION_VOLUME);
         m_openPrices[m_count] = PositionGetDouble(POSITION_PRICE_OPEN);
         m_openTimes[m_count]  = (datetime)PositionGetInteger(POSITION_TIME);
         m_layers[m_count]     = layer;
         m_count++;
        }

      ArrayResize(m_tickets, m_count);
      ArrayResize(m_directions, m_count);
      ArrayResize(m_lots, m_count);
      ArrayResize(m_openPrices, m_count);
      ArrayResize(m_openTimes, m_count);
      ArrayResize(m_layers, m_count);
     }

   //-----------------------------------------------------------------
   bool HasOpenPositions() const { return m_count > 0; }
   int  GetLayerCount()    const { return m_count; }

   //-----------------------------------------------------------------
   double GetTotalLot()
     {
      double total = 0.0;
      for(int i = 0; i < m_count; i++)
         total += m_lots[i];
      return total;
     }

   //-----------------------------------------------------------------
   // Live floating profit (profit + swap) summed across all tracked
   // positions. Queried fresh from the terminal each call since
   // profit changes every tick.
   //-----------------------------------------------------------------
   double GetFloatingProfit()
     {
      double total = 0.0;
      for(int i = 0; i < m_count; i++)
        {
         if(!PositionSelectByTicket(m_tickets[i]))
            continue;
         total += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        }
      return total;
     }

   //-----------------------------------------------------------------
   double GetTicketProfit(const ulong ticket)
     {
      if(!PositionSelectByTicket(ticket))
         return 0.0;
      return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
     }

   //-----------------------------------------------------------------
   int GetTicketLayer(const ulong ticket)
     {
      int idx = FindIndexByTicket(ticket);
      return (idx >= 0) ? m_layers[idx] : -1;
     }

   ENUM_TRADE_DIRECTION GetTicketDirection(const ulong ticket)
     {
      int idx = FindIndexByTicket(ticket);
      return (idx >= 0) ? m_directions[idx] : DIRECTION_NONE;
     }

   double GetTicketLot(const ulong ticket)
     {
      int idx = FindIndexByTicket(ticket);
      return (idx >= 0) ? m_lots[idx] : 0.0;
     }

   double GetTicketOpenPrice(const ulong ticket)
     {
      int idx = FindIndexByTicket(ticket);
      return (idx >= 0) ? m_openPrices[idx] : 0.0;
     }

   //-----------------------------------------------------------------
   // Returns the direction/lot/open-time of the HIGHEST layer index
   // currently open (i.e. the most recently opened layer).
   //-----------------------------------------------------------------
   ENUM_TRADE_DIRECTION GetLastLayerDirection()
     {
      if(m_count == 0)
         return DIRECTION_NONE;

      int bestIdx = 0;
      for(int i = 1; i < m_count; i++)
         if(m_layers[i] > m_layers[bestIdx])
            bestIdx = i;

      return m_directions[bestIdx];
     }

   double GetLastLayerLot()
     {
      if(m_count == 0)
         return 0.0;

      int bestIdx = 0;
      for(int i = 1; i < m_count; i++)
         if(m_layers[i] > m_layers[bestIdx])
            bestIdx = i;

      return m_lots[bestIdx];
     }

   datetime GetLastLayerOpenTime()
     {
      if(m_count == 0)
         return 0;

      int bestIdx = 0;
      for(int i = 1; i < m_count; i++)
         if(m_layers[i] > m_layers[bestIdx])
            bestIdx = i;

      return m_openTimes[bestIdx];
     }

   //-----------------------------------------------------------------
   // Copies all currently tracked tickets into the caller's array.
   //-----------------------------------------------------------------
   void GetTicketsArray(ulong &out[])
     {
      ArrayResize(out, m_count);
      for(int i = 0; i < m_count; i++)
         out[i] = m_tickets[i];
     }

   //-----------------------------------------------------------------
   // Returns tickets whose individual floating profit (profit+swap)
   // is at or above targetUSD. Used by RecoveryEngine for Individual
   // TP management. Returns the number of matching tickets.
   //-----------------------------------------------------------------
   int GetTicketsAtOrAboveProfit(const double targetUSD, ulong &outTickets[])
     {
      ArrayResize(outTickets, m_count);
      int found = 0;

      for(int i = 0; i < m_count; i++)
        {
         double profit = GetTicketProfit(m_tickets[i]);
         if(profit >= targetUSD)
           {
            outTickets[found] = m_tickets[i];
            found++;
           }
        }

      ArrayResize(outTickets, found);
      return found;
     }

   //-----------------------------------------------------------------
   // Baseline state derived purely from position count. The main EA
   // layers additional states (COOLDOWN, EMERGENCY_CLOSED,
   // PAUSED_RISK) on top of this via RecoveryEngine/RiskEngine.
   //-----------------------------------------------------------------
   ENUM_TRADE_STATE DetermineBaselineState()
     {
      if(m_count == 0)
         return STATE_IDLE;
      if(m_count == 1)
         return STATE_INITIAL_OPEN;
      return STATE_RECOVERY_ACTIVE;
     }
  };

#endif // __GHR_POSITIONMANAGER_MQH__
