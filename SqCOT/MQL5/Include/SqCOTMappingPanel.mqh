// Compact mapping inspector. Editing shared rules is deliberately confined to the CSV.
#ifndef __SQ_COT_MAPPING_PANEL_MQH__
#define __SQ_COT_MAPPING_PANEL_MQH__
#include <SqCOTSymbolMap.mqh>
class CCOTMappingPanel
{
private:
   string m_prefix,m_search;
   int m_page;
   bool m_open,m_unmapped;
   void Control(const string key,const string text,const int window,const int x,const int y,const int w,const bool edit=false)
   {
      string name=m_prefix+key;
      if(ObjectFind(0,name)<0)ObjectCreate(0,name,edit?OBJ_EDIT:OBJ_BUTTON,window,0,0);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,w);ObjectSetInteger(0,name,OBJPROP_YSIZE,20);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'42,51,65');ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'65,77,94');
      ObjectSetInteger(0,name,OBJPROP_BACK,false);ObjectSetInteger(0,name,OBJPROP_ZORDER,20);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);ObjectSetString(0,name,OBJPROP_FONT,"Arial");
      ObjectSetString(0,name,OBJPROP_TEXT,text);ObjectSetString(0,name,OBJPROP_TOOLTIP,text);
   }
public:
   CCOTMappingPanel(){m_prefix="";m_search="";m_open=false;m_page=0;m_unmapped=false;}
   void Init(const string prefix){m_prefix=prefix+"map.";}
   bool IsOpen()const{return m_open;}
   void Collapse(){m_open=false;}
   string Signature(){return IntegerToString((int)m_open)+m_search+IntegerToString(m_page)+IntegerToString((int)m_unmapped);}
   int Render(CCOTSymbolMap &map,const CotMapResult &r,const bool automatic,const string selected,const int weeks,
              const int headerWindow,const int top,const int headerWidth,const int mainTop=64)
   {
      ObjectsDeleteAll(0,m_prefix);
      string title=(automatic?"AUTO | "+_Symbol+" > ":"MANUAL | ")+(automatic?r.market:selected)+" | "+IntegerToString(weeks)+"W";
      if(automatic && r.orientation=="INVERSE")title+=" | INV";
      if(automatic && r.status!="RESOLVED")title+=" | "+r.status;
      Control("toggle",title+(m_open?" -":" +"),headerWindow,10,top,headerWidth-20);
      ObjectSetString(0,m_prefix+"toggle",OBJPROP_TOOLTIP,title+"\n"+r.error+"\n"+SymbolInfoString(_Symbol,SYMBOL_DESCRIPTION)+
         "\nBasis: "+SymbolInfoString(_Symbol,SYMBOL_BASIS)+" | "+SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE)+"/"+SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT));
      if(!m_open)return top+24;
      int window=0,width=MathMin(430,(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)-16);
      int bodyTop=MathMax(34,mainTop),height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
      int pageSize=MathMax(1,MathMin(5,(height-bodyTop-170)/22));
      string bg=m_prefix+"background";
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,5);ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,bodyTop-5);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,width);ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'24,28,34');
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);ObjectSetInteger(0,bg,OBJPROP_BACK,false);
      ObjectSetInteger(0,bg,OBJPROP_ZORDER,19);ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      int y=bodyTop,w=(width-26)/3;
      Control("auto","Auto",window,10,y,w);Control("52","52W",window,13+w,y,w);Control("156","156W",window,16+2*w,y,w);y+=24;
      Control("validate","Validate / load",window,10,y,(width-24)/2);
      Control("path","CSV location",window,12+(width-24)/2,y,(width-24)/2);y+=24;
      ObjectSetString(0,m_prefix+"path",OBJPROP_TOOLTIP,TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\"+COT_MAP_FILE);
      Control("state",(automatic?r.status:"MANUAL")+" | "+(map.Error()==""?r.source:map.Error()),window,10,y,width-20);y+=24;
      ObjectSetString(0,m_prefix+"state",OBJPROP_TOOLTIP,r.error+"\nRevision: "+map.Hash()+"\nRaw CPI/CTI unchanged. INV describes quote orientation only.");
      Control("search",m_search,window,10,y,(width-24)/2,true);
      Control("filter",m_unmapped?"No aliases":"All markets",window,12+(width-24)/2,y,(width-24)/2);y+=24;
      int order[],mapped=0,markets=0;string query=m_search;StringToUpper(query);
      for(int i=0;i<map.Count();i++)
      {
         CotMapRow row;map.Row(i,row);if(row.server!="*")continue;markets++;
         bool aliases=row.direct!="" || row.inverse!="";if(aliases)mapped++;
         string hay=row.market+" "+row.name;StringToUpper(hay);
         if(m_unmapped && aliases)continue;
         if(query!="" && StringFind(hay,query)<0)continue;
         int n=ArraySize(order);ArrayResize(order,n+1);order[n]=i;
      }
      int pages=MathMax(1,(ArraySize(order)+pageSize-1)/pageSize);m_page=MathMax(0,MathMin(m_page,pages-1));
      for(int i=m_page*pageSize;i<MathMin(ArraySize(order),(m_page+1)*pageSize);i++)
      {
         CotMapRow row;map.Row(order[i],row);
         string caption=row.market+" | "+row.name+(map.Available(row.market)?"":" | unavailable");
         Control("select."+row.market,caption,window,10,y,width-20);y+=22;
         ObjectSetString(0,m_prefix+"select."+row.market,OBJPROP_TOOLTIP,caption+"\nDirect: "+row.direct+"\nInverse: "+row.inverse+"\nSelect only for this chart; shared CSV is unchanged.");
      }
      Control("prev","<",window,10,y,26);Control("next",">",window,width-36,y,26);
      Control("count",IntegerToString(m_page+1)+"/"+IntegerToString(pages)+" | "+IntegerToString(map.SeriesCount())+" series",window,40,y,width-80);y+=24;
      Control("coverage",IntegerToString(markets)+" markets | "+IntegerToString(mapped)+" with aliases",window,10,y,width-20);
      ObjectSetInteger(0,bg,OBJPROP_YSIZE,y+28-bodyTop);
      return top+24;
   }
   bool Handle(const int event,const string object,string &action)
   {
      action="";if(StringFind(object,m_prefix)!=0)return false;
      string key=StringSubstr(object,StringLen(m_prefix));
      if(event==CHARTEVENT_OBJECT_ENDEDIT && key=="search")
      {m_search=StringSubstr(ObjectGetString(0,object,OBJPROP_TEXT),0,64);m_page=0;return true;}
      if(event!=CHARTEVENT_OBJECT_CLICK || key=="search")return false;
      if(key=="toggle")m_open=!m_open;
      else if(key=="filter"){m_unmapped=!m_unmapped;m_page=0;}
      else if(key=="prev")m_page--;
      else if(key=="next")m_page++;
      else action=key;
      return true;
   }
};
#endif
