.PHONY: all clean

VOC ?= voc

all: O7ARMv6MPCompile O7ARMv7MPCompile O7ARMv7MToolDecObj O7ARMv7MToolDecSym O7ARMv7MToolDecBin O7ARMv7MToolDecHex O7ARMv6MLinkerLink O7ARMv7MLinkerLink

O7ARMv6MPCompile: O7ARMv6MP.o O7ARMv6MPCompile.Mod SYSTEM.h
	${VOC} -OC O7ARMv6MPCompile.Mod -m

O7ARMv7MPCompile: O7ARMv7MP.o O7ARMv7MPCompile.Mod SYSTEM.h
	${VOC} -OC O7ARMv7MPCompile.Mod -m

O7ARMv7MToolDecObj: O7ARMv7MTool.o O7ARMv7MToolDecObj.Mod SYSTEM.h
	${VOC} -OC O7ARMv7MToolDecObj.Mod -m

O7ARMv7MToolDecSym: O7ARMv7MTool.o O7ARMv7MToolDecSym.Mod SYSTEM.h
	${VOC} -OC O7ARMv7MToolDecSym.Mod -m

O7ARMv7MToolDecBin: O7ARMv7MTool.o O7ARMv7MToolDecBin.Mod SYSTEM.h
	${VOC} -OC O7ARMv7MToolDecBin.Mod -m

O7ARMv7MToolDecHex: O7ARMv7MTool.o O7ARMv7MToolDecHex.Mod SYSTEM.h
	${VOC} -OC O7ARMv7MToolDecHex.Mod -m

O7ARMv6MLinkerLink: O7ARMv6MLinker.o O7ARMv6MLinkerLink.Mod SYSTEM.h
	${VOC} -OC O7ARMv6MLinkerLink.Mod -m

O7ARMv7MLinkerLink: O7ARMv7MLinker.o O7ARMv7MLinkerLink.Mod SYSTEM.h
	${VOC} -OC O7ARMv7MLinkerLink.Mod -m

O7S.o: O7S.Mod SYSTEM.h
	${VOC} -OC -c O7S.Mod

O7B.o: O7S.o O7B.Mod SYSTEM.h
	${VOC} -OC -c O7B.Mod

O7ARMv6M.o: O7ARMv6M.Mod SYSTEM.h
	${VOC} -OC -c O7ARMv6M.Mod

O7ARMv7M.o: O7ARMv6M.o O7ARMv7M.Mod SYSTEM.h
	${VOC} -OC -c O7ARMv7M.Mod

O7ARMv6MG.o: O7S.o O7B.o O7ARMv6M.o O7ARMv6MG.Mod SYSTEM.h
	${VOC} -OC -c O7ARMv6MG.Mod

O7ARMv7MG.o: O7S.o O7B.o O7ARMv6M.o O7ARMv7M.o O7ARMv7MG.Mod SYSTEM.h
	${VOC} -OC -c O7ARMv7MG.Mod

O7ARMv6MP.o: O7S.o O7B.o O7ARMv6MG.o O7ARMv6MP.Mod SYSTEM.h
	${VOC} -OC -c O7ARMv6MP.Mod

O7ARMv7MP.o: O7S.o O7B.o O7ARMv7MG.o O7ARMv7MP.Mod SYSTEM.h
	${VOC} -OC -c O7ARMv7MP.Mod

O7ARMv7MTool.o: O7B.o O7ARMv7MG.o O7ARMv7M.o O7ARMv7MTool.Mod SYSTEM.h
	${VOC} -OC -c O7ARMv7MTool.Mod

O7ARMv6MLinker.o: O7ARMv6M.o O7ARMv6MLinker.Mod SYSTEM.h
	${VOC} -OC -c O7ARMv6MLinker.Mod

O7ARMv7MLinker.o: O7ARMv6M.o O7ARMv7M.o O7ARMv7MLinker.Mod SYSTEM.h
	${VOC} -OC -c O7ARMv7MLinker.Mod

clean:
	rm -f .tmp* *.o *.sym \
		O7S.c O7S.h \
		O7B.c O7B.h \
		O7ARMv6M.c O7ARMv6M.h \
		O7ARMv7M.c O7ARMv7M.h \
		O7ARMv6MG.c O7ARMv6MG.h \
		O7ARMv7MG.c O7ARMv7MG.h \
		O7ARMv6MP.c O7ARMv6MP.h \
		O7ARMv7MP.c O7ARMv7MP.h \
		O7ARMv6MLinker.c O7ARMv6MLinker.h \
		O7ARMv7MLinker.c O7ARMv7MLinker.h \
		O7ARMv7MTool.c O7ARMv7MTool.h \
		O7ARMv6MPCompile.c O7ARMv6MLinkerLink.c \
		O7ARMv7MPCompile.c O7ARMv7MLinkerLink.c \
		O7ARMv7MToolDecObj.c O7ARMv7MToolDecSym.c O7ARMv7MToolDecBin.c O7ARMv7MToolDecHex.c \
		O7ARMv6MPCompile O7ARMv7MPCompile \
		O7ARMv6MLinkerLink O7ARMv7MLinkerLink \
		O7ARMv7MToolDecObj O7ARMv7MToolDecSym O7ARMv7MToolDecBin O7ARMv7MToolDecHex
