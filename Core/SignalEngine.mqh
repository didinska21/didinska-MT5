//+------------------------------------------------------------------+
//|                                                SignalEngine.mqh  |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Produces the single, final INITIAL ENTRY signal (layer 0       |
//|   only) by combining:                                            |
//|     1) Raw direction from Entry Mode (Wait Cross / Current Trend)|
//|     2) Trend confirmation (EMA200/SMA200/MTF via CTrendFilter)   |
//|     3) ATR volatility gate                                       |
//|     4) Spread gate                                               |
//|     5) Session gate                                              |
//|     6) Candle body size gate                                     |
//|                                                                  |
//|   Only fires once per new closed bar (internal de-duplication)   |
//|   to avoid re-triggering the same signal multiple times while    |
//|   the bar is still forming.                                       |
//+------------------------------------------------------------------+
#ifndef __GHR_SIGNALENGINE_MQH__
#define __GHR_SIGNALENGINE_MQH__

#include "../Config/Inputs.mqh"
#include "Logger.mqh"
#include "Utils.mqh"
#include "SessionManager.mqh"
#include "../Indicators/EMAFilter.mqh"
#include "../Indicators/ATRFilter.mqh"
#include "../Indicators/TrendFilter.mqh"

//====================================================================
// CLASS: CSignalEngine
//====================================================================
class CSignalEngine
  {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_timeframe;
   CLogger         *m_logger;

   CEMAFilter       m_entryEma;      // Used for either cross-pair or trend-bias, depending on InpEntryMode
   CATRFilter       m_atrFilter;
   CTrendFilter     m_trendFilter;
   CSessionManager *m_sessionMgr;    // Shared instance owned by the main EA (not owned here)

   datetime         m_lastSignalBarTime;

   //-----------------------------------------------------------------
   bool CheckSpread()
     {
      if(!InpUseSpreadFilter)
         return true;

      double spreadPoints = CUtils::GetSpreadPoints(m_symbol);
      bool ok = (spreadPoints <= InpMaxSpreadPoints);

      if(!ok && m_logger != NULL)
         m_logger.Debug(StringFormat("SignalEngine - blocked by spread filter (%.1f > %.1f pts)", spreadPoints, InpMaxSpreadPoints));

      return ok;
     }

   //-----------------------------------------------------------------
   bool CheckCandleBody()
     {
      if(!InpUseCandleFilter)
         return true;

      double openPrice  = iOpen(m_symbol, m_timeframe, 1);
      double closePrice = iClose(m_symbol, m_timeframe, 1);
      double bodyPoints = CUtils::PriceToPoints(m_symbol, MathAbs(closePrice - openPrice));

      bool ok = (bodyPoints >= InpMinCandleBodyPoints);

      if(!ok && m_logger != NULL)
         m_logger.Debug(StringFormat("SignalEngine - blocked by candle body filter (%.1f < %.1f pts)", bodyPoints, InpMinCandleBodyPoints));

      return ok;
     }

   //-----------------------------------------------------------------
   // ENTRY_SCALP_CANDLE: direction is simply the color of the last
   // CLOSED candle (bullish close>open -> BUY, bearish -> SELL).
   // No indicator required - this fires on almost every new bar,
   // by design, for a "always look for an entry" scalping style.
   //-----------------------------------------------------------------
   bool GetScalpCandleDirection(ENUM_TRADE_DIRECTION &outDirection)
     {
      outDirection = DIRECTION_NONE;

      double openPrice  = iOpen(m_symbol, m_timeframe, 1);
      double closePrice = iClose(m_symbol, m_timeframe, 1);

      if(openPrice <= 0.0 || closePrice <= 0.0)
         return false;

      if(closePrice > openPrice)
         outDirection = DIRECTION_BUY;
      else if(closePrice < openPrice)
         outDirection = DIRECTION_SELL;
      else
         outDirection = DIRECTION_NONE; // perfectly flat doji, skip

      return true;
     }

   //-----------------------------------------------------------------
   // Returns true only the FIRST time this is called for a given
   // closed-bar timestamp, preventing duplicate signals within the
   // same bar.
   //-----------------------------------------------------------------
   bool IsNewBar()
     {
      datetime barTime = iTime(m_symbol, m_timeframe, 1);
      if(barTime == 0)
         return false;

      if(barTime == m_lastSignalBarTime)
         return false;

      return true;
     }

public:
   CSignalEngine()
     {
      m_logger            = NULL;
      m_sessionMgr        = NULL;
      m_timeframe         = PERIOD_CURRENT;
      m_lastSignalBarTime = 0;
     }

   //-----------------------------------------------------------------
   // sessionMgr is a pointer to an already-initialized CSessionManager
   // owned by the main EA (shared, not duplicated here).
   //-----------------------------------------------------------------
   bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, CLogger *logger, CSessionManager *sessionMgr)
     {
      m_symbol     = symbol;
      m_timeframe  = timeframe;
      m_logger     = logger;
      m_sessionMgr = sessionMgr;

      bool ok = true;

      if(InpEntryMode == ENTRY_WAIT_CROSS)
        {
         if(!m_entryEma.InitCrossPair(symbol, timeframe, InpEmaFastPeriod, InpEmaSlowPeriod, logger))
           {
            if(m_logger != NULL)
               m_logger.Error("CSignalEngine::Init failed - EMA cross pair init error");
            ok = false;
           }
        }
      else if(InpEntryMode == ENTRY_CURRENT_TREND)
        {
         if(!m_entryEma.InitTrendEma(symbol, timeframe, InpTrendEmaPeriod, logger))
           {
            if(m_logger != NULL)
               m_logger.Error("CSignalEngine::Init failed - trend EMA init error");
            ok = false;
           }
        }
      // ENTRY_SCALP_CANDLE requires no indicator handle - direction comes
      // straight from candle open/close, nothing to initialize here.

      if(InpUseAtrFilter)
        {
         if(!m_atrFilter.Init(symbol, timeframe, InpAtrPeriod, logger))
           {
            if(m_logger != NULL)
               m_logger.Error("CSignalEngine::Init failed - ATR filter init error");
            ok = false;
           }
        }

      if(!m_trendFilter.Init(symbol, timeframe, logger))
        {
         if(m_logger != NULL)
            m_logger.Error("CSignalEngine::Init failed - TrendFilter init error");
         ok = false;
        }

      return ok;
     }

   void Release()
     {
      m_entryEma.Release();
      m_atrFilter.Release();
      m_trendFilter.Release();
     }

   //-----------------------------------------------------------------
   // Main entry point, called every OnTick() by the main EA. Returns
   // true and sets outDirection ONLY when a fully-confirmed, brand
   // new entry signal is available on the just-closed bar.
   //-----------------------------------------------------------------
   bool TryGetEntrySignal(ENUM_TRADE_DIRECTION &outDirection)
     {
      outDirection = DIRECTION_NONE;

      if(!IsNewBar())
         return false;

      //--- Step 1: raw direction from entry mode
      ENUM_TRADE_DIRECTION rawDirection = DIRECTION_NONE;

      if(InpEntryMode == ENTRY_WAIT_CROSS)
        {
         if(!m_entryEma.DetectCross(rawDirection))
            return false; // data not ready yet, don't consume the bar slot
        }
      else if(InpEntryMode == ENTRY_CURRENT_TREND)
        {
         if(!m_entryEma.GetTrendBias(rawDirection))
            return false;
        }
      else // ENTRY_SCALP_CANDLE
        {
         if(!GetScalpCandleDirection(rawDirection))
            return false;
        }

      if(rawDirection == DIRECTION_NONE)
        {
         m_lastSignalBarTime = iTime(m_symbol, m_timeframe, 1);
         return false;
        }

      //--- From here on, a candidate direction exists — mark bar as processed
      //--- regardless of outcome, so we never re-evaluate this bar again.
      m_lastSignalBarTime = iTime(m_symbol, m_timeframe, 1);

      //--- Step 2: trend confirmation (EMA200 / SMA200 / MTF)
      bool trendConfirmed;
      if(!m_trendFilter.Confirm(rawDirection, trendConfirmed) || !trendConfirmed)
        {
         if(m_logger != NULL)
            m_logger.Debug("SignalEngine - signal rejected by TrendFilter");
         return false;
        }

      //--- Step 3: ATR volatility gate
      if(InpUseAtrFilter)
        {
         double atrPoints;
         if(!m_atrFilter.IsVolatilityAcceptable(InpAtrMinPoints, InpAtrMaxPoints, atrPoints))
           {
            if(m_logger != NULL)
               m_logger.Debug("SignalEngine - signal rejected by ATR filter");
            return false;
           }
        }

      //--- Step 4: spread gate
      if(!CheckSpread())
         return false;

      //--- Step 5: session gate
      if(m_sessionMgr != NULL && !m_sessionMgr.IsTradingAllowed())
        {
         if(m_logger != NULL)
            m_logger.Debug("SignalEngine - signal rejected by session filter");
         return false;
        }

      //--- Step 6: candle body gate
      if(!CheckCandleBody())
         return false;

      //--- All gates passed
      outDirection = rawDirection;

      if(m_logger != NULL)
         m_logger.Info(StringFormat("SignalEngine - CONFIRMED entry signal: %s",
                        (outDirection == DIRECTION_BUY) ? "BUY" : "SELL"));

      return true;
     }
  };

#endif // __GHR_SIGNALENGINE_MQH__
