CC ?= cc

_SYS := $(shell uname 2>/dev/null || echo Unknown)
_SYS := $(patsubst MSYS%,MSYS,$(_SYS))
_SYS := $(patsubst MINGW%,MinGW,$(_SYS))

ifneq ($(filter $(_SYS),MSYS MinGW),)
WIN32:=1
endif

all:
	#rm -rf vc/
	#git clone --depth 1 --quiet https://github.com/vlang/vc
ifdef WIN32
	$(CC) -std=gnu11 -w -o v0.exe vc/v_win.c
	./v0.exe -o v.exe compiler
	rm -f v0.exe
else
	$(CC) -std=gnu11 -w -o v vc/v.c -lm
	@(VC_V=`./v version | cut -f 3 -d " "`; \
	V_V=`git rev-parse --short HEAD`; \
	if [ $$VC_V != $$V_V ]; then \
		echo "Self rebuild ($$VC_V => $$V_V)"; \
		./v -o v compiler; \
	fi)
endif
	#rm -rf vc/
	@echo "V has been successfully built"

