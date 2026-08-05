//+------------------------------------------------------------------+
//|                                              RecoveryEngine.mqh  |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   The heart of the trading concept. Owns the full lifecycle of   |
//|   ONE hedge-recovery cycle:                                      |
//|                                                                  |
//|     Initial Entry -> (price moves against) -> Recovery Layer     |
//|     (opposite direction, larger lot) -> ... -> Individual TP     |
//|     per layer AND/OR Basket TP closes everything together ->     |
//|     Cooldown -> ready for next cycle.                            |
//|                                                                  |
//|   Also enforces Break Even / Trailing Stop on the initial layer, |
//|   and reacts to RiskEngine's emergency-close signal.             |
//|                                                                  |
//| CALL ORDER (once per OnTick(), AFTER CPositionManager.Refresh()):|
//|   1. ManageEmergencyClose()                                       |
//|   2. ManageIndividualTP()                                        |
//|   3. ManageBasketTP()                                            |
//|   4. ManageBreakEven()                                           |
//|   5. ManageTrailing()                                            |
//|   6. ManageRecoveryLayers()                                       |
//|   7. TryOpenInitialPosition() — only if no positions are open     |
//+------------------------------------------------------------------+
#ifndef __GHR_RECOVERYENGINE_MQH__
#define __GHR_RECOVERYENGINE_MQH__

#include "../Config/Inputs.mqh"
#include "Logger.mqh"
#include "Utils.mqh"
#include "PositionManager.mqh"
#include "TradeEngine.mqh"
#include "RiskEngine.mqh"

//====================================================================
// CLASS: CRecoveryEngine
//====================================================================
class CRecoveryEngine
  {
private:
   string             m_symbol;
   CLogger           *m_logger;
   CPositionManager  *m_posMgr;
   CTradeEngine      *m_tradeEngine;
   CRiskEngine       *m_riskEngine;

   double             m_customSequence[];
   int                m_customCount;

   datetime           m_lastCycleCloseTime;
   ENUM_TRADE_STATE   m_state;

   //-----------------------------------------------------------------
   // Determines the lot size for the NEXT layer about to be opened.
   // nextLayerIndex is the index the new layer WILL have (0 = initial,
   // 1 = first recovery, 2 = second recovery, ...).
   //-----------------------------------------------------------------
   double ComputeNextLot(const int nextLayerIndex, const double lastLot)
     {
      if(nextLayerIndex == 0)
         return InpBaseLot;

      switch(InpRecoveryMode)
        {
         case RECOVERY_FIXED_LOT:
            return InpBaseLot;

         case RECOVERY_MULTIPLIER:
            return lastLot * InpRecoveryMultiplier;

         case RECOVERY_CUSTOM_SEQUENCE:
           {
            int seqIndex = nextLayerIndex - 1; // sequence covers recovery layers only (layer 1 = index 0)
            if(m_customCount > 0)
              {
               if(seqIndex >= 0 && seqIndex < m_customCount)
                  return m_customSequence[seqIndex];
               // Ran out of explicit sequence values — fall back to
               // repeating the last defined value rather than failing.
               return m_customSequence[m_customCount - 1];
              }
            // No valid sequence parsed — fall back to multiplier behavior
            if(m_logger != NULL)
               m_logger.Warning("RecoveryEngine - custom lot sequence empty/invalid, falling back to multiplier x2.0");
            return lastLot * 2.0;
           }

         default:
            return lastLot * 2.0;
        }
     }

public:
   CRecoveryEngine()
     {
      m_logger             = NULL;
      m_posMgr             = NULL;
      m_tradeEngine        = NULL;
      m_riskEngine         = NULL;
      m_customCount        = 0;
      m_lastCycleCloseTime = 0;
      m_state              = STATE_IDLE;
     }

   //-----------------------------------------------------------------
   void Init(const string symbol, CLogger *logger, CPositionManager *posMgr,
             CTradeEngine *tradeEngine, CRiskEngine *riskEngine)
     {
      m_symbol      = symbol;
      m_logger      = logger;
      m_posMgr      = posMgr;
      m_tradeEngine = tradeEngine;
      m_riskEngine  = riskEngine;

      m_customCount = CUtils::ParseCsvDoubles(InpCustomLotSequence, m_customSequence);

      if(InpRecoveryMode == RECOVERY_CUSTOM_SEQUENCE && m_customCount == 0)
        {
         if(m_logger != NULL)
            m_logger.Warning("RecoveryEngine::Init - InpCustomLotSequence produced 0 valid values; will fall back to multiplier logic at runtime");
        }

      m_lastCycleCloseTime = 0;
      m_state = STATE_IDLE;
     }

   ENUM_TRADE_STATE GetState() const { return m_state; }

   //-----------------------------------------------------------------
   // True while the EA is deliberately waiting out the cooldown period
   // after a cycle closed, before starting a brand new cycle.
   //-----------------------------------------------------------------
   bool IsInCycleCooldown()
     {
      if(m_posMgr.HasOpenPositions())
         return false;
      if(m_lastCycleCloseTime == 0)
         return false;

      return (TimeCurrent() - m_lastCycleCloseTime) < InpRecoveryCooldownSec;
     }

   //-----------------------------------------------------------------
   // Internal helper: records the outcome of a just-closed cycle and
   // resets cooldown/state bookkeeping. Called after any full-basket
   // close (Basket TP or Emergency Close).
   //-----------------------------------------------------------------
   void OnCycleClosed(const double cycleProfit)
     {
      m_riskEngine.RegisterCycleResult(cycleProfit);
      m_lastCycleCloseTime = TimeCurrent();
      m_state = STATE_COOLDOWN;

      if(m_logger != NULL)
         m_logger.Info(StringFormat("RecoveryEngine - cycle closed. Net cycle profit=%.2f", cycleProfit));
     }

   //-----------------------------------------------------------------
   // STEP 1 (highest priority): forces a full close of every open
   // position if RiskEngine says an emergency threshold was breached.
   //-----------------------------------------------------------------
   bool ManageEmergencyClose()
     {
      if(!InpUseEmergencyClose)
         return false;

      if(!m_posMgr.HasOpenPositions())
         return false;

      string reason;
      if(!m_riskEngine.IsEmergencyCloseNeeded(reason))
         return false;

      double floatingAtClose = m_posMgr.GetFloatingProfit();

      ulong tickets[];
      m_posMgr.GetTicketsArray(tickets);

      bool ok = m_tradeEngine.CloseAllPositions(tickets);

      if(m_logger != NULL)
         m_logger.Warning("EMERGENCY CLOSE triggered: " + reason);

      m_state = STATE_EMERGENCY_CLOSED;

      if(ok)
         OnCycleClosed(floatingAtClose);

      return ok;
     }

   //-----------------------------------------------------------------
   // STEP 2: closes individual positions that have independently
   // reached their own Individual TP target, leaving the rest of the
   // basket untouched.
   //-----------------------------------------------------------------
   bool ManageIndividualTP()
     {
      if(!InpUseIndividualTP)
         return false;

      if(!m_posMgr.HasOpenPositions())
         return false;

      ulong tickets[];
      int count = m_posMgr.GetTicketsAtOrAboveProfit(InpIndividualTPUSD, tickets);

      if(count == 0)
         return false;

      bool anyClosed = false;
      for(int i = 0; i < count; i++)
        {
         if(m_tradeEngine.ClosePosition(tickets[i]))
            anyClosed = true;
        }

      return anyClosed;
     }

   //-----------------------------------------------------------------
   // STEP 3: closes the ENTIRE basket at once once total floating
   // profit across all open layers reaches the Basket TP target.
   //-----------------------------------------------------------------
   bool ManageBasketTP()
     {
      if(!InpUseBasketTP)
         return false;

      if(!m_posMgr.HasOpenPositions())
         return false;

      double floating = m_posMgr.GetFloatingProfit();
      if(floating < InpBasketTPUSD)
         return false;

      ulong tickets[];
      m_posMgr.GetTicketsArray(tickets);

      bool ok = m_tradeEngine.CloseAllPositions(tickets);

      if(m_logger != NULL)
         m_logger.Info(StringFormat("RecoveryEngine - Basket TP reached (%.2f >= %.2f), closing all layers", floating, InpBasketTPUSD));

      if(ok)
         OnCycleClosed(floating);

      return ok;
     }

   //-----------------------------------------------------------------
   // STEP 4: moves the Layer 0 (initial) position's stop loss to
   // break-even (+ lock points) once it reaches the BE trigger profit.
   //-----------------------------------------------------------------
   bool ManageBreakEven()
     {
      if(!InpUseBreakEven)
         return false;

      if(!m_posMgr.HasOpenPositions())
         return false;

      ulong tickets[];
      m_posMgr.GetTicketsArray(tickets);

      bool anyModified = false;

      for(int i = 0; i < ArraySize(tickets); i++)
        {
         ulong ticket = tickets[i];

         if(m_posMgr.GetTicketLayer(ticket) != 0)
            continue; // Break Even only applies to the initial layer

         if(!PositionSelectByTicket(ticket))
            continue;

         double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(profit < InpBreakEvenTriggerUSD)
            continue;

         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL  = PositionGetDouble(POSITION_SL);
         double currentTP  = PositionGetDouble(POSITION_TP);
         ENUM_TRADE_DIRECTION direction = m_posMgr.GetTicketDirection(ticket);

         double lockOffset = CUtils::PointsToPrice(m_symbol, InpBreakEvenLockPoints);
         double newSL;
         bool needsUpdate;

         if(direction == DIRECTION_BUY)
           {
            newSL = entryPrice + lockOffset;
            needsUpdate = (currentSL == 0.0 || currentSL < newSL);
           }
         else
           {
            newSL = entryPrice - lockOffset;
            needsUpdate = (currentSL == 0.0 || currentSL > newSL);
           }

         if(needsUpdate)
           {
            if(m_tradeEngine.ModifySLTP(ticket, newSL, currentTP))
               anyModified = true;
           }
        }

      return anyModified;
     }

   //-----------------------------------------------------------------
   // STEP 5: trails the Layer 0 (initial) position's stop loss once
   // it has moved favorably beyond the trailing start distance.
   //-----------------------------------------------------------------
   bool ManageTrailing()
     {
      if(!InpUseTrailingStop)
         return false;

      if(!m_posMgr.HasOpenPositions())
         return false;

      ulong tickets[];
      m_posMgr.GetTicketsArray(tickets);

      bool anyModified = false;

      for(int i = 0; i < ArraySize(tickets); i++)
        {
         ulong ticket = tickets[i];

         if(m_posMgr.GetTicketLayer(ticket) != 0)
            continue; // Trailing only applies to the initial layer

         if(!PositionSelectByTicket(ticket))
            continue;

         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL  = PositionGetDouble(POSITION_SL);
         double currentTP  = PositionGetDouble(POSITION_TP);
         ENUM_TRADE_DIRECTION direction = m_posMgr.GetTicketDirection(ticket);

         double startOffset = CUtils::PointsToPrice(m_symbol, InpTrailingStartPoints);
         double stepOffset  = CUtils::PointsToPrice(m_symbol, InpTrailingStepPoints);

         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

         if(direction == DIRECTION_BUY)
           {
            double profitDistance = bid - entryPrice;
            if(profitDistance < startOffset)
               continue;

            double newSL = bid - stepOffset;
            bool needsUpdate = (currentSL == 0.0 || newSL > currentSL);

            if(needsUpdate)
              {
               if(m_tradeEngine.ModifySLTP(ticket, newSL, currentTP))
                  anyModified = true;
              }
           }
         else
           {
            double profitDistance = entryPrice - ask;
            if(profitDistance < startOffset)
               continue;

            double newSL = ask + stepOffset;
            bool needsUpdate = (currentSL == 0.0 || newSL < currentSL);

            if(needsUpdate)
              {
               if(m_tradeEngine.ModifySLTP(ticket, newSL, currentTP))
                  anyModified = true;
              }
           }
        }

      return anyModified;
     }

   //-----------------------------------------------------------------
   // STEP 6: opens the NEXT recovery layer if the current basket has
   // floated into a large enough loss, respecting max layers, cooldown
   // between layers, and all RiskEngine guards. The new layer always
   // opens in the OPPOSITE direction of the most recently opened layer
   // (the core hedge-recovery mechanic), with a lot size determined
   // by the configured Recovery Mode.
   //-----------------------------------------------------------------
   bool ManageRecoveryLayers()
     {
      if(!m_posMgr.HasOpenPositions())
         return false;

      int layerCount = m_posMgr.GetLayerCount();

      if(InpMaxLayers > 0 && layerCount >= InpMaxLayers)
         return false; // already at cap, no duplicate recovery

      double floating = m_posMgr.GetFloatingProfit();
      if(floating > -InpRecoveryTriggerUSD)
         return false; // not enough floating loss yet to justify recovery

      datetime lastOpenTime = m_posMgr.GetLastLayerOpenTime();
      if((TimeCurrent() - lastOpenTime) < InpRecoveryCooldownSec)
         return false; // still within cooldown since the last layer was opened

      string reason;
      if(!m_riskEngine.IsNewLayerAllowed(reason))
        {
         if(m_logger != NULL)
            m_logger.Warning("RecoveryEngine - recovery layer blocked by RiskEngine: " + reason);
         return false;
        }

      ENUM_TRADE_DIRECTION lastDirection = m_posMgr.GetLastLayerDirection();
      ENUM_TRADE_DIRECTION newDirection  = (lastDirection == DIRECTION_BUY) ? DIRECTION_SELL : DIRECTION_BUY;

      double lastLot = m_posMgr.GetLastLayerLot();
      double nextLot = ComputeNextLot(layerCount, lastLot);

      ulong newTicket;
      bool ok = m_tradeEngine.OpenPosition(newDirection, nextLot, layerCount, newTicket);

      if(ok)
        {
         m_state = STATE_RECOVERY_ACTIVE;
         if(m_logger != NULL)
            m_logger.Info(StringFormat("RecoveryEngine - opened recovery layer %d, direction=%s, lot=%.2f",
                           layerCount, (newDirection == DIRECTION_BUY) ? "BUY" : "SELL", nextLot));
        }

      return ok;
     }

   //-----------------------------------------------------------------
   // STEP 7: opens the very first position (Layer 0) of a brand new
   // cycle, given a confirmed direction from SignalEngine. Only fires
   // when no positions are currently open, the EA isn't paused by
   // consecutive losses, cooldown has elapsed, and RiskEngine allows it.
   //-----------------------------------------------------------------
   bool TryOpenInitialPosition(const ENUM_TRADE_DIRECTION direction)
     {
      if(direction == DIRECTION_NONE)
         return false;

      if(m_posMgr.HasOpenPositions())
         return false; // a cycle is already active

      if(!InpAllowNewCycles && m_lastCycleCloseTime > 0)
         return false; // one-shot mode: only ever run a single cycle

      if(m_riskEngine.IsPausedByConsecutiveLosses())
        {
         m_state = STATE_PAUSED_RISK;
         if(m_logger != NULL)
            m_logger.Debug("RecoveryEngine - new cycle blocked, paused due to consecutive losses");
         return false;
        }

      if(IsInCycleCooldown())
         return false;

      string reason;
      if(!m_riskEngine.IsNewLayerAllowed(reason))
        {
         if(m_logger != NULL)
            m_logger.Warning("RecoveryEngine - initial entry blocked by RiskEngine: " + reason);
         return false;
        }

      ulong newTicket;
      bool ok = m_tradeEngine.OpenPosition(direction, InpBaseLot, 0, newTicket);

      if(ok)
        {
         m_state = STATE_INITIAL_OPEN;
         if(m_logger != NULL)
            m_logger.Info(StringFormat("RecoveryEngine - opened NEW CYCLE, direction=%s, lot=%.2f",
                           (direction == DIRECTION_BUY) ? "BUY" : "SELL", InpBaseLot));
        }

      return ok;
     }
  };

#endif // __GHR_RECOVERYENGINE_MQH__
