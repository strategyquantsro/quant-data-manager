// Main-chart overlay. Rebuild objects only after a meaningful UI/data change.
#ifndef __SQ_COT_MARKETS_PANEL_MQH__
#define __SQ_COT_MARKETS_PANEL_MQH__
#include <SqCOTMarkets.mqh>
#include <SqCOTMaintenance.mqh>

color COT_MarketColor(const double value)
{
   if(!COT_MarketValid(value)) return C'51,57,66';
   color edge=value<0.5?C'40,103,165':C'165,93,37';
   color middle=C'46,54,66';
   double weight=MathAbs(value-0.5)*2;
   int r=(int)((middle&255)*(1-weight)+(edge&255)*weight);
   int g=(int)(((middle>>8)&255)*(1-weight)+((edge>>8)&255)*weight);
   int b=(int)(((middle>>16)&255)*(1-weight)+((edge>>16)&255)*weight);
   return (color)(r|(g<<8)|(b<<16));
}

class CCOTMarketsPanel
{
private:
   string m_prefix,m_signature,m_dataVersion,m_path;
   string m_rendered[],m_touched[];
   int m_width,m_height,m_dataWeeks,m_pageSize,m_order[],m_top;
   double m_scale;
   bool m_enabled,m_remember,m_dirty,m_orderDirty;
   CotMarketRow m_rows[];
   CSqCOTClient m_client,m_peerClient;
   bool m_eventPopup,m_eventPush;
   long m_started,m_expected;
   string m_lastEvent;
   bool m_baselined;
   long m_eventReport;
   int m_eventMask;
   string m_analyticsToken;
   SqCOTInsight m_alertInsight;
   bool m_alertValid;
   CCOTPollGate m_insightPoll;
   string m_insightVersion;

   int Px(const int value) {return (int)MathRound(value*m_scale);}
   string Fit(string value,const int width,const int font=8)
   {
      // Chart label captions are truncated by MT5 on some terminal builds.
      // Keep the full text in the tooltip and make truncation explicit.
      if(StringLen(value)>63) value=StringSubstr(value,0,60)+"...";
      TextSetFont("Arial",-10*font);
      uint w=0,h=0;
      if(TextGetSize(value,w,h) && (int)w<=width) return value;
      while(StringLen(value)>1)
      {
         value=StringSubstr(value,0,StringLen(value)-1);
         if(TextGetSize(value+"...",w,h) && (int)w<=width) return value+"...";
      }
      return "";
   }
   bool Object(const string key,const ENUM_OBJECT type)
   {
      string name=m_prefix+key;
      int n=ArraySize(m_touched); ArrayResize(m_touched,n+1); m_touched[n]=name;
      if(ObjectFind(0,name)>=0) return true;
      if(!ObjectCreate(0,name,type,0,0,0)) return false;
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetString(0,name,OBJPROP_FONT,"Arial");
      return true;
   }
   void Box(const string key,const int x,const int y,const int w,const int h,const color bg)
   {
      if(!Object(key,OBJ_RECTANGLE_LABEL)) return;
      string name=m_prefix+key;
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,name,OBJPROP_COLOR,C'65,77,94');
      ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,10);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,"\n");
   }
   void Label(const string key,const string text,const int x,const int y,const int w,const color ink=clrSilver)
   {
      if(!Object(key,OBJ_LABEL)) return;
      string name=m_prefix+key;
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8); ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
      ObjectSetInteger(0,name,OBJPROP_ZORDER,11);
      string clipped=Fit(text,w);
      ObjectSetString(0,name,OBJPROP_TEXT,clipped==""?" ":clipped);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,text);
   }
   void Button(const string key,const string text,const int x,const int y,const int w,
               const int h,const color bg,const string tooltip="")
   {
      if(!Object(key,OBJ_BUTTON)) return;
      string name=m_prefix+key;
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,w); ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8); ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'45,55,70');
      ObjectSetInteger(0,name,OBJPROP_STATE,false); ObjectSetInteger(0,name,OBJPROP_ZORDER,12);
      string clipped=Fit(text,w-Px(8));
      ObjectSetString(0,name,OBJPROP_TEXT,clipped==""?" ":clipped);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,tooltip==""?text:tooltip);
   }
   void End()
   {
      // Remove only controls no longer in the layout. Existing backgrounds stay
      // behind their text; removing/recreating them would change paint order.
      for(int i=0;i<ArraySize(m_rendered);i++)
      {
         bool found=false;
         for(int j=0;j<ArraySize(m_touched);j++) if(m_rendered[i]==m_touched[j]) {found=true; break;}
         if(!found) ObjectDelete(0,m_rendered[i]);
      }
      ArrayResize(m_rendered,ArraySize(m_touched)); ArrayCopy(m_rendered,m_touched);
      ChartRedraw();
   }
   void EnsureData()
   {
      string version=COT_GetDatasetVersion();
      bool changed=m_dataVersion!=version || m_dataWeeks!=prefs.weeks;
      if(changed)
      {
         string oldIds[];
         if(m_dataWeeks==prefs.weeks && !m_orderDirty)
         {
            ArrayResize(oldIds,ArraySize(m_order));
            for(int i=0;i<ArraySize(m_order);i++) oldIds[i]=m_rows[m_order[i]].id;
         }
         COT_MarketBuild(prefs.weeks,COT_NOW(),m_rows);
         m_dataVersion=version; m_dataWeeks=prefs.weeks;
         COT_MarketFilter(m_rows,prefs,m_order);
         // Freeze the visible order on cache refresh. Explicit sort/filter
         // actions re-sort; values may change without moving a hovered row.
         int target=0;
         for(int i=0;i<ArraySize(oldIds);i++)
            for(int j=target;j<ArraySize(m_order);j++)
               if(m_rows[m_order[j]].id==oldIds[i])
               {
                  int value=m_order[j];
                  for(int k=j;k>target;k--) m_order[k]=m_order[k-1];
                  m_order[target++]=value; break;
               }
         m_orderDirty=false;
      }
      if(m_orderDirty)
      {
         COT_MarketFilter(m_rows,prefs,m_order);
         m_orderDirty=false;
      }
   }
   string RowTooltip(const CotMarketRow &r)
   {
      string result=r.name+" | "+r.id+"\n";
      if(!r.readable) return result+"No readable records in the active cache.";
      result+="Dataset report date: "+TimeToString(r.date,TIME_DATE);
      if(r.previous>0) result+="\nPrevious record: "+TimeToString(r.previous,TIME_DATE);
      result+="\nHedgers: "+COT_MarketPercent(r.values[prefs.metric]);
      result+=" | Large speculators: "+COT_MarketPercent(r.values[prefs.metric==0?2:3]);
      if(prefs.metric==0) result+=" | Small traders: "+COT_MarketPercent(r.values[4]);
      SqCOTInsight a=r.insights[prefs.metric];
      result+="\nHedger change: "+COT_MarketDeltaText(r,prefs.metric)+" index points";
      result+="\n4-report change: "+(a.delta4Valid?COT_InsightDelta(a.delta4):"--")+" index points";
      result+="\nOther horizon: "+COT_InsightIndex(a.otherLevel)+" | "+COT_InsightHorizon(a);
      result+="\nExtreme duration: "+IntegerToString(a.extremeReports)+(a.durationCapped?"+":"")+" reports";
      result+="\nEvents: "+COT_InsightEvents(a.events);
      result+="\nFreshness: "+(m_expected==0?"Unknown schedule":(r.date>=m_expected?"Current report":"Expected report missing"));
      result+="\nChange compares adjacent records, which may be more than a week apart.";
      result+="\nColor shows index level, not a buy/sell recommendation.";
      return result+"\nClick to show this COT series; the price chart stays unchanged.";
   }
   void PrepareInsights(const string selected)
   {
      string version=COT_GetDatasetVersion();
      bool changed=m_client.Series()!=selected || version!=m_insightVersion;
      if(!m_insightPoll.Due(GetTickCount64(),changed)) return;
      m_insightVersion=version;
      if(m_client.Series()!=selected)
      {
         m_client.OpenLive(selected);
         m_peerClient.OpenLive(COT_MarketBase(selected)+(COT_MarketWeeks(selected)==52?"_156W":"_52W"));
         m_started=(long)COT_NOW();m_lastEvent="";m_baselined=false;m_eventReport=0;m_eventMask=0;m_analyticsToken="";
      }
      m_client.Poll();m_peerClient.Poll();
      long due,next;m_expected=0;
      if(!m_client.Expected((long)COT_NOW(),m_expected,due,next)) m_expected=0;
      if(!m_eventPopup && !m_eventPush) return;
      string token=IntegerToString(m_client.Generation())+":"+IntegerToString(m_peerClient.Generation())+":"+IntegerToString(m_expected);
      if(token!=m_analyticsToken)
      {m_alertValid=COT_ReadInsight(m_client,m_peerClient,(long)COT_NOW(),m_alertInsight);m_analyticsToken=token;}
      SqCOTInsight a=m_alertInsight;SqCOTSnapshot snapshot;
      if(!m_alertValid || !m_client.ReadLatest(snapshot) ||
         !m_client.CanTrade(snapshot)) return;
      if(!m_baselined)
      {m_baselined=true;m_started=(long)COT_NOW();m_eventReport=a.reportDate;m_eventMask=a.events;return;}
      bool cancelled=a.events==0 && a.reportDate==m_eventReport && m_eventMask!=0;
      if((a.events==0 && !cancelled) || a.availableAtUtc<=m_started)
      {m_eventReport=a.reportDate;m_eventMask=a.events;return;}
      // The first attached cache is a baseline, never a burst of historical alerts.
      // Hash the result so revisions of dependencies can produce a separate notice.
      string key="cot-insight-"+selected+"-"+IntegerToString(a.reportDate)+"-"+
         IntegerToString(a.availableAtUtc)+"-"+IntegerToString(a.events);
      if(key==m_lastEvent) return;
      string msg=selected+" "+TimeToString((datetime)a.reportDate,TIME_DATE)+": "+COT_InsightEvents(a.events)+
         "; H "+COT_InsightIndex(a.level)+"; d1 "+(a.delta1Valid?COT_InsightDelta(a.delta1):"--")+" pts";
      if(cancelled) msg+="; previous event no longer present";
      if(a.reportDate==m_eventReport) msg+="; revised comparison";
      if(a.revision>1) msg+="; revision "+IntegerToString(a.revision);
      if(COT_Notify(key,msg,m_eventPopup,m_eventPush,2147483647))
      {m_lastEvent=key;m_eventReport=a.reportDate;m_eventMask=a.events;}
   }
   void InsightLine(const int n,const string text,const int x,const int y,const int w,const color ink=clrGainsboro)
   {Label("insight."+IntegerToString(n),text,x+Px(8),y,w-Px(16),ink);}
   void RenderInsights(const string selected,const int x,const int top,const int w,const int height)
   {
      int y=top+Px(39),n=0;
      string lines[];
      if(prefs.view==3)
      {
         ArrayResize(lines,9);
         lines[0]="CPI: net-position range. CTI: trader participation.";
         lines[1]="87/100 is an index, not a share or probability.";
         lines[2]="High >=80; low <=20. Colors do not mean buy/sell.";
         lines[3]="Large move: >=10 pts. Persistence: third strict move.";
         lines[4]="52W / 156W: same report, different historical windows.";
         lines[5]="Count reports, not weeks. Rolling windows affect the index.";
         lines[6]="COT does not confirm reversals. CTI is not directional.";
         lines[7]="Check futures/CFD mapping and inverse FX quotes.";
         lines[8]="Data: SpreadCharts | Price confirmation not evaluated.";
      }
      else if(prefs.view==2)
      {
         ArrayResize(lines,9);
         lines[0]="Hedger CPI | current revisions, not a historical signal log";
         int available=0;
         for(int i=0;i<6;i++)
         {
            SqCOTInsight a;
            if(!COT_ReadInsight(m_client,m_peerClient,(long)COT_NOW(),a,i)) break;
            lines[i+1]=TimeToString((datetime)a.reportDate,TIME_DATE)+" | "+COT_InsightEvents(a.events);available++;
         }
         ArrayResize(lines,available+3);
         lines[available+1]=available==0?"No verified history. Start the service and update data.":"EA historical reads: use your decision time asOf UTC.";
         lines[available+2]="Alerts: opt-in, selected market, no historical replay.";
      }
      else
      {
         ArrayResize(lines,10);SqCOTInsight a;SqCOTSnapshot s;
         bool valid=COT_ReadInsight(m_client,m_peerClient,(long)COT_NOW(),a);
         bool ready=m_client.ReadLatest(s) && m_client.CanTrade(s);
         lines[0]=selected+" | "+(valid?COT_StatusName(a.dataStatus):"NO VERIFIED DATA")+" | "+(ready?"Data ready":"Data gate closed");
         lines[1]="Hedgers CPI: "+(valid?COT_InsightIndex(a.level):"--")+" | Large speculators: "+(s.generation>0?COT_InsightIndex(s.values[2]):"--");
         lines[2]="Change: "+(a.delta1Valid?COT_InsightDelta(a.delta1):"--")+" / 1 report; "+
            (a.delta4Valid?COT_InsightDelta(a.delta4):"--")+" / 4 reports (index points)";
         lines[3]="Other horizon: "+(valid?COT_InsightIndex(a.otherLevel):"--")+" | "+COT_InsightHorizon(a);
         lines[4]="Extreme duration: "+IntegerToString(a.extremeReports)+(a.durationCapped?"+":"")+" reports (up to 12 inspected)";
         lines[5]="New events: "+(valid?COT_InsightEvents(a.events):"Unavailable");
         lines[6]=valid?"Report: "+TimeToString((datetime)a.reportDate,TIME_DATE)+" | dependency observed: "+
            TimeToString((datetime)a.availableAtUtc,TIME_DATE|TIME_MINUTES)+" UTC":"Start the service and download COT data.";
         lines[7]="COT: "+COT_MarketBase(selected)+" | Chart: "+_Symbol+" | No price confirmation";
         lines[8]="High/low: state. Entry/exit: event. Neither is a trade.";
         lines[9]="Events: report comparisons. Guide: definitions. Hover: full text.";
         if(!valid)
         {
            ArrayResize(lines,3);
            lines[1]="No verified cache. Start SqCOTService and update data.";
            lines[2]="Guide explains CPI, CTI, events and horizon comparisons.";
         }
      }
      int maxLines=MathMax(0,(height-y-Px(28))/Px(21));
      for(int i=0;i<ArraySize(lines) && n<maxLines;i++,n++,y+=Px(21)) InsightLine(n,lines[i],x,y,w);
      if(n<ArraySize(lines)) {InsightLine(n,"Enlarge chart height for remaining details.",x,y,w,clrOrange);y+=Px(21);}
      Box("background",x,top,w,y-top+Px(8),C'22,28,37');End();
   }
public:
   CotMarketPrefs prefs;
   void Init(const string prefix,const string path,const string id,const string favorites,
             const bool enabled,const bool remember,const int top=24,const bool eventPopup=false,const bool eventPush=false)
   {
      m_prefix=prefix+"markets."; m_path=path; m_enabled=enabled; m_remember=remember;
      m_width=-1; m_height=-1; m_dataWeeks=0; m_pageSize=8;
      m_top=top;
      m_eventPopup=eventPopup;m_eventPush=eventPush;m_started=(long)COT_NOW();m_expected=0;m_lastEvent="";
      m_baselined=false;m_eventReport=0;m_eventMask=0;m_analyticsToken="";m_alertValid=false;
      m_insightVersion="";
      m_scale=MathMax(1.0,MathMin(2.5,TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0));
      m_dataVersion=""; m_signature=""; m_dirty=true; m_orderDirty=true;
      COT_MarketDefaults(prefs,id,favorites);
      if(remember)
      {
         string saved;
         if(COT_ReadText(m_path,saved,0)) COT_MarketParse(saved,prefs);
      }
   }
   void Save() {if(m_remember) COT_MarketSavePrefs(m_path,prefs);}
   void Invalidate() {m_dirty=true;}
   void Destroy() {m_client.Close();m_peerClient.Close();ObjectsDeleteAll(0,m_prefix);}
   int RowCount() {return ArraySize(m_rows);}
   void Render(const string selected,const datetime report)
   {
      if(!m_enabled) return;
      int width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
      int height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
      PrepareInsights(selected);
      string signature=COT_GetDatasetVersion()+"|"+selected+"|"+IntegerToString((long)report)+"|"+
         IntegerToString(m_expected)+"|"+IntegerToString(m_client.Generation())+"|"+IntegerToString(m_peerClient.Generation());
      if(!m_dirty && signature==m_signature && width==m_width && height==m_height) return;
      m_dirty=false; m_signature=signature; m_width=width; m_height=height;
      ArrayFree(m_touched);
      int x=Px(8),top=Px(m_top),w=MathMin(Px(prefs.expanded?900:540),width-2*x);
      if(w<Px(110) || height<top+Px(38)) {End(); return;}
      // Create the background before all controls, then size it after layout.
      Box("background",x,top,w,Px(34),C'22,28,37');
      Button("toggle",prefs.expanded?"Markets -":"Markets +",x+Px(6),top+Px(5),Px(88),Px(24),C'45,65,89');
      string tabs[3]={"Summary","Events","Guide"};
      for(int t=0;t<3;t++)
         if(w>=Px(346)) Button("view"+IntegerToString(t+1),tabs[t]+(prefs.view==t+1?" -":" +"),
            x+Px(98+t*80),top+Px(5),Px(76),Px(24),prefs.view==t+1?C'48,94,141':C'42,51,65');
      if(w<Px(346))
      {
         if(w>=Px(185)) Button("view1",prefs.view>0?"Close":"Summary +",x+Px(98),top+Px(5),Px(80),Px(24),C'42,51,65');
         if(prefs.view>1) prefs.view=1;
      }
      string title=COT_MarketName(COT_MarketBase(selected))+" | "+selected;
      if(report>0) title+=" | "+TimeToString(report,TIME_DATE);
      if(w>Px(440)) Label("title",title,x+Px(342),top+Px(9),w-Px(350),clrGainsboro);
      if(prefs.view>0) {RenderInsights(selected,x,top,w,height);return;}
      if(!prefs.expanded) {End(); return;}
      EnsureData();
      if(w<Px(320) || height<top+Px(270))
      {
         Label("small","Enlarge the chart to view the market table.",x+Px(8),top+Px(42),w-Px(16));
         Box("background",x,top,w,Px(67),C'22,28,37'); End(); return;
      }
      int y=top+Px(38),cx=x+Px(8),right=x+w-Px(8);
      string keys[8]={"52","156","metric","filter","sort","refresh","compare","events"};
      string labels[8];
      labels[0]="52W"; labels[1]="156W"; labels[2]=prefs.metric==0?"CPI":"CTI";
      labels[3]=prefs.favoritesOnly?"Favorites":"All markets";
      labels[4]=prefs.sort==0?"Sort: name":(prefs.sort==1?"Sort: change":"Sort: level");
      labels[5]="Re-sort";
      labels[6]=prefs.compare?"Compare: on":"Compare: off";labels[7]=prefs.eventsOnly?"New events":"All states";
      int widths[8]={44,48,48,94,106,62,92,86};
      for(int i=0;i<8;i++)
      {
         if(cx+Px(widths[i])>right) {cx=x+Px(8); y+=Px(28);}
         bool active=(i==0 && prefs.weeks==52) || (i==1 && prefs.weeks==156);
         string tip=i==2?"CPI = position index; CTI = trader participation index. Click to switch.":labels[i];
         Button(keys[i],labels[i],cx,y,Px(widths[i]),Px(24),active?C'48,94,141':C'42,51,65',tip);
         cx+=Px(widths[i]+4);
      }
      if(cx+Px(154)>right) {cx=x+Px(8); y+=Px(28);}
      Label("searchlabel","Find",cx,y+Px(5),Px(28));
      if(Object("search",OBJ_EDIT))
      {
         string name=m_prefix+"search";
         ObjectSetInteger(0,name,OBJPROP_XDISTANCE,cx+Px(30)); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
         ObjectSetInteger(0,name,OBJPROP_XSIZE,Px(112)); ObjectSetInteger(0,name,OBJPROP_YSIZE,Px(24));
         ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8); ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
         ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'35,43,55'); ObjectSetInteger(0,name,OBJPROP_READONLY,false);
         ObjectSetInteger(0,name,OBJPROP_ZORDER,13);
         ObjectSetString(0,name,OBJPROP_TEXT,prefs.search);
         ObjectSetString(0,name,OBJPROP_TOOLTIP,"Search market names or codes; press Enter to apply. Clear to reset.");
      }
      y+=Px(29);
      Label("context",prefs.compare?"Same-report horizons | d1 / d4 in index points | 12-report mini history":"Report dates | Index /100 | Change in index points",
            x+Px(8),y,w-Px(16));
      y+=Px(22);
      // Compact layouts keep the date and hedger value; other values remain
      // available in each row's tooltip. CTI has no small-trader column.
      bool large=w>=Px(490),small=prefs.metric==0 && w>=Px(610);
      bool delta=w>=Px(710),event=w>=Px(840);
      int starW=Px(26),dateW=Px(84),valueW=Px(66),deltaW=delta?Px(65):0,eventW=event?Px(112):0;
      int count=1+(large?1:0)+(small?1:0);
      int nameW=w-Px(16)-starW-dateW-count*valueW-deltaW-eventW;
      int col=x+Px(8)+starW;
      Label("hname","Market",col,y,nameW); col+=nameW;
      Label("hh","Hedgers",col,y,valueW); col+=valueW;
      if(large) {Label("hl",prefs.compare?(prefs.weeks==52?"156W":"52W"):"Large spec.",col,y,valueW); col+=valueW;}
      if(small) {Label("hs",prefs.compare?"d4":"Small",col,y,valueW); col+=valueW;}
      if(delta) {Label("hd","H change",col,y,deltaW); col+=deltaW;}
      Label("hdate","Report date",col,y,dateW); col+=dateW;
      if(event) Label("he",prefs.compare?"Last 12 / zone":"Hedger event",col,y,eventW);
      y+=Px(20);
      int available=height-y-Px(63);
      m_pageSize=MathMax(1,MathMin(10,available/Px(27)));
      int total=ArraySize(m_order),pages=MathMax(1,(total+m_pageSize-1)/m_pageSize);
      prefs.page=MathMax(0,MathMin(prefs.page,pages-1));
      datetime newest=0;
      for(int i=0;i<ArraySize(m_rows);i++) if(m_rows[i].date>newest) newest=m_rows[i].date;
      if(total==0)
      {
         string empty=ArraySize(m_rows)==0?"No cached markets. Use Update COT Data in the indicator.":
                      "No matches. Switch to All markets or clear Find.";
         Label("empty",empty,x+Px(8),y+Px(5),w-Px(16)); y+=Px(30);
      }
      for(int pos=prefs.page*m_pageSize;pos<MathMin(total,(prefs.page+1)*m_pageSize);pos++)
      {
         CotMarketRow r=m_rows[m_order[pos]];
         string tip=RowTooltip(r),key="pick."+r.id+".";
         bool selectedRow=r.id==selected;
         color neutral=selectedRow?C'46,78,104':C'32,40,52';
         col=x+Px(8);
         Button("fav."+r.base,COT_MarketHasFavorite(prefs.favorites,r.base)?"*":"+",col,y,starW-Px(2),Px(25),
                C'42,51,65',"Add/remove "+r.name+" from Favorites"); col+=starW;
         Button(key+"name",r.name+" ("+r.base+")",col,y,nameW-Px(2),Px(25),neutral,tip); col+=nameW;
         Button(key+"h",COT_MarketPercent(r.values[prefs.metric]),col,y,valueW-Px(2),Px(25),
                COT_MarketColor(r.values[prefs.metric]),tip); col+=valueW;
         if(large)
         {
            int field=prefs.metric==0?2:3;
            double value=prefs.compare?r.peer[prefs.metric]:r.values[field];
            Button(key+"l",COT_MarketPercent(value),col,y,valueW-Px(2),Px(25),COT_MarketColor(value),tip); col+=valueW;
         }
         if(small)
         {Button(key+"s",prefs.compare?(r.insights[prefs.metric].delta4Valid?COT_InsightDelta(r.insights[prefs.metric].delta4):"--"):COT_MarketPercent(r.values[4]),col,y,valueW-Px(2),Px(25),prefs.compare?neutral:COT_MarketColor(r.values[4]),tip); col+=valueW;}
         if(delta)
         {Button(key+"d",COT_MarketDeltaText(r,prefs.metric),col,y,deltaW-Px(2),Px(25),neutral,tip); col+=deltaW;}
         bool older=m_expected>0 && r.date<m_expected;
         string date=r.date==0?"--":TimeToString(r.date,TIME_DATE);
         if(older) date+=" *";
         Button(key+"date",date,col,y,dateW-Px(2),Px(25),older?C'91,68,39':neutral,tip); col+=dateW;
         if(event && !prefs.compare) Button(key+"e",COT_MarketEvent(r,prefs.metric),col,y,eventW-Px(2),Px(25),neutral,tip);
         if(event && prefs.compare)
         {
            Button(key+"e","",col,y,eventW-Px(2),Px(25),neutral,tip);
            for(int k=0;k<12;k++)
            {
               double v=r.trail[prefs.metric*12+11-k];
               int h=COT_MarketValid(v)?MathMax(2,(int)MathRound(18*v)):2;
               Box(key+"spark"+IntegerToString(k),col+Px(3+k*6),y+Px(22-h),Px(4),Px(h),COT_MarketColor(v));
            }
            Label(key+"run",IntegerToString(r.insights[prefs.metric].extremeReports)+(r.insights[prefs.metric].durationCapped?"+":""),col+Px(78),y+Px(5),Px(30));
         }
         y+=Px(27);
      }
      y+=Px(4);
      Button("prev","<",x+Px(8),y,Px(28),Px(22),C'42,51,65');
      Button("next",">",x+Px(40),y,Px(28),Px(22),C'42,51,65');
      Label("page",IntegerToString(prefs.page+1)+"/"+IntegerToString(pages)+" | "+IntegerToString(total)+" markets",
            x+Px(76),y+Px(4),w-Px(90));
      y+=Px(27);
      Label("foot",m_expected>0?"* Expected report missing | Blue: low / Orange: high | SpreadCharts":"Schedule unknown: freshness unverified | Blue: low / Orange: high | SpreadCharts",
            x+Px(8),y,w-Px(16));
      Box("background",x,top,w,y-top+Px(24),C'22,28,37');
      End();
   }
   // Return selected identifier separately, so the indicator can validate it
   // before replacing its active buffers. All other actions are UI-only.
   bool Handle(const int event,const string object,string &selection)
   {
      selection="";
      if(!m_enabled || StringFind(object,m_prefix)!=0) return false;
      string key=StringSubstr(object,StringLen(m_prefix));
      if(event==CHARTEVENT_OBJECT_ENDEDIT && key=="search")
      {
         prefs.search=StringSubstr(COT_Trim(ObjectGetString(0,object,OBJPROP_TEXT)),0,64);
         StringReplace(prefs.search,"\n",""); StringReplace(prefs.search,"\r","");
         prefs.page=0; m_orderDirty=true;
      }
      else if(event==CHARTEVENT_OBJECT_CLICK)
      {
         if(key=="toggle") {prefs.expanded=!prefs.expanded;prefs.view=0;}
         else if(key=="view1" || key=="view2" || key=="view3")
         {int view=(int)StringToInteger(StringSubstr(key,4));prefs.view=prefs.view==view?0:view;prefs.expanded=false;}
         else if(key=="compare") prefs.compare=!prefs.compare;
         else if(key=="events") {prefs.eventsOnly=!prefs.eventsOnly;prefs.page=0;m_orderDirty=true;}
         else if(key=="52" || key=="156") {prefs.weeks=(int)StringToInteger(key); prefs.page=0; m_orderDirty=true;}
         else if(key=="metric") {prefs.metric=1-prefs.metric; prefs.page=0; m_orderDirty=true;}
         else if(key=="filter") {prefs.favoritesOnly=!prefs.favoritesOnly; prefs.page=0; m_orderDirty=true;}
         else if(key=="sort") {prefs.sort=(prefs.sort+1)%3; prefs.page=0; m_orderDirty=true;}
         else if(key=="refresh") m_orderDirty=true;
         else if(key=="prev") prefs.page=MathMax(0,prefs.page-1);
         else if(key=="next") prefs.page++;
         else if(StringFind(key,"fav.")==0)
         {COT_MarketToggleFavorite(prefs,StringSubstr(key,4)); m_orderDirty=true;}
         else if(StringFind(key,"pick.")==0)
         {
            int end=StringFind(key,".",5);
            if(end>5) selection=StringSubstr(key,5,end-5);
         }
         else return true;
      }
      else return false;
      m_dirty=true; Save();
      return true;
   }
};
#endif
