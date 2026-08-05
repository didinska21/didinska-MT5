//+------------------------------------------------------------------+
//|                                          GoldHedgeRecovery.mq5   |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| Main EA entry point. Wires together every module and drives the |
//| per-tick execution order. Contains NO trading logic of its own — |
//| every decision is delegated to the appropriate engine so this    |
//| file stays thin, readable, and easy to extend.                   |
//|                                                                  |
//| TICK EXECUTION ORDER:                                            |
//|   1. RiskEngine.OnTick()            - refresh day/peak tracking  |
//|   2. PositionManager.Refresh()      - rebuild live position cache|
//|   3. RecoveryEngine.ManageEmergencyClose()                        |
//|   4. RecoveryEngine.ManageIndividualTP()                          |
//|   5. RecoveryEngine.ManageBasketTP()                              |
//|   6. RecoveryEngine.ManageBreakEven()                             |
//|   7. RecoveryEngine.ManageTrailing()                              |
//|   8. RecoveryEngine.ManageRecoveryLayers()                        |
//|   9. SignalEngine.TryGetEntrySignal() -> RecoveryEngine.TryOpenInitialPosition() |
//|  10. Dashboard.Update()                                           |
//+------------------------------------------------------------------+
#property copyright "GoldHedgeRecovery EA"
#property version   "1.00"
#property strict

#include "Config/Inputs.mqh"
#include "Core/Utils.mqh"
#include "Core/Logger.mqh"
#include "Core/SessionManager.mqh"
#include "Indicators/SMAEngine.mqh"
#include "Indicators/EMAFilter.mqh"
#include "Indicators/ATRFilter.mqh"
#include "Indicators/TrendFilter.mqh"
#include "Core/SignalEngine.mqh"
#include "Core/TradeEngine.mqh"
#include "Core/PositionManager.mqh"
#include "Core/RiskEngine.mqh"
#include "Core/RecoveryEngine.mqh"
#include "Core/Dashboard.mqh"

//====================================================================
// GLOBAL MODULE INSTANCES
//====================================================================
CLogger           g_logger;
CSessionManager   g_sessionMgr;
CSignalEngine     g_signalEngine;
CTradeEngine      g_tradeEngine;
CPositionManager  g_positionMgr;
CRiskEngine       g_riskEngine;
CRecoveryEngine   g_recoveryEngine;
CDashboard        g_dashboard;

// Extra indicator instances kept at EA level purely for Dashboard display
// (SignalEngine has its own internal instances used for trading decisions;
// these are separate read-only instances so the dashboard never affects
// trading logic).
CATRFilter        g_dashAtr;
CEMAFilter        g_dashTrendEma;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_logger.Init();
   g_logger.Info("GoldHedgeRecovery EA - initializing...");

   //--- Basic sanity checks on critical inputs
   if(InpBaseLot <= 0.0)
     {
      g_logger.Error("OnInit failed - InpBaseLot must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpMaxLayers <= 0)
     {
      g_logger.Error("OnInit failed - InpMaxLayers must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   long accountMarginMode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(accountMarginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      g_logger.Warning("OnInit - account is NOT in Hedging mode. This EA is designed for hedging accounts; "
                        "behavior on netting accounts is unsupported and may not match the intended strategy.");
     }

   string symbol = _Symbol;
   ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT;

   //--- Init order matters: dependencies first
   g_sessionMgr.Init(&g_logger);

   if(!g_signalEngine.Init(symbol, timeframe, &g_logger, &g_sessionMgr))
     {
      g_logger.Error("OnInit failed - SignalEngine initialization error");
      return INIT_FAILED;
     }

   g_tradeEngine.Init(symbol, &g_logger);
   g_positionMgr.Init(symbol, InpMagicNumber, InpTradeComment, &g_logger);
   g_riskEngine.Init(&g_positionMgr, &g_logger);
   g_recoveryEngine.Init(symbol, &g_logger, &g_positionMgr, &g_tradeEngine, &g_riskEngine);

   //--- Dashboard-only indicator instances (read-only, informational)
   if(!g_dashAtr.Init(symbol, timeframe, InpAtrPeriod, &g_logger))
      g_logger.Warning("OnInit - dashboard ATR instance failed to init (dashboard ATR value may show 0)");

   if(!g_dashTrendEma.InitTrendEma(symbol, timeframe, InpTrendEmaPeriod, &g_logger))
      g_logger.Warning("OnInit - dashboard trend EMA instance failed to init (dashboard trend may show N/A)");

   g_dashboard.Init();

   g_logger.Info(StringFormat("GoldHedgeRecovery EA initialized successfully on %s, Magic=%d", symbol, InpMagicNumber));

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_logger.Info(StringFormat("GoldHedgeRecovery EA deinitializing. Reason code=%d", reason));

   g_signalEngine.Release();
   g_dashAtr.Release();
   g_dashTrendEma.Release();
   g_dashboard.Deinit();
   g_logger.Deinit();
  }

//+------------------------------------------------------------------+
//| Builds a human-readable trend string for the dashboard only.     |
//| Purely informational - has no effect on trading decisions.       |
//+------------------------------------------------------------------+
string GetDashboardTrendText()
  {
   ENUM_TRADE_DIRECTION bias;
   if(!g_dashTrendEma.GetTrendBias(bias))
      return "N/A";

   if(bias == DIRECTION_BUY)
      return "BULLISH";
   if(bias == DIRECTION_SELL)
      return "BEARISH";
   return "NEUTRAL";
  }

//+------------------------------------------------------------------+
//| Builds a human-readable recovery-mode string for the dashboard.  |
//+------------------------------------------------------------------+
string GetRecoveryModeText()
  {
   switch(InpRecoveryMode)
     {
      case RECOVERY_FIXED_LOT:       return "Fixed Lot";
      case RECOVERY_MULTIPLIER:      return StringFormat("Multiplier x%.2f", InpRecoveryMultiplier);
      case RECOVERY_CUSTOM_SEQUENCE: return "Custom Sequence";
      default:                       return "Unknown";
     }
  }

//+------------------------------------------------------------------+
//| Builds a human-readable EA state string for the dashboard.       |
//+------------------------------------------------------------------+
string GetStateText()
  {
   ENUM_TRADE_STATE state = g_recoveryEngine.GetState();

   // Override with live baseline state when a cycle is actively open,
   // since RecoveryEngine's stored m_state may lag by one tick right
   // after a fresh initial entry.
   if(g_positionMgr.HasOpenPositions())
      state = g_positionMgr.DetermineBaselineState();
   else if(g_recoveryEngine.IsInCycleCooldown())
      state = STATE_COOLDOWN;

   switch(state)
     {
      case STATE_IDLE:             return "IDLE";
      case STATE_INITIAL_OPEN:     return "INITIAL_OPEN";
      case STATE_RECOVERY_ACTIVE:  return "RECOVERY_ACTIVE";
      case STATE_EMERGENCY_CLOSED: return "EMERGENCY_CLOSED";
      case STATE_COOLDOWN:         return "COOLDOWN";
      case STATE_PAUSED_RISK:      return "PAUSED (Consecutive Losses)";
      default:                     return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//| Refreshes and renders the on-chart dashboard.                    |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowDashboard)
      return;

   SDashboardData data;

   data.trendText       = GetDashboardTrendText();

   double atrPoints = 0.0;
   g_dashAtr.GetValuePoints(1, atrPoints);
   data.atrPoints       = atrPoints;

   data.spreadPoints    = CUtils::GetSpreadPoints(_Symbol);
   data.sessionOk       = g_sessionMgr.IsTradingAllowed();
   data.stateText       = GetStateText();
   data.layerCount      = g_positionMgr.GetLayerCount();
   data.floatingProfit  = g_positionMgr.GetFloatingProfit();
   data.equity          = AccountInfoDouble(ACCOUNT_EQUITY);
   data.balance         = AccountInfoDouble(ACCOUNT_BALANCE);
   data.marginLevel     = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   data.recoveryModeText= GetRecoveryModeText();
   data.totalLots       = g_positionMgr.GetTotalLot();

   g_dashboard.Update(data);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1. Refresh risk tracking (daily rollover, peak equity)
   g_riskEngine.OnTick();

   //--- 2. Rebuild live position/layer cache - EVERYTHING below this
   //---    line depends on this being current for this tick.
   g_positionMgr.Refresh();

   //--- 3. Highest priority: emergency close overrides everything else
   if(g_recoveryEngine.ManageEmergencyClose())
     {
      UpdateDashboard();
      return; // basket just force-closed this tick, nothing else to do
     }

   //--- 4. Individual TP - close any single layer that hit its own target
   g_recoveryEngine.ManageIndividualTP();

   //--- 5. Basket TP - close the whole basket if total target reached
   if(g_recoveryEngine.ManageBasketTP())
     {
      UpdateDashboard();
      return; // cycle just completed, skip further management this tick
     }

   //--- 6. Break Even management on the initial layer
   g_recoveryEngine.ManageBreakEven();

   //--- 7. Trailing Stop management on the initial layer
   g_recoveryEngine.ManageTrailing();

   //--- 8. Open next recovery layer if conditions are met
   g_recoveryEngine.ManageRecoveryLayers();

   //--- 9. Look for a brand new entry signal (only acts if no cycle is active)
   ENUM_TRADE_DIRECTION entryDirection;
   if(g_signalEngine.TryGetEntrySignal(entryDirection))
     {
      g_recoveryEngine.TryOpenInitialPosition(entryDirection);
     }

   //--- 10. Refresh dashboard display
   UpdateDashboard();
  }
//+------------------------------------------------------------------+
