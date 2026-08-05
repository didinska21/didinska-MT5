//+------------------------------------------------------------------+
//|                                                 TradeEngine.mqh  |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   The ONLY module allowed to call OrderSend(). Centralizes all  |
//|   market execution (open, close, modify SL/TP) with defensive    |
//|   retry logic for transient/recoverable trade server errors      |
//|   (Trade Context Busy, Requotes, Off Quotes, Timeout, etc).      |
//|   Every action funnels through Logger for full auditability.     |
//+------------------------------------------------------------------+
#ifndef __GHR_TRADEENGINE_MQH__
#define __GHR_TRADEENGINE_MQH__

#include "../Config/Inputs.mqh"
#include "Logger.mqh"
#include "Utils.mqh"

//====================================================================
// CLASS: CTradeEngine
//====================================================================
class CTradeEngine
  {
private:
   string   m_symbol;
   ulong    m_magic;
   int      m_slippagePoints;
   int      m_retryCount;
   int      m_retryDelayMs;
   string   m_commentPrefix;
   CLogger *m_logger;

   //-----------------------------------------------------------------
   // Picks a filling mode the symbol/broker actually supports,
   // preferring IOC, then FOK, then RETURN (fail-safe order).
   //-----------------------------------------------------------------
   ENUM_ORDER_TYPE_FILLING GetSupportedFillingMode()
     {
      int fillingFlags = (int)SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);

      if((fillingFlags & SYMBOL_FILLING_IOC) != 0)
         return ORDER_FILLING_IOC;
      if((fillingFlags & SYMBOL_FILLING_FOK) != 0)
         return ORDER_FILLING_FOK;

      return ORDER_FILLING_RETURN;
     }

   //-----------------------------------------------------------------
   string BuildComment(const int layer)
     {
      return StringFormat("%s-L%d", m_commentPrefix, layer);
     }

   //-----------------------------------------------------------------
   // Extracts the layer index embedded in a position's comment by
   // TradeEngine (e.g. "GoldHedgeRecovery-L2" -> 2). Returns -1 if
   // the comment does not match the expected pattern.
   //-----------------------------------------------------------------
public:
   static int ParseLayerFromComment(const string comment, const string prefix)
     {
      string marker = prefix + "-L";
      int pos = StringFind(comment, marker);
      if(pos < 0)
         return -1;

      string tail = StringSubstr(comment, pos + StringLen(marker));
      if(StringLen(tail) == 0)
         return -1;

      return (int)StringToInteger(tail);
     }

private:
   //-----------------------------------------------------------------
   // Generic retry wrapper around a single OrderSend attempt.
   //-----------------------------------------------------------------
   bool SendWithRetry(MqlTradeRequest &request, MqlTradeResult &result, const string actionLabel)
     {
      int attempts = 0;

      while(true)
        {
         attempts++;
         ZeroMemory(result);

         bool sent = OrderSend(request, result);

         if(sent && (result.retcode == TRADE_RETCODE_DONE ||
                     result.retcode == TRADE_RETCODE_PLACED ||
                     result.retcode == TRADE_RETCODE_DONE_PARTIAL))
           {
            return true;
           }

         if(m_logger != NULL)
            m_logger.Warning(StringFormat("%s attempt %d/%d failed. Retcode=%d (%s)",
                              actionLabel, attempts, m_retryCount, result.retcode,
                              CUtils::RetcodeDescription(result.retcode)));

         bool retryable = CUtils::IsRetryableRetcode(result.retcode);

         if(!retryable || attempts >= m_retryCount)
            return false;

         Sleep(m_retryDelayMs);

         // Refresh price on retry for market orders (price may have moved)
         if(request.action == TRADE_ACTION_DEAL && request.position == 0)
           {
            if(request.type == ORDER_TYPE_BUY)
               request.price = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
            else if(request.type == ORDER_TYPE_SELL)
               request.price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
           }
        }
     }

public:
   CTradeEngine()
     {
      m_magic          = 0;
      m_slippagePoints = 30;
      m_retryCount     = 3;
      m_retryDelayMs   = 200;
      m_commentPrefix  = "GoldHedgeRecovery";
      m_logger         = NULL;
     }

   //-----------------------------------------------------------------
   void Init(const string symbol, CLogger *logger)
     {
      m_symbol         = symbol;
      m_logger         = logger;
      m_magic          = InpMagicNumber;
      m_slippagePoints = InpSlippagePoints;
      m_retryCount     = MathMax(1, InpOrderRetryCount);
      m_retryDelayMs   = MathMax(0, InpOrderRetryDelayMs);
      m_commentPrefix  = InpTradeComment;
     }

   //-----------------------------------------------------------------
   // Opens a new market position in the given direction/lot, tagging
   // it with the given recovery layer index (embedded in the order
   // comment so PositionManager can recover layer state after a
   // terminal restart).
   //-----------------------------------------------------------------
   bool OpenPosition(const ENUM_TRADE_DIRECTION direction, const double rawLot, const int layer, ulong &outTicket)
     {
      outTicket = 0;

      if(direction == DIRECTION_NONE)
        {
         if(m_logger != NULL)
            m_logger.Error("CTradeEngine::OpenPosition failed - direction is NONE");
         return false;
        }

      double lot = CUtils::NormalizeLot(m_symbol, rawLot);
      if(lot <= 0.0)
        {
         if(m_logger != NULL)
            m_logger.Error("CTradeEngine::OpenPosition failed - normalized lot is <= 0");
         return false;
        }

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      double price = (direction == DIRECTION_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      request.action       = TRADE_ACTION_DEAL;
      request.symbol       = m_symbol;
      request.volume       = lot;
      request.type         = (direction == DIRECTION_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      request.price        = price;
      request.deviation    = m_slippagePoints;
      request.magic        = m_magic;
      request.comment      = BuildComment(layer);
      request.type_filling = GetSupportedFillingMode();
      request.type_time    = ORDER_TIME_GTC;

      bool ok = SendWithRetry(request, result, "OpenPosition");

      double floating = 0.0; // not applicable before position exists

      if(ok)
        {
         outTicket = result.order;
         if(m_logger != NULL)
            m_logger.LogTrade("OPEN", m_symbol, outTicket, layer, result.price, lot, 0.0, floating, result.retcode);
        }
      else
        {
         if(m_logger != NULL)
            m_logger.LogTrade("OPEN_FAILED", m_symbol, 0, layer, price, lot, 0.0, floating, result.retcode);
        }

      return ok;
     }

   //-----------------------------------------------------------------
   // Closes a single open position by ticket at current market price.
   //-----------------------------------------------------------------
   bool ClosePosition(const ulong ticket)
     {
      if(!PositionSelectByTicket(ticket))
        {
         if(m_logger != NULL)
            m_logger.Warning(StringFormat("CTradeEngine::ClosePosition - ticket %I64u not found (already closed?)", ticket));
         return false;
        }

      double volume  = PositionGetDouble(POSITION_VOLUME);
      long   posType = PositionGetInteger(POSITION_TYPE);
      int    layer   = ParseLayerFromComment(PositionGetString(POSITION_COMMENT), m_commentPrefix);
      double profitBefore = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      ENUM_ORDER_TYPE closeType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double price = (closeType == ORDER_TYPE_SELL) ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                                                     : SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action       = TRADE_ACTION_DEAL;
      request.symbol       = m_symbol;
      request.volume       = volume;
      request.type         = closeType;
      request.price        = price;
      request.deviation    = m_slippagePoints;
      request.magic        = m_magic;
      request.position     = ticket;
      request.type_filling = GetSupportedFillingMode();

      bool ok = SendWithRetry(request, result, "ClosePosition");

      if(m_logger != NULL)
        {
         string action = ok ? "CLOSE" : "CLOSE_FAILED";
         m_logger.LogTrade(action, m_symbol, ticket, layer, price, volume, profitBefore, 0.0, result.retcode);
        }

      return ok;
     }

   //-----------------------------------------------------------------
   // Closes every ticket in the given array. Returns true ONLY if
   // ALL positions closed successfully. Continues attempting the
   // remaining tickets even if one fails, so a single stuck position
   // doesn't block the rest of the basket from closing.
   //-----------------------------------------------------------------
   bool CloseAllPositions(ulong &tickets[])
     {
      int total = ArraySize(tickets);
      if(total == 0)
         return true;

      bool allOk = true;

      for(int i = 0; i < total; i++)
        {
         if(!ClosePosition(tickets[i]))
            allOk = false;
        }

      return allOk;
     }

   //-----------------------------------------------------------------
   // Modifies SL/TP on an existing open position (used by Break Even
   // and Trailing Stop logic).
   //-----------------------------------------------------------------
   bool ModifySLTP(const ulong ticket, const double newSL, const double newTP)
     {
      if(!PositionSelectByTicket(ticket))
        {
         if(m_logger != NULL)
            m_logger.Warning(StringFormat("CTradeEngine::ModifySLTP - ticket %I64u not found", ticket));
         return false;
        }

      int layer = ParseLayerFromComment(PositionGetString(POSITION_COMMENT), m_commentPrefix);

      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);

      request.action   = TRADE_ACTION_SLTP;
      request.symbol    = m_symbol;
      request.position  = ticket;
      request.sl        = CUtils::NormalizePrice(m_symbol, newSL);
      request.tp        = CUtils::NormalizePrice(m_symbol, newTP);

      bool ok = SendWithRetry(request, result, "ModifySLTP");

      if(m_logger != NULL)
        {
         string action = ok ? "MODIFY" : "MODIFY_FAILED";
         m_logger.LogTrade(action, m_symbol, ticket, layer, newSL, 0.0, 0.0, 0.0, result.retcode);
        }

      return ok;
     }
  };

#endif // __GHR_TRADEENGINE_MQH__
