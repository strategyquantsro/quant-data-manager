// Shared implementation for SqCOT and its compatibility alias SqCOTAuto.
#include <SqCOTReader.mqh>
#include <SqCOTProtocol.mqh>
#include <SqCOTMarketsPanel.mqh>
#include <SqCOTClient.mqh>
#include <SqCOTMaintenance.mqh>
#include <SqCOTMappingPanel.mqh>
#ifndef SQ_COT_DEFAULT_ID
#define SQ_COT_DEFAULT_ID "AUTO"
#endif

// Keep the first two inputs in the original order for existing iCustom callers.
input string CotIdentifier = SQ_COT_DEFAULT_ID; // COT identifier, exactly as in the dataset
input int    ValueIndex    = 0;        // Highlight buffer 0..4
input bool   ShowUpdatePanel = true;  // Show download button and service status
input bool   ShowLegend = true;       // Show color-matched descriptions of all five lines
input bool   ShowMarketsPanel = true; // Collapsible market heatmap above the price chart
input bool   RememberLayout = true;   // Remember this chart's market, filters and panel layout
input string FavoriteMarkets = "GC,6E,ES,NQ,CL,SI,ZB,6B"; // Initial favorites (market codes)
input string UIInstance = "main";     // Use a different key for multiple SqCOT instances on one chart
input int    MarketsTop = 24;         // Top margin of the market panel, in logical pixels
input bool   NotifyServicePopup = true; // Shared watchdog popup when service stops
input bool   NotifyServicePush = false; // MT5 Notifications must be configured first
input bool   NotifyCOTEventsPopup = false; // New hedger CPI events after attachment (selected market)
input bool   NotifyCOTEventsPush = false;  // Explain COT events via MT5 Notifications
input int AutoHorizonWeeks=52; // Used in AUTO mode; explicit IDs retain their horizon
CCOTSymbolMap SymbolMap;
CCOTMappingPanel MappingPanel;
CotMapResult MappingResult;
bool AutoMode=false;
int MappingWeeks=52;
CSqCOTClient LiveStatus;
CCOTPollGate LocalPoll;
int PollTimerSeconds=60;

double CpihedgBuffer[],CtihedgBuffer[],CpispecBuffer[],CtispecBuffer[],CpismallBuffer[];
datetime BarTimes[];
bool DataLoaded=false,Busy=false,OtherBusy=false,TesterMode=false,UIReady=false;
string LoadedVersion="",RequestId="",UiPrefix="",UiMessage="";
string LastPanelState="";
bool UiError=false;
int PanelWidth=320,PanelRowHeight=17,AttributionRowHeight=14,LastChartWidth=-1;
bool PanelTwoColumns=false;
string ActiveIdentifier="";
bool RestoredSelection=false;
CCOTMarketsPanel Markets;

datetime LatestReport()
{
   int idx=COT_FindSeries(ActiveIdentifier);
   if(idx<0 || !DataLoaded) return 0;
   datetime asOf=TesterMode?TimeCurrent():COT_NOW();
   int row=COT_BinarySearch(g_cotSeries[idx].records,g_cotSeries[idx].count,asOf);
   return row<0?0:(datetime)g_cotSeries[idx].records[row].date;
}
void SaveMappingMode()
{
   Markets.prefs.autoMode=AutoMode?1:0;Markets.prefs.autoWeeks=MappingWeeks;Markets.Save();
}
bool ResolveChart(const bool force=false)
{
   if(!AutoMode)return false;
   string old=ActiveIdentifier;
   bool resolved=SymbolMap.Resolve(_Symbol,AccountInfoString(ACCOUNT_SERVER),MappingWeeks,MappingResult,force);
   if(!resolved)
   {
      UiError=true;UiMessage=MappingResult.status+" "+MappingResult.error;
      // Invalid edits retain previous curves with a visible error. Unmapped charts stay empty.
      if(MappingResult.status!="CONFIG_INVALID")
      {
         ActiveIdentifier="";DataLoaded=false;LiveStatus.Close();
         ArrayInitialize(CpihedgBuffer,EMPTY_VALUE);ArrayInitialize(CtihedgBuffer,EMPTY_VALUE);
         ArrayInitialize(CpispecBuffer,EMPTY_VALUE);ArrayInitialize(CtispecBuffer,EMPTY_VALUE);ArrayInitialize(CpismallBuffer,EMPTY_VALUE);
         return old!="";
      }
      return false;
   }
   ActiveIdentifier=MappingResult.series;
   UiError=false;UiMessage="";
   if(old==ActiveIdentifier)return false;
   DataLoaded=false;LoadedVersion="";LastPanelState="";
   COT_RetainOnlySeries(ActiveIdentifier);
   IndicatorSetString(INDICATOR_SHORTNAME,"SqCOT(AUTO "+_Symbol+" > "+ActiveIdentifier+")");
   UiError=false;UiMessage="";Markets.prefs.selected=ActiveIdentifier;Markets.Invalidate();
   return true;
}
bool SelectMarket(string identifier)
{
   StringToUpper(identifier);
   if(!COT_SafeName(identifier) || !COT_Load(identifier))
   {
      UiError=true; UiMessage=COT_GetLastError();
      if(UiMessage=="") UiMessage="Cannot load this COT market. Existing detail was retained.";
      return false;
   }
   AutoMode=false;ActiveIdentifier=identifier; DataLoaded=true;
   MappingWeeks=COT_MapWeeks(identifier)==156?156:52;SaveMappingMode();
   COT_RetainOnlySeries(ActiveIdentifier);
   LoadedVersion=COT_GetDatasetVersion();
   Markets.prefs.selected=identifier; Markets.Save();
   UiError=false; UiMessage="";
   IndicatorSetString(INDICATOR_SHORTNAME,"SqCOT("+ActiveIdentifier+" | price: "+_Symbol+")");
   LastPanelState=""; Markets.Invalidate();
   if(!TesterMode) LoadCOTData(true,false);
   RefreshIndicator();
   return true;
}

void MeasurePanel()
{
   TextSetFont("Arial",-80);
   uint creditWidth=0,creditHeight=0;
   if(TextGetSize("Data provided by SpreadCharts",creditWidth,creditHeight))
      AttributionRowHeight=MathMax(14,(int)creditHeight+2);
   TextSetFont("Arial",-90);
   uint width=0,height=0;
   int desired=280;
   for(int i=0;i<5;i++)
      if(TextGetSize(LegendText(i),width,height)) desired=MathMax(desired,(int)width+24);
   if(TextGetSize("Last update: 2026.09.24 15:35",width,height))
   {
      desired=MathMax(desired,(int)width+24);
      PanelRowHeight=MathMax(17,(int)height+4);
   }
   LastChartWidth=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int available=LastChartWidth-12;
   PanelTwoColumns=ShowUpdatePanel && Markets.prefs.details && available>=desired*2;
   if(PanelTwoColumns) desired*=2;
   PanelWidth=MathMax(100,MathMin(desired,available));
}
string TakePanelLine(string &text)
{
   int take=StringLen(text);
   uint width=0,height=0;
   while(take>1)
   {
      int lineWidth=(PanelTwoColumns?PanelWidth/2:PanelWidth)-20;
      if(!TextGetSize(StringSubstr(text,0,take),width,height) || (int)width<=lineWidth) break;
      take--;
   }
   if(take<StringLen(text))
      for(int i=take;i>take/2;i--) if(StringGetCharacter(text,i)==' ') {take=i; break;}
   string line=StringSubstr(text,0,take);
   text=COT_Trim(StringSubstr(text,take));
   return line;
}
void ResizePanel(const int bottom)
{
   ObjectSetInteger(0,UiPrefix+"background",OBJPROP_XSIZE,PanelWidth);
   ObjectSetInteger(0,UiPrefix+"background",OBJPROP_YSIZE,MathMax(30,bottom-14+8));
}

string LegendText(const int field)
{
   switch(field)
   {
      case 0: return "Hedgers - positions (CPI)";
      case 1: return "Hedgers - traders (CTI)";
      case 2: return "Large speculators - positions (CPI)";
      case 3: return "Large speculators - traders (CTI)";
      case 4: return "Small traders - positions (CPI)";
   }
   return " ";
}
string LegendTooltip(const int field)
{
   string key="";
   switch(field)
   {
      case 0: key="cpihedg"; break;
      case 1: key="ctihedg"; break;
      case 2: key="cpispec"; break;
      case 3: key="ctispec"; break;
      case 4: key="cpismall"; break;
   }
   string meaning=(field==1 || field==3) ? "CTI: trader participation index." : "CPI: position index.";
   return LegendText(field)+"\n"+meaning+" Values: 0 to 1.\nData field: "+key;
}
bool CreatePanelLabel(const string name,const int window,const int y,const string text)
{
   if(!ObjectCreate(0,name,OBJ_LABEL,window,0,0)) return false;
   // MT5 may show the default caption "Label" for an empty OBJ_LABEL.
   // Initialize with a space and explicitly hide unused status rows.
   ObjectSetString(0,name,OBJPROP_TEXT,text==""?" ":text);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,1);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   return true;
}
void UpdateLegend(const int top)
{
   if(!ShowLegend) return;
   for(int i=0;i<5;i++)
   {
      string name=UiPrefix+"legend"+IntegerToString(i);
      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,(!ShowUpdatePanel || Markets.prefs.details)?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,PanelTwoColumns?10+PanelWidth/2:10);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,top+i*PanelRowHeight);
      ObjectSetInteger(0,name,OBJPROP_COLOR,PlotIndexGetInteger(i,PLOT_LINE_COLOR));
      ObjectSetString(0,name,OBJPROP_TEXT,LegendText(i));
      ObjectSetString(0,name,OBJPROP_TOOLTIP,LegendTooltip(i));
   }
}
void FillBar(const int i,const datetime when)
{
   CpihedgBuffer[i]=COT_GetValue(ActiveIdentifier,0,when);
   CtihedgBuffer[i]=COT_GetValue(ActiveIdentifier,1,when);
   CpispecBuffer[i]=COT_GetValue(ActiveIdentifier,2,when);
   CtispecBuffer[i]=COT_GetValue(ActiveIdentifier,3,when);
   CpismallBuffer[i]=COT_GetValue(ActiveIdentifier,4,when);
   // Reader/strategy API keeps its -1 sentinel; plotted lines leave a gap.
   if(CpihedgBuffer[i]==-1.0) CpihedgBuffer[i]=EMPTY_VALUE;
   if(CtihedgBuffer[i]==-1.0) CtihedgBuffer[i]=EMPTY_VALUE;
   if(CpispecBuffer[i]==-1.0) CpispecBuffer[i]=EMPTY_VALUE;
   if(CtispecBuffer[i]==-1.0) CtispecBuffer[i]=EMPTY_VALUE;
   if(CpismallBuffer[i]==-1.0) CpismallBuffer[i]=EMPTY_VALUE;
}
void RefreshIndicator()
{
   // Timer-driven redraw also works on weekends, without another market tick.
   int n=ArraySize(BarTimes);
   if(DataLoaded && n==ArraySize(CpihedgBuffer))
      for(int i=0;i<n;i++) FillBar(i,BarTimes[i]);
   ChartRedraw();
}
bool LoadCOTData(const bool force=false,const bool redraw=true)
{
   // One shared gate for timer and ticks. Scrolling/history loads do not poll disk.
   if(!TesterMode && !LocalPoll.Due(GetTickCount64(),force)) return false;
   SymbolMap.Load(force);
   bool mapped=ResolveChart(force);
   if(ActiveIdentifier=="" || ActiveIdentifier=="AUTO")return mapped;
   if(!TesterMode)
   {
      if(LiveStatus.Series()!=ActiveIdentifier) {LiveStatus.OpenLive(ActiveIdentifier);LiveStatus.SetNotifications(NotifyServicePopup,NotifyServicePush);}
      LiveStatus.Poll();
   }
   bool changed=COT_ReloadIfVersionChanged();
   if(!DataLoaded || changed)
   {
      if(COT_Load(ActiveIdentifier))
      {
         DataLoaded=true; LoadedVersion=COT_GetDatasetVersion();
         if(redraw) RefreshIndicator();
         return true;
      }
      if(!DataLoaded) UiMessage=COT_GetLastError();
   }
   return false;
}
bool CreateUpdateButton()
{
   if((!ShowUpdatePanel && !ShowLegend) || UIReady) return UIReady;
   int window=ChartWindowFind();
   if(window<0) return false;
   MeasurePanel();
   // Create the opaque foreground panel first, then draw controls/text above it.
   string background=UiPrefix+"background";
   if(!ObjectCreate(0,background,OBJ_RECTANGLE_LABEL,window,0,0)) return false;
   ObjectSetInteger(0,background,OBJPROP_XDISTANCE,5);
   ObjectSetInteger(0,background,OBJPROP_YDISTANCE,14);
   ObjectSetInteger(0,background,OBJPROP_BGCOLOR,C'24,28,34');
   ObjectSetInteger(0,background,OBJPROP_COLOR,C'70,78,90');
   ObjectSetInteger(0,background,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,background,OBJPROP_BACK,false);
   ObjectSetInteger(0,background,OBJPROP_ZORDER,0);
   ObjectSetInteger(0,background,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,background,OBJPROP_HIDDEN,true);
   ObjectSetString(0,background,OBJPROP_TOOLTIP,"\n");
   ResizePanel(ShowUpdatePanel?190:115);
   if(ShowUpdatePanel)
   {
      string button=UiPrefix+"button";
      if(!ObjectCreate(0,button,OBJ_BUTTON,window,0,0))
      {ObjectsDeleteAll(0,UiPrefix); return false;}
      ObjectSetInteger(0,button,OBJPROP_XDISTANCE,10);
      ObjectSetInteger(0,button,OBJPROP_YDISTANCE,20);
      ObjectSetInteger(0,button,OBJPROP_XSIZE,180);
      ObjectSetInteger(0,button,OBJPROP_YSIZE,24);
      ObjectSetInteger(0,button,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,button,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,button,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,button,OBJPROP_BACK,false);
      ObjectSetInteger(0,button,OBJPROP_ZORDER,2);
      ObjectSetString(0,button,OBJPROP_FONT,"Arial");
      string details=UiPrefix+"details";
      if(!ObjectCreate(0,details,OBJ_BUTTON,window,0,0))
      {ObjectsDeleteAll(0,UiPrefix); return false;}
      ObjectSetInteger(0,details,OBJPROP_YDISTANCE,20);
      ObjectSetInteger(0,details,OBJPROP_YSIZE,24);
      ObjectSetInteger(0,details,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,details,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,details,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,details,OBJPROP_BACK,false);
      ObjectSetInteger(0,details,OBJPROP_ZORDER,2);
      ObjectSetInteger(0,details,OBJPROP_BGCOLOR,C'42,51,65');
      ObjectSetInteger(0,details,OBJPROP_COLOR,clrWhite);
      ObjectSetString(0,details,OBJPROP_FONT,"Arial");
      ObjectSetString(0,details,OBJPROP_TOOLTIP,"Expand/collapse status details and the five-line legend.");
      for(int i=0;i<2;i++)
      {
         string credit=UiPrefix+"credit"+IntegerToString(i);
         string caption=i==0?"StrategyQuant COT":"Data provided by SpreadCharts";
         if(!CreatePanelLabel(credit,window,48+i*AttributionRowHeight,caption))
         {ObjectsDeleteAll(0,UiPrefix); return false;}
         ObjectSetInteger(0,credit,OBJPROP_FONTSIZE,8);
         ObjectSetInteger(0,credit,OBJPROP_COLOR,i==0?clrGainsboro:clrSilver);
         ObjectSetString(0,credit,OBJPROP_TOOLTIP,caption);
      }
      for(int i=0;i<6;i++)
      {
         string name=UiPrefix+"label"+IntegerToString(i);
         if(!CreatePanelLabel(name,window,50+i*17," "))
         {ObjectsDeleteAll(0,UiPrefix); return false;}
         ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_NO_PERIODS);
      }
   }
   if(ShowLegend)
      for(int i=0;i<5;i++)
         if(!CreatePanelLabel(UiPrefix+"legend"+IntegerToString(i),window,90+i*17,LegendText(i)))
         {ObjectsDeleteAll(0,UiPrefix); return false;}
   UIReady=true;
   LastPanelState="";
   return true;
}
void ShowStatus()
{
   // Only an attached, interactive indicator may restore a clicked market.
   // Invisible iCustom handles and tester runs retain their input identifier.
   int window=ChartWindowFind();
   if(window<0) return;
   if(!RestoredSelection)
   {
      RestoredSelection=true;
      if(!TesterMode && RememberLayout && Markets.prefs.autoMode>=0)
      {
         AutoMode=Markets.prefs.autoMode==1;MappingWeeks=Markets.prefs.autoWeeks;
         if(AutoMode)LoadCOTData(true);
      }
      if(!AutoMode && !TesterMode && RememberLayout && Markets.prefs.selected!=ActiveIdentifier &&
         COT_IsAvailable(Markets.prefs.selected)) SelectMarket(Markets.prefs.selected);
   }
   Markets.Render(ActiveIdentifier,LatestReport());
   if(!CreateUpdateButton()) return;
   MeasurePanel();
   string layout=IntegerToString(PanelWidth)+"|"+IntegerToString(PanelRowHeight)+"|"+IntegerToString(AttributionRowHeight);
   if(ShowLegend)
      for(int i=0;i<5;i++) layout+="|"+IntegerToString(PlotIndexGetInteger(i,PLOT_LINE_COLOR));
   if(!ShowUpdatePanel)
   {
      if(LastPanelState==layout) return;
      LastPanelState=layout;
      UpdateLegend(20);
      ResizePanel(20+5*PanelRowHeight);
      ChartRedraw();
      return;
   }
   string message=UiMessage;
   color ink=UiError?clrTomato:clrGainsboro;
   if(TesterMode) message=DataLoaded?"Strategy Tester: cached COT data.":"Strategy Tester: prepare COT data before testing.";
   else if(!COT_ServiceAvailable())
   {message="COT Data Service is not running. Start Navigator > Services > SqCOTService."; ink=clrTomato;}
   else if(Busy) message="Downloading and validating COT data...";
   else if(OtherBusy) message="Another chart is updating COT data...";
   else
   {
      SqCOTSnapshot snapshot;
      if(LiveStatus.ReadLatest(snapshot))
      {
         message=COT_StatusName(snapshot.dataStatus)+(snapshot.calendarFallback?" [age limit]":"")+" | Report: "+TimeToString((datetime)snapshot.reportDate,TIME_DATE)+
            " | Observed: "+TimeToString((datetime)snapshot.availableAtUtc,TIME_DATE|TIME_MINUTES)+" UTC";
         if(!LiveStatus.CanTrade(snapshot)) ink=clrTomato;
      }
       else if(message=="") message=DataLoaded?"Legacy display only; verified live snapshot unavailable.":"No cached data. Set QDM Data License in SqCOTService, then click Update COT Data.";
   }
   if(AutoMode && MappingResult.status!="RESOLVED"){message=MappingResult.status+" "+MappingResult.error;ink=clrTomato;}
   string button=UiPrefix+"button";
   bool disabled=TesterMode || Busy || OtherBusy;
   bool showButton=!TesterMode;
   string updated=DataLoaded?TimeToString(COT_GetLastUpdate(),TIME_DATE|TIME_MINUTES):"never";
   string state=layout+"|"+message+"|"+IntegerToString((int)ink)+"|"+updated+
                "|"+IntegerToString((int)disabled)+"|"+IntegerToString((int)UiError)+
                "|"+IntegerToString((int)showButton)+"|"+ActiveIdentifier+
                "|"+IntegerToString((int)Markets.prefs.details)+"|"+MappingPanel.Signature()+"|"+SymbolMap.Hash()+
                "|"+MappingResult.status+"|"+IntegerToString((int)AutoMode)+"|"+IntegerToString(MappingWeeks);
   // Polling is read-only while state is unchanged. Do not requeue object
   // updates or ChartRedraw on every timer event / chart scroll.
   if(LastPanelState==state) return;
   LastPanelState=state;
   ObjectSetInteger(0,button,OBJPROP_TIMEFRAMES,showButton?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
   ObjectSetString(0,button,OBJPROP_TEXT,disabled?(TesterMode?"Cached data only":"Updating..."):(UiError?"Retry":"Update COT Data"));
   ObjectSetInteger(0,button,OBJPROP_BGCOLOR,disabled?clrDimGray:clrSteelBlue);
   ObjectSetInteger(0,button,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,button,OBJPROP_STATE,false);
   int buttonWidth=MathMin(180,PanelWidth-86);
   ObjectSetInteger(0,button,OBJPROP_XSIZE,buttonWidth);
   string details=UiPrefix+"details";
   ObjectSetInteger(0,details,OBJPROP_XDISTANCE,16+buttonWidth);
   ObjectSetInteger(0,details,OBJPROP_XSIZE,64);
   ObjectSetInteger(0,details,OBJPROP_STATE,false);
   ObjectSetString(0,details,OBJPROP_TEXT,Markets.prefs.details?"Details -":"Details +");
   int creditTop=48;
   for(int i=0;i<2;i++)
      ObjectSetInteger(0,UiPrefix+"credit"+IntegerToString(i),OBJPROP_YDISTANCE,creditTop+i*AttributionRowHeight);
   int statusTop=creditTop+2*AttributionRowHeight+4;
   if(!TesterMode)statusTop=MappingPanel.Render(SymbolMap,MappingResult,AutoMode,ActiveIdentifier,MappingWeeks,
      window,statusTop,PanelTwoColumns?PanelWidth/2:PanelWidth,MarketsTop+40);
   string headline=Markets.prefs.details?"Downloaded: "+updated:message;
   string headlineRest=headline;
   if(!Markets.prefs.details) headline=TakePanelLine(headlineRest);
   if(!Markets.prefs.details && headlineRest!="") headline+="...";
   ObjectSetString(0,UiPrefix+"label0",OBJPROP_TEXT,headline);
   ObjectSetInteger(0,UiPrefix+"label0",OBJPROP_YDISTANCE,statusTop);
   ObjectSetString(0,UiPrefix+"label0",OBJPROP_TOOLTIP,"COT "+ActiveIdentifier+" | Downloaded: "+updated+"\n"+message);
   ObjectSetInteger(0,UiPrefix+"label0",OBJPROP_COLOR,Markets.prefs.details?clrGainsboro:ink);
   ObjectSetInteger(0,UiPrefix+"label0",OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   string fullMessage=message;
   int visibleRows=0;
   for(int i=1;i<6;i++)
   {
      string line="";
      if(StringLen(message)>0)
      {
         line=TakePanelLine(message);
      }
      string name=UiPrefix+"label"+IntegerToString(i);
      bool visible=Markets.prefs.details && (line!="");
      ObjectSetString(0,name,OBJPROP_TEXT,visible?line:" ");
      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,visible?OBJ_ALL_PERIODS:OBJ_NO_PERIODS);
      ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,statusTop+i*PanelRowHeight);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,fullMessage);
      if(visible) visibleRows=i;
   }
   // Keep descriptions directly below the actual message, including wrapped errors.
   int statusBottom=statusTop+(visibleRows+1)*PanelRowHeight+6;
   int legendTop=PanelTwoColumns?20:statusBottom;
   UpdateLegend(legendTop);
   int bottom=(ShowLegend && Markets.prefs.details)?MathMax(statusBottom,legendTop+5*PanelRowHeight):statusBottom;
   ResizePanel(bottom);
   ChartRedraw();
}
int OnInit()
{
   if(!COT_SafeName(CotIdentifier) || !COT_SafeName(UIInstance) ||
      MarketsTop<0 || MarketsTop>2000 || ValueIndex<0 || ValueIndex>4 || (AutoHorizonWeeks!=52 && AutoHorizonWeeks!=156)) return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,CpihedgBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,CtihedgBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,CpispecBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,CtispecBuffer,INDICATOR_DATA);
   SetIndexBuffer(4,CpismallBuffer,INDICATOR_DATA);
   ArraySetAsSeries(CpihedgBuffer,false); ArraySetAsSeries(CtihedgBuffer,false);
   ArraySetAsSeries(CpispecBuffer,false); ArraySetAsSeries(CtispecBuffer,false); ArraySetAsSeries(CpismallBuffer,false);
   for(int i=0;i<5;i++)
   {
      PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetInteger(i,PLOT_LINE_WIDTH,i==ValueIndex?2:1);
   }
   IndicatorSetString(INDICATOR_SHORTNAME,"SqCOT("+CotIdentifier+")");
   IndicatorSetInteger(INDICATOR_DIGITS,3);
   TesterMode=(bool)(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION));
   UiPrefix="SqCOT_"+IntegerToString(ChartID())+"_"+IntegerToString((long)GetMicrosecondCount())+"_";
   ActiveIdentifier=CotIdentifier; StringToUpper(ActiveIdentifier);
   AutoMode=ActiveIdentifier=="AUTO";MappingWeeks=AutoMode?AutoHorizonWeeks:(COT_MapWeeks(ActiveIdentifier)==156?156:52);
   if(AutoMode && TesterMode){Print("Use SqCOTData AUTO with a pinned snapshot in the tester.");return INIT_PARAMETERS_INCORRECT;}
   MappingPanel.Init(UiPrefix);SymbolMap.Load(true);
   string settingsPath="StrategyQuant\\COT\\ui\\"+IntegerToString(ChartID())+"_"+COT_MapHash(AccountInfoString(ACCOUNT_SERVER)+"|"+_Symbol+"|"+CotIdentifier+"|"+UIInstance)+".dat";
   Markets.Init(UiPrefix,settingsPath,ActiveIdentifier,FavoriteMarkets,ShowMarketsPanel && !TesterMode,
                RememberLayout && !TesterMode,MarketsTop,NotifyCOTEventsPopup,NotifyCOTEventsPush);
   if(AutoMode){ActiveIdentifier="";ResolveChart(true);}
   DataLoaded=COT_Initialize() && ActiveIdentifier!="" && COT_Load(ActiveIdentifier);
   if(DataLoaded) LoadedVersion=COT_GetDatasetVersion();
   else Print("[SQ COT] ",COT_GetLastError());
   // Tester data is pinned at initialization for reproducibility.
   if(!TesterMode && !EventSetTimer(PollTimerSeconds)) return INIT_FAILED;
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   Markets.Destroy();
   LiveStatus.Close();
   EventKillTimer();
   if(RequestId!="" && !TesterMode) COT_CancelQueued(RequestId);
   ObjectsDeleteAll(0,UiPrefix);
   COT_Deinitialize();
}
void UpdatePollTimer()
{
   if(TesterMode) return;
   int seconds=(Busy || OtherBusy)?1:60;
   if(seconds!=PollTimerSeconds && EventSetTimer(seconds)) PollTimerSeconds=seconds;
}
void OnTimer()
{
   LoadCOTData();
   bool available=COT_ServiceAvailable();
   CotStatus shared;
   OtherBusy=COT_ReadStatus(shared) && available &&
             (shared.state=="REQUESTED" || shared.state=="DOWNLOADING") && shared.id!=RequestId;
   if(RequestId!="")
   {
      CotStatus own;
      if(COT_ReadRequestStatus(RequestId,own))
      {
         if(own.state=="SUCCESS" || own.state=="ERROR")
         {
            Busy=false; UiError=own.state=="ERROR"; UiMessage=own.message;
            if(own.state=="SUCCESS")
            {
               LoadCOTData(true);
               if(!DataLoaded) {UiError=true; UiMessage=COT_GetLastError();}
            }
            RequestId="";
         }
      }
      if(Busy && !available)
      {
         COT_CancelQueued(RequestId);
         Busy=false; UiError=true; UiMessage="Service stopped during update. Restart SqCOTService and retry.";
         RequestId="";
      }
   }
   ShowStatus();
   UpdatePollTimer();
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      // Scrolling/zooming can emit chart-change events with identical layout.
      Markets.Render(ActiveIdentifier,LatestReport());
      if((int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)!=LastChartWidth) ShowStatus();
      return;
   }
   string mapAction;
   if(!TesterMode && MappingPanel.Handle(id,sparam,mapAction))
   {
      if(MappingPanel.IsOpen()){Markets.prefs.expanded=false;Markets.prefs.view=0;Markets.Invalidate();}
      if(mapAction=="auto" || mapAction=="52" || mapAction=="156")
      {
         AutoMode=true;if(mapAction!="auto")MappingWeeks=(int)StringToInteger(mapAction);
         // Changing the user's selection clears the previous market immediately.
         ActiveIdentifier="";DataLoaded=false;
         ArrayInitialize(CpihedgBuffer,EMPTY_VALUE);ArrayInitialize(CtihedgBuffer,EMPTY_VALUE);
         ArrayInitialize(CpispecBuffer,EMPTY_VALUE);ArrayInitialize(CtispecBuffer,EMPTY_VALUE);ArrayInitialize(CpismallBuffer,EMPTY_VALUE);
         LoadCOTData(true);SaveMappingMode();
      }
      else if(mapAction=="validate"){SymbolMap.Load(true);LoadCOTData(true);}
      else if(mapAction=="path")Print("[SQ COT MAPPING] ",TerminalInfoString(TERMINAL_COMMONDATA_PATH),"\\Files\\",COT_MAP_FILE);
      else if(StringFind(mapAction,"select.")==0)
      {
         string series=SymbolMap.SeriesFor(StringSubstr(mapAction,7),MappingWeeks);
         if(series!="")SelectMarket(series);
         else{UiError=true;UiMessage="SERIES_UNAVAILABLE: selected horizon is not in the dataset.";}
      }
      LastPanelState="";ShowStatus();return;
   }
   string selection;
   if(Markets.Handle(id,sparam,selection))
   {
      MappingPanel.Collapse();LastPanelState="";
      if(selection!="") SelectMarket(selection);
      ShowStatus(); return;
   }
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==UiPrefix+"details")
   {
      Markets.prefs.details=!Markets.prefs.details; Markets.Save();
      ShowStatus(); return;
   }
   if(id!=CHARTEVENT_OBJECT_CLICK || sparam!=UiPrefix+"button") return;
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   if(TesterMode || Busy || OtherBusy) return;
   string error,newId;
    if(COT_RequestUpdate(ActiveIdentifier=="" || ActiveIdentifier=="AUTO"?"GC_52W":ActiveIdentifier,newId,error))
   {RequestId=newId; Busy=true; UiError=false; UiMessage="";}
   else {UiError=true; UiMessage=error;}
   UpdatePollTimer();
   ShowStatus();
}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   ArraySetAsSeries(time,false);
   bool refreshed=false;
   if(!TesterMode) refreshed=LoadCOTData(false,false);
   int start=(prev_calculated>0 && prev_calculated<=rates_total)?prev_calculated-1:0;
   if(refreshed) start=0;
   ArrayResize(BarTimes,rates_total);
   if(start==0)
   {
      ArrayInitialize(CpihedgBuffer,EMPTY_VALUE); ArrayInitialize(CtihedgBuffer,EMPTY_VALUE);
      ArrayInitialize(CpispecBuffer,EMPTY_VALUE); ArrayInitialize(CtispecBuffer,EMPTY_VALUE);
      ArrayInitialize(CpismallBuffer,EMPTY_VALUE);
   }
   for(int i=start;i<rates_total;i++)
   {
      BarTimes[i]=time[i];
      if(DataLoaded) FillBar(i,time[i]);
      else
      {
         CpihedgBuffer[i]=EMPTY_VALUE; CtihedgBuffer[i]=EMPTY_VALUE; CpispecBuffer[i]=EMPTY_VALUE;
         CtispecBuffer[i]=EMPTY_VALUE; CpismallBuffer[i]=EMPTY_VALUE;
      }
   }
   if(!UIReady) ShowStatus();
   return rates_total;
}
