aLL: O7ARMv7MPCompile O7ARMv7MToolDecObj O7ARMv7MToolDecSym O7ARMv7MToolDecBin O7ARMv7MToolDecHex O7ARMv7MLinkerLink

O7ARMv7MPCompile: O7ARMv7MP.o O7ARMv7MPCompile.Mod
	voc -OC O7ARMv7MPCompile.Mod -m

O7ARMv7MToolDecObj: O7ARMv7MTool.o O7ARMv7MToolDecObj.Mod
	voc -OC O7ARMv7MToolDecObj.Mod -m

O7ARMv7MToolDecSym: O7ARMv7MTool.o O7ARMv7MToolDecSym.Mod
	voc -OC O7ARMv7MToolDecSym.Mod -m

O7ARMv7MToolDecBin: O7ARMv7MTool.o O7ARMv7MToolDecBin.Mod
	voc -OC O7ARMv7MToolDecBin.Mod -m

O7ARMv7MToolDecHex: O7ARMv7MTool.o O7ARMv7MToolDecHex.Mod
	voc -OC O7ARMv7MToolDecHex.Mod -m

O7ARMv7MLinkerLink: O7ARMv7MLinker.o O7ARMv7MLinkerLink.Mod
	voc -OC O7ARMv7MLinkerLink.Mod -m

O7S.o: O7S.Mod
	voc -OC -c O7S.Mod

O7B.o: O7S.o O7B.Mod
	voc -OC -c O7B.Mod

O7ARMv6M.o: O7ARMv6M.Mod
	voc -OC -c O7ARMv6M.Mod

O7ARMv7M.o: O7ARMv6M.o O7ARMv7M.Mod
	voc -OC -c O7ARMv7M.Mod

O7ARMv7MG.o: O7S.o O7B.o O7ARMv6M.o O7ARMv7M.o O7ARMv7MG.Mod
	voc -OC -c O7ARMv7MG.Mod

O7ARMv7MP.o: O7S.o O7B.o O7ARMv7MG.o O7ARMv7MP.Mod
	voc -OC -c O7ARMv7MP.Mod

O7ARMv7MTool.o: O7B.o O7ARMv7MG.o O7ARMv7M.o O7ARMv7MTool.Mod
	voc -OC -c O7ARMv7MTool.Mod

O7ARMv7MLinker.o: O7ARMv6M.o O7ARMv7M.o O7ARMv7MLinker.Mod
	voc -OC -c O7ARMv7MLinker.Mod

clean:
	rm -f *.c *.o *.h *.sym O7ARMv7MPCompile O7ARMv7MToolDecObj O7ARMv7MToolDecSym O7ARMv7MToolDecBin O7ARMv7MToolDecHex O7ARMv7MLinkerLink
