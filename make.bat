gcc -std=gnu11 -DUNICODE -D_UNICODE -w -o v2.exe v.c
v2.exe -o v.exe compiler
del v2.exe
del v.c
