//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|                                    GoldHedgeRecovery EA v1.0     |
//|                                                                  |
//| PURPOSE:                                                        |
//|   Renders a lightweight on-chart status panel using native       |
//|   OBJ_LABEL/OBJ_RECTANGLE_LABEL objects (no external libraries). |
//|   Purely presentational — reads data handed to it by the main    |
//|   EA each tick via Update(); it has no trading logic of its own. |
//+------------------------------------------------------------------+
#ifndef __GHR_DASHBOARD_MQH__
#define __GHR_DASHBOARD_MQH__

#include "../Config/Inputs.mqh"

//====================================================================
// STRUCT: SDashboardData
// Snapshot of everything the dashboard needs to render one frame.
// Populated by the main EA each tick from the various engines.
//====================================================================
struct SDashboardData
  {
   string   trendText;      // e.g. "BULLISH" / "BEARISH" / "NEUTRAL"
   double   atrPoints;
   double   spreadPoints;
   bool     sessionOk;
   string   stateText;      // e.g. "IDLE" / "RECOVERY_ACTIVE" / "COOLDOWN"
   int      layerCount;
   double   floatingProfit;
   double   equity;
   double   balance;
   double   marginLevel;
   string   recoveryModeText;
   double   totalLots;
  };

//====================================================================
// CLASS: CDashboard
//====================================================================
class CDashboard
  {
private:
   bool     m_enabled;
   string   m_prefix;
   int      m_x;
   int      m_y;
   color    m_textColor;
   color    m_bgColor;
   int      m_fontSize;
   int      m_lineHeight;
   int      m_lineCount;

   //-----------------------------------------------------------------
   string LabelName(const string key)
     {
      return m_prefix + "_" + key;
     }

   //-----------------------------------------------------------------
   void CreateLabel(const string key, const int line)
     {
      string name = LabelName(key);

      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_y + (line * m_lineHeight));
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, m_fontSize);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_COLOR, m_textColor);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
        }
     }

   //-----------------------------------------------------------------
   void CreateBackground()
     {
      string name = LabelName("bg");

      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x - 6);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_y - 6);
         ObjectSetInteger(0, name, OBJPROP_XSIZE, 260);
         ObjectSetInteger(0, name, OBJPROP_YSIZE, (m_lineCount * m_lineHeight) + 12);
         ObjectSetInteger(0, name, OBJPROP_BGCOLOR, m_bgColor);
         ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
        }
     }

   //-----------------------------------------------------------------
   void SetText(const string key, const string text)
     {
      string name = LabelName(key);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
     }

public:
   CDashboard()
     {
      m_enabled    = true;
      m_prefix     = "GHR_Dash";
      m_x          = 10;
      m_y          = 20;
      m_textColor  = clrWhite;
      m_bgColor    = clrBlack;
      m_fontSize   = 9;
      m_lineHeight = 15;
      m_lineCount  = 13;
     }

   //-----------------------------------------------------------------
   void Init()
     {
      m_enabled   = InpShowDashboard;
      m_x         = InpDashboardX;
      m_y         = InpDashboardY;
      m_textColor = InpDashboardColor;
      m_bgColor   = InpDashboardBgColor;
      m_fontSize  = InpDashboardFontSize;

      if(!m_enabled)
         return;

      CreateBackground();

      CreateLabel("title",    0);
      CreateLabel("state",    1);
      CreateLabel("trend",    2);
      CreateLabel("atr",      3);
      CreateLabel("spread",   4);
      CreateLabel("session",  5);
      CreateLabel("layer",    6);
      CreateLabel("recovery", 7);
      CreateLabel("lots",     8);
      CreateLabel("floating", 9);
      CreateLabel("equity",   10);
      CreateLabel("balance",  11);
      CreateLabel("margin",   12);

      SetText("title", "== GoldHedgeRecovery EA ==");
     }

   //-----------------------------------------------------------------
   // Removes all dashboard objects. Must be called from OnDeinit().
   //-----------------------------------------------------------------
   void Deinit()
     {
      ObjectsDeleteAll(0, m_prefix);
     }

   //-----------------------------------------------------------------
   // Refreshes all label text with the latest data snapshot. Cheap
   // enough to call every tick (only updates text properties of
   // already-created objects, does not recreate them).
   //-----------------------------------------------------------------
   void Update(const SDashboardData &data)
     {
      if(!m_enabled)
         return;

      color floatingColor = (data.floatingProfit >= 0.0) ? clrLime : clrTomato;

      SetText("state",    "State     : " + data.stateText);
      SetText("trend",    "Trend     : " + data.trendText);
      SetText("atr",      StringFormat("ATR       : %.1f pts", data.atrPoints));
      SetText("spread",   StringFormat("Spread    : %.1f pts", data.spreadPoints));
      SetText("session",  "Session   : " + (data.sessionOk ? "OPEN" : "CLOSED"));
      SetText("layer",    StringFormat("Layer     : %d / %d", data.layerCount, InpMaxLayers));
      SetText("recovery", "Recovery  : " + data.recoveryModeText);
      SetText("lots",     StringFormat("Total Lot : %.2f", data.totalLots));
      SetText("floating", StringFormat("Floating  : %.2f", data.floatingProfit));
      SetText("equity",   StringFormat("Equity    : %.2f", data.equity));
      SetText("balance",  StringFormat("Balance   : %.2f", data.balance));
      SetText("margin",   StringFormat("Margin Lvl: %.1f%%", data.marginLevel));

      ObjectSetInteger(0, LabelName("floating"), OBJPROP_COLOR, floatingColor);
     }
  };

#endif // __GHR_DASHBOARD_MQH__
