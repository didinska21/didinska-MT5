//+------------------------------------------------------------------+
//|                                                    RiskEngine.mqh|
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   The EA's "brake pedal". Owns every quantitative risk guard     |
//|   and answers two questions for the rest of the system:          |
//|     1) IsNewLayerAllowed()     - safe to open another layer?     |
//|     2) IsEmergencyCloseNeeded() - must we close everything NOW?  |
//|                                                                  |
//|   Also tracks consecutive losing cycles to allow a temporary     |
//|   trading pause, independent of the hard emergency-close guards. |
//+------------------------------------------------------------------+
#ifndef __GHR_RISKENGINE_MQH__
#define __GHR_RISKENGINE_MQH__

#include "../Config/Inputs.mqh"
#include "Logger.mqh"
#include "Utils.mqh"
#include "PositionManager.mqh"

//====================================================================
// CLASS: CRiskEngine
//====================================================================
class CRiskEngine
  {
private:
   CLogger          *m_logger;
   CPositionManager *m_posMgr;

   double   m_dayStartBalance;
   int      m_currentDayOfYear;
   int      m_currentYear;

   double   m_peakEquity;
   int      m_consecutiveLosses;

   double   m_startingBalance;   // Balance snapshot taken once at EA Init() - used only for Profit Target Stop
   bool     m_targetReached;     // Latched true once the profit target has been hit (persists until EA restart)

   //-----------------------------------------------------------------
   void CheckDayRollover()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      if(dt.day_of_year != m_currentDayOfYear || dt.year != m_currentYear)
        {
         m_currentDayOfYear = dt.day_of_year;
         m_currentYear      = dt.year;
         m_dayStartBalance  = AccountInfoDouble(ACCOUNT_BALANCE);

         if(m_logger != NULL)
            m_logger.Info(StringFormat("RiskEngine - new trading day, daily loss counter reset. Balance=%.2f", m_dayStartBalance));
        }
     }

public:
   CRiskEngine()
     {
      m_logger            = NULL;
      m_posMgr            = NULL;
      m_dayStartBalance   = 0.0;
      m_currentDayOfYear  = -1;
      m_currentYear       = -1;
      m_peakEquity        = 0.0;
      m_consecutiveLosses = 0;
      m_startingBalance   = 0.0;
      m_targetReached     = false;
     }

   //-----------------------------------------------------------------
   void Init(CPositionManager *posMgr, CLogger *logger)
     {
      m_posMgr = posMgr;
      m_logger = logger;

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      m_currentDayOfYear = dt.day_of_year;
      m_currentYear      = dt.year;

      m_dayStartBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
      m_peakEquity        = AccountInfoDouble(ACCOUNT_EQUITY);
      m_consecutiveLosses = 0;

      m_startingBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
      m_targetReached     = false;

      if(InpUseProfitTarget && m_logger != NULL)
        {
         double targetEquity = m_startingBalance * (1.0 + InpProfitTargetPercent / 100.0);
         m_logger.Info(StringFormat("RiskEngine - Profit Target Stop ENABLED. Start balance=%.2f, Target equity=%.2f (+%.1f%%)",
                        m_startingBalance, targetEquity, InpProfitTargetPercent));
        }
     }

   //-----------------------------------------------------------------
   // Must be called once per tick (before any guard check) to keep
   // daily/peak-equity tracking accurate.
   //-----------------------------------------------------------------
   void OnTick()
     {
      CheckDayRollover();

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > m_peakEquity)
         m_peakEquity = equity;
     }

   //-----------------------------------------------------------------
   // Returns true if it is currently safe to open ANOTHER layer
   // (initial entry OR recovery layer). reason is filled with a
   // human-readable explanation when returning false.
   //-----------------------------------------------------------------
   bool IsNewLayerAllowed(string &reason)
     {
      reason = "";

      if(m_posMgr == NULL)
        {
         reason = "PositionManager not attached";
         return false;
        }

      if(InpUseMaxTotalLot && m_posMgr.GetTotalLot() >= InpMaxTotalLot)
        {
         reason = StringFormat("Max total lot reached (%.2f >= %.2f)", m_posMgr.GetTotalLot(), InpMaxTotalLot);
         return false;
        }

      if(InpMaxLayers > 0 && m_posMgr.GetLayerCount() >= InpMaxLayers)
        {
         reason = StringFormat("Max layers reached (%d >= %d)", m_posMgr.GetLayerCount(), InpMaxLayers);
         return false;
        }

      if(InpUseFreeMarginGuard)
        {
         double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         if(freeMargin < InpMinFreeMarginUSD)
           {
            reason = StringFormat("Free margin too low (%.2f < %.2f)", freeMargin, InpMinFreeMarginUSD);
            return false;
           }
        }

      if(InpUseMarginLevelGuard)
        {
         double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
         // marginLevel == 0 typically means no positions/margin used yet - not a breach
         if(marginLevel > 0.0 && marginLevel < InpMinMarginLevelPercent)
           {
            reason = StringFormat("Margin level too low (%.1f%% < %.1f%%)", marginLevel, InpMinMarginLevelPercent);
            return false;
           }
        }

      return true;
     }

   //-----------------------------------------------------------------
   // Returns true if an emergency close must happen RIGHT NOW.
   // reason is filled with which guard was breached.
   //-----------------------------------------------------------------
   bool IsEmergencyCloseNeeded(string &reason)
     {
      reason = "";

      if(m_posMgr == NULL || !m_posMgr.HasOpenPositions())
         return false;

      if(InpUseMaxFloatingLoss)
        {
         double floating = m_posMgr.GetFloatingProfit();
         if(floating <= -InpMaxFloatingLossUSD)
           {
            reason = StringFormat("Max floating loss breached (%.2f <= -%.2f)", floating, InpMaxFloatingLossUSD);
            return true;
           }
        }

      if(InpUseMaxDailyLoss)
        {
         double dailyPnL = AccountInfoDouble(ACCOUNT_BALANCE) - m_dayStartBalance;
         if(dailyPnL <= -InpMaxDailyLossUSD)
           {
            reason = StringFormat("Max daily loss breached (%.2f <= -%.2f)", dailyPnL, InpMaxDailyLossUSD);
            return true;
           }
        }

      if(InpUseMaxDrawdown)
        {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double ddPercent = CUtils::SafeDivide((m_peakEquity - equity) * 100.0, m_peakEquity, 0.0);
         if(ddPercent >= InpMaxDrawdownPercent)
           {
            reason = StringFormat("Max drawdown breached (%.1f%% >= %.1f%%)", ddPercent, InpMaxDrawdownPercent);
            return true;
           }
        }

      return false;
     }

   //-----------------------------------------------------------------
   // Returns true once account equity has reached the configured
   // profit target relative to the balance recorded at EA startup.
   // Once latched true, stays true for the rest of this EA session
   // (a permanent stop, not a cooldown) — the intent of a profit
   // target is "we're done, lock in the win", not "pause and retry".
   //-----------------------------------------------------------------
   bool IsProfitTargetReached()
     {
      if(!InpUseProfitTarget)
         return false;

      if(m_targetReached)
         return true; // already latched, no need to recheck

      double targetEquity = m_startingBalance * (1.0 + InpProfitTargetPercent / 100.0);
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(currentEquity >= targetEquity)
        {
         m_targetReached = true;
         if(m_logger != NULL)
            m_logger.Info(StringFormat("RiskEngine - PROFIT TARGET REACHED! Equity=%.2f >= Target=%.2f",
                           currentEquity, targetEquity));
        }

      return m_targetReached;
     }

   //-----------------------------------------------------------------
   // Should new cycles (initial entries) be paused due to too many
   // consecutive losing cycles?
   //-----------------------------------------------------------------
   bool IsPausedByConsecutiveLosses()
     {
      if(!InpUseMaxConsecLosses)
         return false;

      return (m_consecutiveLosses >= InpMaxConsecutiveLosses);
     }

   //-----------------------------------------------------------------
   // Called by RecoveryEngine whenever a full cycle (basket) closes,
   // whether via Basket TP, all-individual-closes, or emergency close.
   //-----------------------------------------------------------------
   void RegisterCycleResult(const double cycleProfit)
     {
      if(cycleProfit < 0.0)
        {
         m_consecutiveLosses++;
         if(m_logger != NULL)
            m_logger.Warning(StringFormat("RiskEngine - losing cycle registered. Consecutive losses = %d", m_consecutiveLosses));
        }
      else
        {
         if(m_consecutiveLosses > 0 && m_logger != NULL)
            m_logger.Info("RiskEngine - winning cycle registered, consecutive loss counter reset");
         m_consecutiveLosses = 0;
        }
     }

   //-----------------------------------------------------------------
   // Manual reset, exposed in case the user wants to clear the pause
   // state without restarting the EA (e.g. via a future chart button).
   //-----------------------------------------------------------------
   void ResetConsecutiveLosses()
     {
      m_consecutiveLosses = 0;
     }

   //-----------------------------------------------------------------
   // Getters for Dashboard display
   //-----------------------------------------------------------------
   double GetDailyPnL()          { return AccountInfoDouble(ACCOUNT_BALANCE) - m_dayStartBalance; }
   double GetDrawdownPercent()   { return CUtils::SafeDivide((m_peakEquity - AccountInfoDouble(ACCOUNT_EQUITY)) * 100.0, m_peakEquity, 0.0); }
   int    GetConsecutiveLosses() const { return m_consecutiveLosses; }
   double GetPeakEquity()        const { return m_peakEquity; }
   double GetStartingBalance()   const { return m_startingBalance; }
   bool   IsTargetLatched()      const { return m_targetReached; }
  };

#endif // __GHR_RISKENGINE_MQH__
