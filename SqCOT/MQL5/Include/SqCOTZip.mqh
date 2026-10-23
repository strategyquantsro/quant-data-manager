// ZIP32 central-directory parser. Pure MQL5; native raw-DEFLATE decoding.
// Never extracts archive paths to disk. Verifies CRC32 independently.
#ifndef __SQ_COT_ZIP_MQH__
#define __SQ_COT_ZIP_MQH__
#include <SqCOTStorage.mqh>
#define COT_ZIP_MAX_FILE_BYTES 67108864 // cot.json currently expands to about 40 MiB
struct CotZipEntry
{
   string name;
   uint crc,packed,unpacked,offset;
   int method;
};
uint COT_U16(const uchar &a[],int p) {return (uint)a[p]|((uint)a[p+1]<<8);}
uint COT_U32(const uchar &a[],int p) {return COT_U16(a,p)|(COT_U16(a,p+2)<<16);}
bool COT_ZipPathSafe(string path)
{
   StringReplace(path,"\\","/");
   if(path=="" || StringFind(path,"/")==0 || StringFind(path,":")>=0) return false;
   string parts[];
   int n=StringSplit(path,'/',parts);
   for(int i=0;i<n;i++)
      if(parts[i]==".." || parts[i]=="." || (parts[i]=="" && i<n-1)) return false;
   for(int i=0;i<StringLen(path);i++) if(StringGetCharacter(path,i)<32) return false;
   return true;
}
bool COT_ZipDirectory(const uchar &zip[],CotZipEntry &entries[],string &error)
{
   int size=ArraySize(zip),end=-1;
   if(size<22) {error="Empty or truncated ZIP."; return false;}
   int first=MathMax(0,size-65557);
   for(int p=size-22;p>=first;p--)
      if(COT_U32(zip,p)==0x06054b50 && p+22+(int)COT_U16(zip,p+20)==size) {end=p; break;}
   if(end<0) {error="ZIP end record missing."; return false;}
   uint count=COT_U16(zip,end+10),central=COT_U32(zip,end+16),length=COT_U32(zip,end+12);
   if(COT_U16(zip,end+4)!=0 || COT_U16(zip,end+6)!=0 || count!=COT_U16(zip,end+8) ||
      count==0 || count>2048 || (ulong)central+length!=(ulong)end)
   {error="Unsupported ZIP64, split archive or invalid directory."; return false;}
   ArrayResize(entries,(int)count);
   int p=(int)central;
   ulong total=0;
   for(int i=0;i<(int)count;i++)
   {
      if(p<0 || p+46>end || COT_U32(zip,p)!=0x02014b50) {error="Invalid ZIP directory entry."; return false;}
      uint flags=COT_U16(zip,p+8),nameLen=COT_U16(zip,p+28),extra=COT_U16(zip,p+30),comment=COT_U16(zip,p+32);
      ulong next=(ulong)p+46+nameLen+extra+comment;
      if(next>(ulong)end || nameLen==0 || (flags & 0x2041)!=0 || COT_U16(zip,p+34)!=0)
      {error="Encrypted or malformed ZIP entry."; return false;}
      entries[i].method=(int)COT_U16(zip,p+10);
      entries[i].crc=COT_U32(zip,p+16); entries[i].packed=COT_U32(zip,p+20);
      entries[i].unpacked=COT_U32(zip,p+24);
      uint local=COT_U32(zip,p+42);
      entries[i].name=CharArrayToString(zip,p+46,(int)nameLen,CP_UTF8);
      string item="ZIP entry #"+IntegerToString(i+1);
      if(!COT_ZipPathSafe(entries[i].name))
      {error=item+": unsafe path."; return false;}
      item+=" ("+StringSubstr(entries[i].name,0,100)+")";
      if(entries[i].unpacked>COT_ZIP_MAX_FILE_BYTES)
      {error=item+": uncompressed size "+IntegerToString(entries[i].unpacked)+" exceeds 64 MiB."; return false;}
      if(entries[i].method!=0 && entries[i].method!=8)
      {error=item+": unsupported compression method "+IntegerToString(entries[i].method)+"."; return false;}
      if((ulong)local+30>central)
      {error=item+": local header is outside the data section."; return false;}
      int lp=(int)local;
      if(COT_U32(zip,lp)!=0x04034b50 || COT_U16(zip,lp+8)!=(uint)entries[i].method || COT_U16(zip,lp+6)!=flags)
      {error="ZIP local header mismatch."; return false;}
      uint localName=COT_U16(zip,lp+26);
      ulong offset=(ulong)local+30+localName+COT_U16(zip,lp+28);
      if(offset+entries[i].packed>central || localName!=nameLen ||
         CharArrayToString(zip,lp+30,(int)localName,CP_UTF8)!=entries[i].name)
      {error="ZIP payload is truncated or filename mismatches."; return false;}
      entries[i].offset=(uint)offset;
      total+=entries[i].unpacked;
      if(total>134217728) {error="Uncompressed archive exceeds 128 MiB."; return false;}
      p=(int)next;
   }
   if(p!=end) {error="Unexpected ZIP directory data."; return false;}
   return true;
}
uint COT_Crc32(const uchar &bytes[])
{
   static uint table[256];
   static bool ready=false;
   if(!ready)
   {
      for(uint i=0;i<256;i++)
      {
         uint c=i;
         for(int k=0;k<8;k++) c=(c&1)!=0 ? (0xEDB88320^(c>>1)) : (c>>1);
         table[i]=c;
      }
      ready=true;
   }
   uint crc=0xFFFFFFFF;
   for(int i=0;i<ArraySize(bytes);i++) crc=table[(crc^bytes[i])&255]^(crc>>8);
   return crc^0xFFFFFFFF;
}
bool COT_ZipExtract(const uchar &zip[],const CotZipEntry &entry,uchar &data[],string &error)
{
   ArrayFree(data);
   if(entry.unpacked==0)
   {
      if(entry.crc==0) return true;
      error="ZIP empty-file CRC mismatch."; return false;
   }
   uchar packed[];
   ArrayResize(packed,(int)entry.packed);
   if(ArrayCopy(packed,zip,0,(int)entry.offset,(int)entry.packed)!=(int)entry.packed)
   {error="Cannot read ZIP payload."; return false;}
   if(entry.method==0) ArrayCopy(data,packed);
   else
   {
      // MQL5 option 1 means raw DEFLATE (without zlib Adler32 wrapper).
      // CRC32 is checked below against the ZIP central directory.
      uchar options[]={1,0,0,0};
      if(CryptDecode(CRYPT_ARCH_ZIP,packed,options,data)<=0)
      {error="Cannot decompress ZIP entry."; return false;}
   }
   if(ArraySize(data)!=(int)entry.unpacked || COT_Crc32(data)!=entry.crc)
   {error="ZIP size or CRC32 mismatch."; ArrayFree(data); return false;}
   return true;
}
#endif
