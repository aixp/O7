.PHONY: all build clean

BB ?= bbcb2-cli

all: build

build: O7/Sym/ARMv6MP.osf O7/Sym/ARMv7MP.osf O7/Sym/ARMv6MLinker.osf O7/Sym/ARMv7MLinker.osf O7/Sym/ARMv7MTool.osf O7/Sym/References.osf O7/Sym/Position.osf

O7/Sym/Files.osf: O7/Mod/Files2.odc
	echo "DevCompiler.CompileThis O7Files2" | ${BB}

O7/Sym/Texts.osf: O7/Mod/Texts.odc
	echo "DevCompiler.CompileThis O7Texts" | ${BB}

O7/Sym/Texts.osf: O7/Sym/Files.osf

O7/Sym/Oberon.osf: O7/Mod/Oberon.odc
	echo "DevCompiler.CompileThis O7Oberon" | ${BB}

O7/Sym/Oberon.osf: O7/Sym/Texts.osf

O7/Sym/S.osf: O7/Mod/S.odc
	echo "DevCompiler.CompileThis O7S" | ${BB}

O7/Sym/S.osf: O7/Sym/Texts.osf O7/Sym/Oberon.osf

O7/Sym/B.osf: O7/Mod/B.odc
	echo "DevCompiler.CompileThis O7B" | ${BB}

O7/Sym/B.osf: O7/Sym/Files.osf O7/Sym/S.osf

O7/Sym/ARMv6M.osf: O7/Mod/ARMv6M.odc
	echo "DevCompiler.CompileThis O7ARMv6M" | ${BB}

O7/Sym/ARMv7M.osf: O7/Mod/ARMv7M.odc
	echo "DevCompiler.CompileThis O7ARMv7M" | ${BB}

O7/Sym/ARMv7M.osf: O7/Sym/ARMv6M.osf

O7/Sym/ARMv6MG.osf: O7/Mod/ARMv6MG.odc
	echo "DevCompiler.CompileThis O7ARMv6MG" | ${BB}

O7/Sym/ARMv6MG.osf: O7/Sym/Files.osf O7/Sym/S.osf O7/Sym/B.osf O7/Sym/ARMv6M.osf

O7/Sym/ARMv7MG.osf: O7/Mod/ARMv7MG.odc
	echo "DevCompiler.CompileThis O7ARMv7MG" | ${BB}

O7/Sym/ARMv7MG.osf: O7/Sym/Files.osf O7/Sym/S.osf O7/Sym/B.osf O7/Sym/ARMv6M.osf O7/Sym/ARMv7M.osf

O7/Sym/ARMv6MP.osf: O7/Mod/ARMv6MP.odc
	echo "DevCompiler.CompileThis O7ARMv6MP" | ${BB}

O7/Sym/ARMv6MP.osf: O7/Sym/S.osf O7/Sym/B.osf O7/Sym/ARMv6MG.osf O7/Sym/Texts.osf O7/Sym/Oberon.osf

O7/Sym/ARMv7MP.osf: O7/Mod/ARMv7MP.odc
	echo "DevCompiler.CompileThis O7ARMv7MP" | ${BB}

O7/Sym/ARMv7MP.osf: O7/Sym/S.osf O7/Sym/B.osf O7/Sym/ARMv7MG.osf O7/Sym/Texts.osf O7/Sym/Oberon.osf

O7/Sym/ARMv6MLinker.osf: O7/Mod/ARMv6MLinker.odc
	echo "DevCompiler.CompileThis O7ARMv6MLinker" | ${BB}

O7/Sym/ARMv6MLinker.osf: O7/Sym/Files.osf O7/Sym/Texts.osf O7/Sym/Oberon.osf O7/Sym/ARMv6M.osf

O7/Sym/ARMv7MLinker.osf: O7/Mod/ARMv7MLinker.odc
	echo "DevCompiler.CompileThis O7ARMv7MLinker" | ${BB}

O7/Sym/ARMv7MLinker.osf: O7/Sym/Files.osf O7/Sym/Texts.osf O7/Sym/Oberon.osf O7/Sym/ARMv6M.osf O7/Sym/ARMv7M.osf

O7/Sym/ARMv7MTool.osf: O7/Mod/ARMv7MTool.odc
	echo "DevCompiler.CompileThis O7ARMv7MTool" | ${BB}

O7/Sym/ARMv7MTool.osf: O7/Sym/Files.osf O7/Sym/Texts.osf O7/Sym/Oberon.osf O7/Sym/B.osf O7/Sym/ARMv7M.osf

O7/Sym/References.osf: O7/Mod/References2.odc
	echo "DevCompiler.CompileThis O7References2" | ${BB}

O7/Sym/Position.osf: O7/Mod/Position.odc
	echo "DevCompiler.CompileThis O7Position" | ${BB}

clean:
	rm -rf O7/Code O7/Sym
