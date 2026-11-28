// Core 0 用の独立した Dhrystone 2.1 インスタンス（third_party/dhrystone 無改変で 2 コア同時実行するためのリネーム定義）
#include <string.h>

#define main                  dhry0_main
#define malloc                dhry0_malloc
#define scanf                 dhry0_scanf
#define printf                dhry_printf
#define time                  dhry_time

#define Ptr_Glob              dhry0_Ptr_Glob
#define Next_Ptr_Glob         dhry0_Next_Ptr_Glob
#define Int_Glob              dhry0_Int_Glob
#define Bool_Glob             dhry0_Bool_Glob
#define Ch_1_Glob             dhry0_Ch_1_Glob
#define Ch_2_Glob             dhry0_Ch_2_Glob
#define Arr_1_Glob            dhry0_Arr_1_Glob
#define Arr_2_Glob            dhry0_Arr_2_Glob
#define Reg                   dhry0_Reg
#define Begin_Time            dhry0_Begin_Time
#define End_Time              dhry0_End_Time
#define User_Time             dhry0_User_Time
#define Microseconds          dhry0_Microseconds
#define Dhrystones_Per_Second dhry0_Dhrystones_Per_Second

#define Proc_1                dhry0_Proc_1
#define Proc_2                dhry0_Proc_2
#define Proc_3                dhry0_Proc_3
#define Proc_4                dhry0_Proc_4
#define Proc_5                dhry0_Proc_5
#define Proc_6                dhry0_Proc_6
#define Proc_7                dhry0_Proc_7
#define Proc_8                dhry0_Proc_8
#define Func_1                dhry0_Func_1
#define Func_2                dhry0_Func_2
#define Func_3                dhry0_Func_3

char *dhry0_malloc();
int   dhry0_scanf(const char *fmt, ...);
int   dhry_printf(const char *fmt, ...);
long  dhry_time();
