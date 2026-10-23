// Read-only COT API. No networking. Service generations + legacy BIN/CSV.
#ifndef __SQ_COT_READER_MQH__
#define __SQ_COT_READER_MQH__
#include <SqCOTStorage.mqh>
#define COT_FIELD_CPIHEDG  0
#define COT_FIELD_CTIHEDG  1
#define COT_FIELD_CPISPEC  2
#define COT_FIELD_CTISPEC  3
#define COT_FIELD_CPISMALL 4

struct CotSeries
{
   string identifier;
   CotBinRecord records[];
   int count;
   bool loaded;
};
CotSeries g_cotSeries[];
int g_cotSeriesCount=0;
string g_cotVersion="",g_cotLastError="",g_cotDataDir=COT_CACHE_DIR;
datetime g_cotLastUpdate=0;
bool g_cotInitialized=false,g_cotUseCsvFallback=false,g_cotCsvInCommon=false;
string g_cotAvailableIds[];
int g_cotAvailableCount=0;

enum ENUM_COT_SNAPSHOT_STATE {COT_SNAPSHOT_INVALID=-2,COT_SNAPSHOT_BUSY=-1,COT_SNAPSHOT_MISSING=0,COT_SNAPSHOT_READY=1};
ENUM_COT_SNAPSHOT_STATE COT_ReadSnapshotState(string &version,datetime &updated,string &ids[],string &directory)
{
   version="";updated=0;ArrayFree(ids);directory="";
   int lock=COT_Lock("cache");
   if(lock==INVALID_HANDLE) return COT_SNAPSHOT_BUSY;
   bool present=FileIsExist(COT_METADATA_FILE,COT_FILE_SCOPE) || FileIsExist(COT_METADATA_FILE+".previous",COT_FILE_SCOPE);
   string text;
   bool ok=COT_ReadText(COT_METADATA_FILE,text) && COT_ParseMetadata(text,version,updated,ids);
   if(!ok) ok=COT_ReadText(COT_METADATA_FILE+".previous",text) && COT_ParseMetadata(text,version,updated,ids);
   FileClose(lock);
   if(!ok) {version="";updated=0;ArrayFree(ids);return present?COT_SNAPSHOT_INVALID:COT_SNAPSHOT_MISSING;}
   directory=COT_CACHE_DIR+"\\generations\\"+version;
   return COT_SNAPSHOT_READY;
}
bool COT_ReadSnapshot(string &version,datetime &updated,string &ids[],string &directory)
{
   return COT_ReadSnapshotState(version,updated,ids,directory)==COT_SNAPSHOT_READY;
}

bool COT_Initialize()
{
   if(g_cotInitialized) return true;
   g_cotLastError="";
   g_cotUseCsvFallback=false; g_cotCsvInCommon=false; g_cotDataDir=COT_CACHE_DIR;
   ArrayFree(g_cotAvailableIds);
   string text;
   bool ok=COT_ReadSnapshot(g_cotVersion,g_cotLastUpdate,g_cotAvailableIds,g_cotDataDir);
   if(!ok && (FileIsExist(COT_METADATA_FILE,COT_FILE_SCOPE) || FileIsExist(COT_METADATA_FILE+".previous",COT_FILE_SCOPE)))
   {g_cotLastError="COT cache is busy or its metadata is invalid. Retry shortly."; return false;}
   if(!ok && COT_ReadText(COT_MANIFEST_FILE,text))
      ok=COT_ParseMetadata(text,g_cotVersion,g_cotLastUpdate,g_cotAvailableIds);
   if(!ok)
   {
      string name;
      long search=FileFindFirst(COT_CSV_DIR+"\\*.csv",name);
      if(search==INVALID_HANDLE)
      {
         search=FileFindFirst(COT_CSV_DIR+"\\*.csv",name,COT_FILE_SCOPE);
         g_cotCsvInCommon=true;
      }
      ArrayFree(g_cotAvailableIds);
      g_cotLastUpdate=0;
      if(search!=INVALID_HANDLE)
      {
         do
         {
            string id=StringSubstr(name,0,StringLen(name)-4);
            if(!COT_SafeName(id)) continue;
            StringToUpper(id);
            int n=ArraySize(g_cotAvailableIds);
            if(n>=COT_MAX_SERIES) break;
            ArrayResize(g_cotAvailableIds,n+1); g_cotAvailableIds[n]=id;
            datetime modified=(datetime)FileGetInteger(COT_CSV_DIR+"\\"+name,FILE_MODIFY_DATE,g_cotCsvInCommon);
            if(modified>g_cotLastUpdate) g_cotLastUpdate=modified;
         } while(FileFindNext(search,name));
         FileFindClose(search);
      }
      ok=ArraySize(g_cotAvailableIds)>0;
      g_cotUseCsvFallback=ok;
      g_cotVersion="csv";
      if(COT_ReadText(COT_CSV_DIR+"\\version.txt",text,g_cotCsvInCommon?COT_FILE_SCOPE:0)) g_cotVersion=COT_Trim(text);
   }
   if(!ok) {g_cotLastError="COT data not found. Start SqCOTService and click Update COT Data."; return false;}
   g_cotAvailableCount=ArraySize(g_cotAvailableIds);
   ArrayResize(g_cotSeries,COT_MAX_SERIES); g_cotSeriesCount=0;
   g_cotInitialized=true;
   return true;
}
bool COT_IsAvailable(string identifier)
{
   if(!g_cotInitialized) return false;
   for(int i=0;i<g_cotAvailableCount;i++)
      if(StringCompare(g_cotAvailableIds[i],identifier,false)==0) return true;
   return false;
}
string COT_GetDatasetVersion() {return g_cotVersion;}
datetime COT_GetLastUpdate() {return g_cotLastUpdate;}
string COT_GetLastError() {return g_cotLastError;}
bool COT_IsStale() {return !g_cotInitialized || g_cotLastUpdate==0 || COT_NOW()-g_cotLastUpdate>7*86400;}
int COT_FindSeries(string identifier)
{
   for(int i=0;i<g_cotSeriesCount;i++)
      if(StringCompare(g_cotSeries[i].identifier,identifier,false)==0) return i;
   return -1;
}
bool COT_StoreSeries(string identifier,const CotBinRecord &records[])
{
   int idx=COT_FindSeries(identifier);
   if(idx<0)
   {
      if(g_cotSeriesCount>=COT_MAX_SERIES) {g_cotLastError="Maximum COT series limit reached."; return false;}
      idx=g_cotSeriesCount++;
   }
   g_cotSeries[idx].identifier=identifier;
   g_cotSeries[idx].count=ArraySize(records);
   ArrayResize(g_cotSeries[idx].records,ArraySize(records));
   ArrayCopy(g_cotSeries[idx].records,records);
   g_cotSeries[idx].loaded=true;
   return true;
}
bool COT_LoadFromCsv(string identifier)
{
   if(!COT_SafeName(identifier)) return false;
   uchar bytes[];
   CotBinRecord records[];
   if(!COT_ReadBytes(COT_CSV_DIR+"\\"+identifier+".csv",bytes,g_cotCsvInCommon?COT_FILE_SCOPE:0,8388608))
   {g_cotLastError="Cannot read COT CSV for "+identifier; return false;}
   if(!COT_ParseCsv(CharArrayToString(bytes,0,ArraySize(bytes),CP_UTF8),records,g_cotLastError)) return false;
   return COT_StoreSeries(identifier,records);
}
bool COT_LoadFromBin(string identifier)
{
   if(!COT_SafeName(identifier)) return false;
   StringToUpper(identifier);
   CotBinRecord records[];
   int lock=COT_Lock("cache");if(lock==INVALID_HANDLE){g_cotLastError="Cache busy.";return false;}
   bool ok=COT_ReadBin(g_cotDataDir+"\\"+identifier+".bin",records,g_cotLastError);
   FileClose(lock);if(!ok)return false;
   return COT_StoreSeries(identifier,records);
}
bool COT_Load(string identifier)
{
   g_cotLastError="";
   if(!g_cotInitialized && !COT_Initialize()) return false;
   int idx=COT_FindSeries(identifier);
   if(idx>=0 && g_cotSeries[idx].loaded) return true;
   if(!COT_IsAvailable(identifier)) {g_cotLastError="COT identifier not found: "+identifier; return false;}
   if(g_cotUseCsvFallback) return COT_LoadFromCsv(identifier);
   if(g_cotDataDir==COT_CACHE_DIR && !FileIsExist(g_cotDataDir+"\\"+identifier+".bin",COT_FILE_SCOPE))
      return COT_LoadFromCsv(identifier);
   return COT_LoadFromBin(identifier);
}
// Optional for single-market UIs. Strategy callers keep the original
// multi-series behavior unless they explicitly use this function.
bool COT_RetainOnlySeries(const string identifier)
{
   int idx=COT_FindSeries(identifier);
   if(idx<0 || !g_cotSeries[idx].loaded) return false;
   CotBinRecord kept[];
   if(ArrayCopy(kept,g_cotSeries[idx].records)!=g_cotSeries[idx].count) return false;
   for(int i=0;i<g_cotSeriesCount;i++)
   {
      ArrayFree(g_cotSeries[i].records);
      g_cotSeries[i].loaded=false; g_cotSeries[i].count=0; g_cotSeries[i].identifier="";
   }
   g_cotSeriesCount=0;
   return COT_StoreSeries(identifier,kept);
}
int COT_BinarySearch(const CotBinRecord &records[],int count,datetime barTime)
{
   int lo=0,hi=count-1,result=-1;
   while(lo<=hi)
   {
      int mid=(lo+hi)/2;
      if(records[mid].date<=(long)barTime) {result=mid; lo=mid+1;}
      else hi=mid-1;
   }
   return result;
}
double COT_GetValue(string identifier,int field,datetime barTime)
{
   if(!COT_Load(identifier)) return EMPTY_VALUE;
   int idx=COT_FindSeries(identifier);
   int row=COT_BinarySearch(g_cotSeries[idx].records,g_cotSeries[idx].count,barTime);
   if(row<0) return EMPTY_VALUE;
   switch(field)
   {
      case 0: return g_cotSeries[idx].records[row].cpihedg;
      case 1: return g_cotSeries[idx].records[row].ctihedg;
      case 2: return g_cotSeries[idx].records[row].cpispec;
      case 3: return g_cotSeries[idx].records[row].ctispec;
      case 4: return g_cotSeries[idx].records[row].cpismall;
   }
   return EMPTY_VALUE;
}
// Retain every loaded series on disk/read/validation failure.
bool COT_ReloadIfVersionChanged()
{
   if(!g_cotInitialized) return COT_Initialize();
   string version,directory,ids[],text;
   datetime updated=0;
   bool snapshot=COT_ReadSnapshot(version,updated,ids,directory);
   if(!snapshot)
   {
      if(FileIsExist(COT_METADATA_FILE,COT_FILE_SCOPE) || FileIsExist(COT_METADATA_FILE+".previous",COT_FILE_SCOPE)) return false;
      directory=COT_CACHE_DIR;
      if(!COT_ReadText(COT_MANIFEST_FILE,text) || !COT_ParseMetadata(text,version,updated,ids)) return false;
   }
   if(version==g_cotVersion && directory==g_cotDataDir) return false;
   int lock=COT_Lock("cache");if(lock==INVALID_HANDLE)return false;
   CotSeries next[];
   ArrayResize(next,g_cotSeriesCount);
   for(int i=0;i<g_cotSeriesCount;i++)
   {
      string identifier=g_cotSeries[i].identifier;
      StringToUpper(identifier);
      bool available=false;
      for(int j=0;j<ArraySize(ids);j++) if(ids[j]==identifier) {available=true; break;}
      if(!available || !COT_ReadBin(directory+"\\"+identifier+".bin",next[i].records,g_cotLastError)) {FileClose(lock);return false;}
   }
   for(int i=0;i<g_cotSeriesCount;i++) COT_StoreSeries(g_cotSeries[i].identifier,next[i].records);
   ArrayCopy(g_cotAvailableIds,ids); ArrayResize(g_cotAvailableIds,ArraySize(ids));
   g_cotAvailableCount=ArraySize(ids);
   g_cotDataDir=directory; g_cotVersion=version; g_cotLastUpdate=updated;
   g_cotUseCsvFallback=false;
   FileClose(lock);
   return true;
}
void COT_Deinitialize()
{
   ArrayFree(g_cotSeries); ArrayFree(g_cotAvailableIds);
   g_cotSeriesCount=0; g_cotAvailableCount=0; g_cotInitialized=false;
   g_cotVersion=""; g_cotLastUpdate=0;
}
#endif
