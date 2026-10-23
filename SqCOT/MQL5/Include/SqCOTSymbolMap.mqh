// Shared, local-only CFD -> COT resolver. Raw COT values are never transformed.
#ifndef __SQ_COT_SYMBOL_MAP_MQH__
#define __SQ_COT_SYMBOL_MAP_MQH__
#include <SqCOTPit.mqh>
#include <SqCOTProtocol.mqh>
#ifndef COT_CONFIG_DIR
#define COT_CONFIG_DIR "StrategyQuant\\COT\\config"
#endif
#define COT_MAP_FILE COT_CONFIG_DIR "\\symbol-map.csv"
#define COT_MAP_HEADER "schema;market_id;display_name;broker_server;aliases_direct;aliases_inverse;enabled;note"
#define COT_MAP_RESOLVER "1"
struct CotMapRow {string market,name,server,direct,inverse,note;bool enabled;};
struct CotMapResult {string status,market,series,orientation,source,hash,error;};
string COT_MapHash(const string text)
{uchar bytes[];int n=StringToCharArray(text,bytes,0,WHOLE_ARRAY,CP_UTF8);ArrayResize(bytes,n-1);return COT_Hash(bytes);}
string COT_MapBase(const string id)
{
   int n=StringLen(id);
   if(n>4 && StringSubstr(id,n-4)=="_52W") return StringSubstr(id,0,n-4);
   if(n>5 && StringSubstr(id,n-5)=="_156W") return StringSubstr(id,0,n-5);
   return id;
}
int COT_MapWeeks(const string id)
{string b=COT_MapBase(id);return b==id?0:(StringSubstr(id,StringLen(b))=="_52W"?52:156);}
string COT_MapQuote(string text)
{StringReplace(text,"\"","\"\"");return "\""+text+"\"";}
// Strict UTF-8 round trip rejects invalid byte sequences, embedded NUL and oversized files.
bool COT_MapRead(const string path,string &text)
{
   uchar bytes[],again[];
   if(!COT_ReadBytes(path,bytes,COT_FILE_SCOPE,262144)) return false;
   text=CharArrayToString(bytes,0,ArraySize(bytes),CP_UTF8);
   int n=StringToCharArray(text,again,0,WHOLE_ARRAY,CP_UTF8)-1;
   if(n!=ArraySize(bytes)) return false;
   for(int i=0;i<n;i++) if(bytes[i]!=again[i] || bytes[i]==0) return false;
   return true;
}
// Flat table; fixed-width records with quoted semicolons, newlines and escaped quotes.
bool COT_MapCsv(string text,const int columns,string &cells[],string &error)
{
   ArrayFree(cells);error="";
   if(StringLen(text)>0 && StringGetCharacter(text,0)==0xFEFF) text=StringSubstr(text,1);
   bool quoted=false,closed=false;string cell="";int col=0,line=1;
   for(int i=0;i<=StringLen(text);i++)
   {
      ushort c=i<StringLen(text)?StringGetCharacter(text,i):'\n';
      if(i==StringLen(text) && cell=="" && col==0 && !quoted && !closed) break;
      if(quoted)
      {
         if(c=='"')
         {if(i+1<StringLen(text) && StringGetCharacter(text,i+1)=='"'){cell+="\"";i++;}else{quoted=false;closed=true;}}
         else {if(i==StringLen(text)){error="Unclosed quote";break;}cell+=ShortToString(c);if(c=='\n')line++;}
      }
      else if(c=='"' && cell=="" && !closed) quoted=true;
      else if(c==';' || c=='\n' || c=='\r')
      {
         int n=ArraySize(cells);ArrayResize(cells,n+1);cells[n]=cell;cell="";closed=false;col++;
         if(c!=';')
         {
            if(col!=columns){error="Expected "+IntegerToString(columns)+" columns";break;}
            col=0;line++;if(c=='\r' && i+1<StringLen(text) && StringGetCharacter(text,i+1)=='\n') i++;
         }
         if(ArraySize(cells)>8192*columns){error="Too many rows";break;}
      }
      else if(closed || c=='"' || c==0 || (c<32 && c!='\t')) {error="Unexpected character";break;}
      else cell+=ShortToString(c);
      if(StringLen(cell)>4096){error="Cell exceeds 4096 characters";break;}
   }
   if(error!="") {error="Line "+IntegerToString(line)+", column "+IntegerToString(col+1)+": "+error;return false;}
   return ArraySize(cells)>=columns && ArraySize(cells)%columns==0;
}
bool COT_MapAliases(string &list,string &error)
{
   if(list=="") return true;
   string parts[];int n=StringSplit(list,'|',parts);list="";
   for(int i=0;i<n;i++)
   {
      string a=COT_Trim(parts[i]);StringToUpper(a);
      if(a=="" || StringLen(a)>128 || StringFind(a,"*")>=0 || StringFind(a,"?")>=0 ||
         StringFind(a,"\n")>=0 || StringFind(a,"\r")>=0 || StringFind(a,"\t")>=0)
      {error="Invalid exact alias";return false;}
      if(StringFind("|"+list+"|","|"+a+"|")>=0){error="Duplicate alias "+a;return false;}
      list+=(i>0?"|":"")+a;
   }
   return true;
}
bool COT_MapHas(const string list,const string alias)
{return list!="" && StringFind("|"+list+"|","|"+alias+"|")>=0;}
bool COT_MapParse(const string text,CotMapRow &rows[],string &error)
{
   string c[];ArrayFree(rows);
   if(!COT_MapCsv(text,8,c,error)) return false;
   string header="";for(int i=0;i<8;i++)header+=(i>0?";":"")+c[i];
   if(header!=COT_MAP_HEADER){error="Line 1: invalid schema header";return false;}
   for(int at=8;at<ArraySize(c);at+=8)
   {
      CotMapRow r;r.market=c[at+1];r.name=c[at+2];r.server=c[at+3];r.direct=c[at+4];r.inverse=c[at+5];r.enabled=c[at+6]=="1";r.note=c[at+7];
      string upper=r.market;StringToUpper(upper);
      if(c[at]!="1" || !COT_SafeName(r.market) || upper!=r.market || r.name=="" ||
         r.server=="" || StringLen(r.server)>128 || StringFind(r.server,"\n")>=0 || StringFind(r.server,"\r")>=0 ||
         (c[at+6]!="0" && c[at+6]!="1")) error="Invalid schema, market, name, server or enabled value";
      if(error=="" && (!COT_MapAliases(r.direct,error) || !COT_MapAliases(r.inverse,error))) {}
      for(int j=0;error=="" && j<ArraySize(rows);j++)
         if(rows[j].market==r.market && rows[j].server==r.server) error="Duplicate market/server key";
      string aliases[];int count=StringSplit(r.direct+(r.direct!="" && r.inverse!=""?"|":"")+r.inverse,'|',aliases);
      for(int a=0;error=="" && a<count;a++)
      {
         if(aliases[a]=="")continue;
         if(COT_MapHas(r.direct,aliases[a]) && COT_MapHas(r.inverse,aliases[a])) error="AMBIGUOUS alias "+aliases[a];
         for(int j=0;error=="" && j<ArraySize(rows);j++)
            if(rows[j].server==r.server && (COT_MapHas(rows[j].direct,aliases[a]) || COT_MapHas(rows[j].inverse,aliases[a])))
               error="AMBIGUOUS alias "+aliases[a];
      }
      if(error!=""){error="Record "+IntegerToString(at/8+1)+": "+error;ArrayFree(rows);return false;}
      int n=ArraySize(rows);ArrayResize(rows,n+1);rows[n]=r;
   }
   return true;
}
string COT_MapDefaults()
{
   return COT_MAP_HEADER+"\n"
      "1;GC;Gold;*;XAUUSD|GOLD;;1;Gold priced in USD\n"
      "1;SI;Silver;*;XAGUSD|SILVER;;1;Silver priced in USD\n"
      "1;6E;Euro;*;EURUSD;;1;\n1;6B;British pound;*;GBPUSD;;1;\n"
      "1;6A;Australian dollar;*;AUDUSD;;1;\n1;6N;New Zealand dollar;*;NZDUSD;;1;\n"
      "1;6J;Japanese yen;*;;USDJPY;1;Inverse quote - raw COT values unchanged\n"
      "1;6C;Canadian dollar;*;;USDCAD;1;Inverse quote\n1;6S;Swiss franc;*;;USDCHF;1;Inverse quote\n"
      "1;ES;S&P 500;*;US500|SPX500;;1;Verify broker contract specification\n"
      "1;NQ;Nasdaq 100;*;NAS100|USTEC;;1;Verify broker contract specification\n"
      "1;YM;Dow Jones;*;US30;;1;Verify broker contract specification\n"
      "1;CL;WTI crude oil;*;WTI|XTIUSD;;1;Not Brent\n";
}
bool COT_MapMetadata(string &text,string &version,string &ids[])
{
   datetime updated;int lock=COT_Lock("cache");if(lock==INVALID_HANDLE)return false;
   bool ok=COT_ReadText(COT_METADATA_FILE,text) && COT_ParseMetadata(text,version,updated,ids);
   FileClose(lock);return ok;
}
void COT_MapResolve(const CotMapRow &rows[],string symbol,const string server,const int weeks,
                    const string &ids[],const string hash,CotMapResult &result)
{
   ZeroMemory(result);result.hash=hash;result.status="UNMAPPED";StringToUpper(symbol);
   for(int scope=0;scope<2;scope++) for(int i=0;i<ArraySize(rows);i++)
   {
      if(rows[i].server!=(scope==0?server:"*")) continue;
      bool direct=COT_MapHas(rows[i].direct,symbol),inverse=COT_MapHas(rows[i].inverse,symbol);
      if(!direct && !inverse) continue;
      result.market=rows[i].market;result.orientation=inverse?"INVERSE":"DIRECT";
      result.source=rows[i].server;result.status=rows[i].enabled?"SERIES_UNAVAILABLE":"DISABLED";
      if(!rows[i].enabled)return;
      for(int j=0;j<ArraySize(ids);j++) if(COT_MapBase(ids[j])==result.market && COT_MapWeeks(ids[j])==weeks)
      {result.series=ids[j];result.status="RESOLVED";return;}
      return; // Never substitute another horizon or a global disabled override.
   }
}
// Recover only an immutable revision whose content hash and parser both validate.
bool COT_MapLastGood(string &text)
{
   string pointer;CotMapRow rows[];string error;
   if(!COT_ReadText(COT_CONFIG_DIR+"\\active.dat",pointer))return false;
   string hash=COT_Trim(pointer);
   return StringLen(hash)==64 && COT_SafeName(hash) && COT_MapRead(COT_CONFIG_DIR+"\\active\\"+hash+".csv",text) &&
      COT_MapHash(text)==hash && COT_MapParse(text,rows,error);
}
bool COT_MapPublish(const string text)
{
   string hash=COT_MapHash(text),path=COT_CONFIG_DIR+"\\active\\"+hash+".csv",old;
   if(!COT_MapRead(path,old) || COT_MapHash(old)!=hash) if(!COT_WriteText(path,text))return false;
   if(COT_ReadText(COT_CONFIG_DIR+"\\active.dat",old) && COT_Trim(old)==hash)return true;
   return COT_WriteText(COT_CONFIG_DIR+"\\active.dat",hash+"\n");
}
// Optimistic compare-and-publish: a changed/locked editor file is retried next minute.
bool COT_MapReplace(const string original,const bool existed,const string replacement)
{
   string path=COT_MAP_FILE+".pending",check;
   if(!COT_WriteText(path,replacement))return false;
   if(existed) {if(!COT_MapRead(COT_MAP_FILE,check) || check!=original)return false;}
   else if(FileIsExist(COT_MAP_FILE,COT_FILE_SCOPE))return false;
   return FileMove(path,COT_FILE_SCOPE,COT_MAP_FILE,COT_FILE_SCOPE|FILE_REWRITE);
}
bool COT_MapSync(string &error)
{
   static string synced="";
   error="";int lock=COT_Lock("symbol-map");if(lock==INVALID_HANDLE){error="CONFIG_BUSY";return false;}
   bool existed=FileIsExist(COT_MAP_FILE,COT_FILE_SCOPE);string original,text;
   string metadata,version,ids[];bool catalog=COT_MapMetadata(metadata,version,ids);
   CotMapRow rows[];
   if(existed && !COT_MapRead(COT_MAP_FILE,original))error="CONFIG_INVALID: unreadable CSV or invalid UTF-8";
   if(existed)text=original;
   else if(!COT_MapLastGood(text))
   {
      if(FileIsExist(COT_CONFIG_DIR+"\\active.dat",COT_FILE_SCOPE))error="CONFIG_INVALID: recovery revision is damaged";
      else text=COT_MapDefaults();
   }
   string signature=COT_MapHash(text)+"|"+metadata;
   if(error=="" && existed && signature==synced && FileIsExist(COT_CONFIG_DIR+"\\active.dat",COT_FILE_SCOPE) &&
      (!catalog || FileIsExist(COT_CONFIG_DIR+"\\catalog.csv",COT_FILE_SCOPE)))
   {FileClose(lock);return true;}
   if(error=="" && !COT_MapParse(text,rows,error))error="CONFIG_INVALID: "+error;
   if(error=="" && catalog)
   {
      string output="series_id;market_id;horizon;report_type;available;source_generation\n";
      for(int i=0;i<ArraySize(ids);i++)
      {
         string market=COT_MapBase(ids[i]);
         output+=ids[i]+";"+market+";"+IntegerToString(COT_MapWeeks(ids[i]))+";provider;1;"+version+"\n";
         bool found=false;for(int j=0;j<ArraySize(rows);j++) if(rows[j].market==market && rows[j].server=="*"){found=true;break;}
         if(!found)
         {
            if(StringLen(text)>0 && StringSubstr(text,StringLen(text)-1)!="\n")text+="\n";
            text+="1;"+market+";"+market+";*;;;1;No approved CFD alias yet\n";
            // Append a row once, even when several horizons share a market.
            int n=ArraySize(rows);ArrayResize(rows,n+1);rows[n].market=market;rows[n].server="*";
         }
      }
      string old,cells[],csvError;
      if(COT_MapRead(COT_CONFIG_DIR+"\\catalog.csv",old) && COT_MapCsv(old,6,cells,csvError))
         for(int at=6;at<ArraySize(cells);at+=6)
         {
            bool present=false;for(int j=0;j<ArraySize(ids);j++)if(ids[j]==cells[at]){present=true;break;}
            if(!present)output+=cells[at]+";"+cells[at+1]+";"+cells[at+2]+";provider;0;"+version+"\n";
         }
      if(old!=output && !COT_WriteText(COT_CONFIG_DIR+"\\catalog.csv",output))error="Cannot publish catalog";
   }
   if(error=="" && !COT_MapParse(text,rows,error))error="CONFIG_INVALID: "+error;
   if(error=="" && (!existed || text!=original) && !COT_MapReplace(original,existed,text))error="CONFIG_CHANGED_DURING_WRITE";
   if(error=="" && !COT_MapPublish(text))error="Cannot publish validated mapping revision";
   if(error=="")
   {
      string info="SCHEMA=1\nRESOLVER="+COT_MAP_RESOLVER+"\nHASH="+COT_MapHash(text)+"\nSOURCE_GENERATION="+version+
         "\nSOURCE_HASH="+COT_MapHash(metadata)+"\n";
      if(!COT_WriteText(COT_CONFIG_DIR+"\\active-info.dat",info))error="Cannot publish mapping provenance";
      else synced=COT_MapHash(text)+"|"+metadata;
   }
   FileClose(lock);return error=="";
}
class CCOTSymbolMap
{
private:
   CotMapRow m_rows[];
   string m_ids[],m_hash,m_error,m_signature,m_source;
   ulong m_last;
   bool m_loaded,m_pinned;
public:
   CCOTSymbolMap(){m_last=0;m_loaded=false;m_pinned=false;m_hash="";m_error="";m_signature="";m_source="";}
   string Error()const{return m_error;}
   string Hash()const{return m_hash;}
   int Count()const{return ArraySize(m_rows);}
   bool Row(const int index,CotMapRow &row){if(index<0 || index>=ArraySize(m_rows))return false;row=m_rows[index];return true;}
   bool Available(const string market)
   {for(int i=0;i<ArraySize(m_ids);i++)if(COT_MapBase(m_ids[i])==market)return true;return false;}
   int SeriesCount()const{return ArraySize(m_ids);}
   // Manual browse supports unknown provider variants without inventing a horizon suffix.
   string SeriesFor(const string market,const int weeks)
   {
      for(int i=0;i<ArraySize(m_ids);i++)if(COT_MapBase(m_ids[i])==market &&
         (COT_MapWeeks(m_ids[i])==weeks || COT_MapWeeks(m_ids[i])==0))return m_ids[i];
      return "";
   }
   void Reset(){m_pinned=false;m_loaded=false;m_last=0;m_hash="";m_signature="";m_error="";ArrayFree(m_rows);ArrayFree(m_ids);}
   bool Load(const bool force=false)
   {
      if(m_pinned)return m_loaded;
      ulong tick=GetTickCount64();
      if(!force && m_last!=0 && tick>=m_last && tick-m_last<60000)return m_loaded && m_error=="";
      m_last=tick;string text,meta,version,ids[],error;
      int lock=COT_Lock("symbol-map");if(lock==INVALID_HANDLE){m_error="CONFIG_BUSY";return false;}
      bool exists=FileIsExist(COT_MAP_FILE,COT_FILE_SCOPE),ok=true;
      m_source="CSV";
      if(exists)ok=COT_MapRead(COT_MAP_FILE,text);
      else if(COT_MapLastGood(text))m_source="RECOVERED";
      else if(FileIsExist(COT_CONFIG_DIR+"\\active.dat",COT_FILE_SCOPE))ok=false;
      else{text=COT_MapDefaults();m_source="EMBEDDED";}
      FileClose(lock);
      if(!ok){m_error="CONFIG_INVALID: unreadable CSV or recovery revision";return false;}
      bool haveCatalog=COT_MapMetadata(meta,version,ids);
      if(!haveCatalog)ArrayFree(ids);
      string signature=COT_MapHash(text)+"|"+meta;
      if(signature==m_signature && m_loaded){m_error="";return true;}
      CotMapRow parsed[];
      if(!COT_MapParse(text,parsed,error)){m_error="CONFIG_INVALID: "+error;return false;}
      ArrayResize(m_rows,ArraySize(parsed));for(int i=0;i<ArraySize(parsed);i++)m_rows[i]=parsed[i];
      ArrayCopy(m_ids,ids);ArrayResize(m_ids,ArraySize(ids));
      // Browse the complete catalog even while the service has not yet appended the CSV.
      for(int i=0;i<ArraySize(ids);i++)
      {
         string market=COT_MapBase(ids[i]);bool found=false;
         for(int j=0;j<ArraySize(m_rows);j++)if(m_rows[j].market==market && m_rows[j].server=="*"){found=true;break;}
         if(!found)
         {
            CotMapRow row;row.market=market;row.name=market;row.server="*";row.enabled=true;row.direct="";row.inverse="";
            row.note="Pending service CSV synchronization; no approved alias";
            int n=ArraySize(m_rows);ArrayResize(m_rows,n+1);m_rows[n]=row;
         }
      }
      m_signature=signature;m_hash=COT_MapHash(text);m_loaded=true;m_error="";return true;
   }
   bool Resolve(const string symbol,const string server,const int weeks,CotMapResult &result,const bool force=false)
   {
      bool ok=Load(force);COT_MapResolve(m_rows,symbol,server,weeks,m_ids,m_hash,result);
      if(!ok){result.status="CONFIG_INVALID";result.error=m_error;return false;}
      if(m_source!="CSV" && !m_pinned)result.source=m_source+":"+result.source;
      return result.status=="RESOLVED";
   }
   bool OpenSnapshot(const string directory,const string symbol,const string server,const int weeks,CotMapResult &result)
   {
      Reset();m_pinned=true;string text,manifest,source,digest,version;datetime updated;
      bool ok=COT_MapRead(directory+"\\symbol-map.csv",text) && COT_ReadText(directory+"\\mapping.dat",manifest) &&
         COT_ReadText(directory+"\\mapping.sha256",digest) && COT_Trim(digest)==COT_MapHash(manifest) &&
         COT_Field(manifest,"RESOLVER")==COT_MAP_RESOLVER && COT_Field(manifest,"SYMBOL")==symbol &&
         COT_Field(manifest,"SERVER")==server && COT_Field(manifest,"HASH")==COT_MapHash(text) &&
         COT_ReadText(directory+"\\source.dat",source) && COT_Field(manifest,"SOURCE_HASH")==COT_MapHash(source) &&
         COT_ParseMetadata(source,version,updated,m_ids) && COT_MapParse(text,m_rows,m_error);
      if(!ok){m_error="MAPPING_SNAPSHOT_INVALID_OR_MISSING";ZeroMemory(result);result.status=m_error;return false;}
      m_loaded=true;m_hash=COT_MapHash(text);m_source="SNAPSHOT";
      return Resolve(symbol,server,weeks,result);
   }
};
bool COT_MapExport(const string directory,const string source,const string symbol,const string server)
{
   int lock=COT_Lock("symbol-map");if(lock==INVALID_HANDLE)return false;
   string text,error;CotMapRow rows[];
   bool ok=COT_MapRead(COT_MAP_FILE,text) && COT_MapParse(text,rows,error);
   if(!FileIsExist(COT_MAP_FILE,COT_FILE_SCOPE))
   {ok=COT_MapLastGood(text);if(!ok && !FileIsExist(COT_CONFIG_DIR+"\\active.dat",COT_FILE_SCOPE)){text=COT_MapDefaults();ok=true;}}
   string manifest="RESOLVER="+COT_MAP_RESOLVER+"\nHASH="+COT_MapHash(text)+"\nSOURCE_HASH="+COT_MapHash(source)+
      "\nSYMBOL="+symbol+"\nSERVER="+server+"\n";
   string description=SymbolInfoString(symbol,SYMBOL_DESCRIPTION),basis=SymbolInfoString(symbol,SYMBOL_BASIS);
   StringReplace(description,"\n"," ");StringReplace(description,"\r"," ");
   StringReplace(basis,"\n"," ");StringReplace(basis,"\r"," ");
   manifest+="DESCRIPTION="+description+"\nBASIS="+basis+"\nBASE="+SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE)+
      "\nPROFIT="+SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT)+"\n";
   if(ok)ok=COT_WriteText(directory+"\\symbol-map.csv",text) && COT_WriteText(directory+"\\mapping.dat",manifest) &&
      COT_WriteText(directory+"\\mapping.sha256",COT_MapHash(manifest)+"\n");
   FileClose(lock);return ok;
}
#endif
