#ifndef __SQ_COT_RETENTION_MQH__
#define __SQ_COT_RETENTION_MQH__
#include <SqCOTStorage.mqh>
// Caller holds cache.lock. No recursion; only known generated files are removed.
void COT_RemoveGeneration(const string id)
{
   if(!COT_SafeName(id))return;
   string dir=COT_CACHE_DIR+"\\generations\\"+id,name;
   long h=FileFindFirst(dir+"\\*",name,COT_FILE_SCOPE);
   if(h!=INVALID_HANDLE)
   {
      do
      {
         int n=StringLen(name);bool known=name=="runtime.dat"||name=="complete.dat"||name=="calendar.csv"||name=="history.dat";
         if(n>4)
         {
            string ext=StringSubstr(name,n-4);
            known=known||((ext==".bin"||ext==".pit"||ext==".tmp")&&COT_SafeName(StringSubstr(name,0,n-4)));
         }
         if(known)FileDelete(dir+"\\"+name,COT_FILE_SCOPE);
      }while(FileFindNext(h,name));FileFindClose(h);
   }
   FolderDelete(dir,COT_FILE_SCOPE);
}
void COT_DiscardStage(const string id)
{
   int lock=COT_Lock("cache");if(lock==INVALID_HANDLE)return;
   string text,version,ids[];datetime updated;
   bool current=COT_ReadText(COT_METADATA_FILE,text)&&COT_ParseMetadata(text,version,updated,ids)&&version==id;
   bool previous=COT_ReadText(COT_METADATA_FILE+".previous",text)&&COT_ParseMetadata(text,version,updated,ids)&&version==id;
   if(!current&&!previous)COT_RemoveGeneration(id);FileClose(lock);
}
void COT_PruneGenerations(const int keep=4)
{
   if(keep<2)return;
   int lock=COT_Lock("cache");if(lock==INVALID_HANDLE)return;
   string text,current,previous,ids[];datetime updated;
   if(!COT_ReadText(COT_METADATA_FILE,text)||!COT_ParseMetadata(text,current,updated,ids)){FileClose(lock);return;}
   if(COT_ReadText(COT_METADATA_FILE+".previous",text))COT_ParseMetadata(text,previous,updated,ids);
   string names[],name;long stamps[];
   long h=FileFindFirst(COT_CACHE_DIR+"\\generations\\*",name,COT_FILE_SCOPE);
   if(h!=INVALID_HANDLE)
   {
      do
      {
         int length=StringLen(name);
         if(length>0 && StringGetCharacter(name,length-1)=='\\')name=StringSubstr(name,0,length-1);
         if(!COT_SafeName(name))continue;
         string version;datetime stamp;
         if(!COT_ReadText(COT_CACHE_DIR+"\\generations\\"+name+"\\complete.dat",text)||
            !COT_ParseMetadata(text,version,stamp,ids)||version!=name)continue;
         int n=ArraySize(names);ArrayResize(names,n+1);ArrayResize(stamps,n+1);names[n]=name;stamps[n]=(long)stamp;
      }while(FileFindNext(h,name));FileFindClose(h);
   }
   for(int i=0;i<ArraySize(names);i++)for(int j=i+1;j<ArraySize(names);j++)if(stamps[j]>stamps[i])
   {long t=stamps[i];stamps[i]=stamps[j];stamps[j]=t;string s=names[i];names[i]=names[j];names[j]=s;}
   for(int i=keep;i<ArraySize(names);i++)if(names[i]!=current&&names[i]!=previous)COT_RemoveGeneration(names[i]);
   FileClose(lock);
}
#endif
