// COT indicator v3: local cache + chart UI; networking belongs to SqCOTService.
#property copyright "StrategyQuant"
#property link      "https://www.strategyquant.com"
#property version   "4.25"
#property description "COT (Commitment of Traders) indicator"
#property description "Reads binary cache from FILE_COMMON."
#property description "Start SqCOTService and click Update COT Data."
#property description "COT data provided by SpreadCharts.com"
#property indicator_separate_window
#property indicator_buffers 5
#property indicator_plots   5

//--- plot properties
#property indicator_label1  "Hedgers - position index (CPI)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Hedgers - traders index (CTI)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrangeRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Large speculators - position index (CPI)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrLimeGreen
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "Large speculators - traders index (CTI)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGold
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

#property indicator_label5  "Small traders - position index (CPI)"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrMagenta
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1

//--- levels
#property indicator_minimum   -0.05
#property indicator_maximum    1.05
#property indicator_level1     0.20
#property indicator_level2     0.80
#property indicator_levelcolor clrGray
#property indicator_levelstyle STYLE_DOT
#property indicator_levelwidth 1

#define SQ_COT_DEFAULT_ID "AUTO"
#include <SqCOTVisual.mqh>
