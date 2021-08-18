MODULE O7ARMv7MLinker;

	(* Link and load on RISC; NW 20.10.2013 / 8.1.2019 *)

	(* ARMv7-M: Alexander Shiryaev, 2014.10, 2015.02, 2016.06, 2017.01, 2019.11, 2021.08 *)

	(*
		TODO:
			procedure addresses (progbase-relative...)
			add support of version-0 files
			resource files (simple copy to flashOrg before all)
		NOTES:
			we do not fill global data by zeros
				do not call GC.Collect before all global pointers initialization!
			pointer references for GC only
			MTab stored in RAM for fast access
			modules ptrs table stored in RAM for fast GC work
	*)

	IMPORT SYSTEM, Files (*:= O7Files*), Texts (*:= O7Texts*), Oberon (*:= O7Oberon*), ARMv6M := O7ARMv6M, ARMv7M := O7ARMv7M;

	TYPE
		LONGINT = INTEGER;
		BYTE = CHAR;

	CONST versionkey = 1X; MT = 6; SB = 3;
		trace = FALSE;

		(* fixup tags *)
			tagFixup = 00FFFFFFH; (* Add/Ldr/LdrB/Str/StrB *)
			tagVLDR = 00FFFFFCH;
			tagBL = 00FFFFE0H;
			tagLdrSB = 00FFFFD0H;

	TYPE Module = POINTER TO ModDesc;
		ModuleName = ARRAY 32 OF CHAR;

		ModDesc = RECORD
			name: ModuleName;
			next: Module;
			key, num: INTEGER;
			data: INTEGER; (* address, relative to mem, bytes *)
			strs: INTEGER; (* address, relative to data, bytes *)
			code: INTEGER; (* address, relative to flash start, halfwords *)
			entries: POINTER TO ARRAY OF INTEGER;
				entriesLen: INTEGER;
			imports: ARRAY 255 OF Module;
			body: INTEGER;
			typeds: POINTER TO ARRAY OF INTEGER;
				typedsLen: INTEGER;
			strings: POINTER TO ARRAY OF INTEGER;
				stringsLen: INTEGER;
			fixorgT: INTEGER;
			nPtrs: INTEGER; (* number of pointer references *)
			ptr: INTEGER (* address, relative to flash start, halfwords *)
		END;

		TargetName = ARRAY 32 OF CHAR;
		Target = POINTER TO RECORD
			next: Target;
			name: TargetName;
			isNXP: BOOLEAN;
			flashStart, flashSize: INTEGER;
			maxExtInts, flashOrg: INTEGER;
			SRAMStart, SRAMSize: INTEGER
		END;

	VAR
		root: Module;
		modules: ARRAY 100H OF Module;
		flash: ARRAY 200000H DIV 2 OF INTEGER; flashW: INTEGER;
		memW: INTEGER; (* bytes *)
		nPtrs: INTEGER;
		res: INTEGER;
		importing, imported: ModuleName;

		W: Texts.Writer;
		target: Target;
		targets: Target;

	PROCEDURE BITS (x: INTEGER): SET;
	BEGIN
		RETURN SYSTEM.VAL(SET, x)
	END BITS;

	PROCEDURE ORDSET (x: SET): INTEGER;
	BEGIN
		RETURN SYSTEM.VAL(INTEGER, x)
	END ORDSET;

	PROCEDURE StrLen (VAR x: ARRAY OF CHAR): INTEGER;
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE (i < LEN(x)) & (x[i] # 0X) DO INC(i) END;
		RETURN i
	END StrLen;

	PROCEDURE CmpStr (VAR a, b: ARRAY OF CHAR): BOOLEAN;
		VAR i: INTEGER;
			res: BOOLEAN;
	BEGIN
		i := 0;
		WHILE (i < LEN(a)) & (i < LEN(b)) & (a[i] # 0X) & (b[i] # 0X) & (a[i] = b[i]) DO INC(i) END;
		res := (i = LEN(a)) OR (i = LEN(b)) OR ((a[i] = 0X) & (b[i] = 0X));
		RETURN res
	END CmpStr;

	PROCEDURE ReadInt (VAR R: Files.Rider; VAR x: INTEGER);
		VAR y: SYSTEM.INT64;
	BEGIN
		Files.ReadLInt(R, y);
		IF R.eof THEN x := -1
		ELSE x := SHORT(y)
		END
	END ReadInt;

	PROCEDURE ThisFile ((*IN*) VAR name: ARRAY OF CHAR): Files.File;
		VAR i: INTEGER;
			filename: ModuleName;
	BEGIN i := 0;
		WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
		filename[i] := "."; filename[i+1] := "a"; filename[i+2] := "7";
		filename[i+3] := "m"; filename[i+4] := 0X;
		RETURN Files.Old(filename)
	END ThisFile;

	PROCEDURE NewHexFile ((*IN*) VAR name: ARRAY OF CHAR): Files.File;
		VAR i: INTEGER;
			filename: ModuleName;
	BEGIN i := 0;
		WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
		filename[i] := "."; filename[i+1] := "h"; filename[i+2] := "e";
		filename[i+3] := "x"; filename[i+4] := 0X;
		RETURN Files.New(filename)
	END NewHexFile;

	PROCEDURE NewBinFile ((*IN*) VAR name: ARRAY OF CHAR): Files.File;
		VAR i: INTEGER;
			filename: ModuleName;
	BEGIN i := 0;
		WHILE name[i] # 0X DO filename[i] := name[i]; INC(i) END ;
		filename[i] := "."; filename[i+1] := "b"; filename[i+2] := "i";
		filename[i+3] := "n"; filename[i+4] := 0X;
		RETURN Files.New(filename)
	END NewBinFile;

	PROCEDURE error (n: INTEGER; (*IN*) VAR name: ARRAY OF CHAR);
	BEGIN res := n; COPY(name, importing)
	END error;

	PROCEDURE Check ((*IN*) VAR s: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN ch := s[0]; res := 1; i := 1;
		IF (ch >= "A") & (ch <= "Z") OR (ch >= "a") & (ch <= "z") THEN
			REPEAT ch := s[i]; INC(i)
			UNTIL ~((ch >= "0") & (ch <= "9") OR (ch >= "A") & (ch <= "Z")
				OR (ch >= "a") & (ch <= "z") OR (ch = ".")) OR (i = 32);
			IF (i < 32) & (ch = 0X) THEN res := 0 END
		END
	END Check;

	(* emit 2 instructions *)
	PROCEDURE EmitADDSIm0 (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; a, b, im: INTEGER);
		CONST S = 1;
		VAR i, imm3, imm8: INTEGER; isMI: BOOLEAN;
	BEGIN
		ARMv7M.EncodeMI12(im, i, imm3, imm8, isMI);
		IF isMI THEN
			ASSERT(b # 15, 100);
			ASSERT((b = 13) OR (a # 13), 101);
			(* A7.7.3: ADD (immediate); encoding T3 ARMv7-M *)
			(* A7.7.5: ADD (SP plus immediate); encoding T3 ARMv7-M *)
				ARMv7M.EmitDPMI(code, pc, i, 16 + S, b, imm3, a, imm8)
		ELSIF im <= 255 + 7 THEN
			ARMv6M.EmitADDSIm(code, pc, a, b, 7);
			ARMv6M.EmitADDSIm(code, pc, a, a, im - 7)
		ELSE HALT(1)
			(* fixup failed: offset is too big
				(implementation limit) *)
		END
	END EmitADDSIm0;

	(* search module in list; if not found, load module *)
	PROCEDURE Load ((*IN*) VAR name: ARRAY OF CHAR; VAR newmod: Module);
		VAR mod, impmod: Module;
			i, n, key, impkey, mno, nofimps, size: INTEGER;
			u, v, w: INTEGER; (*addresses*)
			ch: CHAR;
			fixorgP, fixorgD: INTEGER;
			disp, adr, inst, pno, vno, dest, offset: INTEGER;
			name1, impname: ModuleName;
			F: Files.File; R: Files.Rider;
			import: ARRAY 255 OF Module;
			a, b: INTEGER;
			op: INTEGER; (* 0: LW, 1: LB, 2: ADDS, 3: SW, 4: SB, 5: VLDR *)
			nxt: INTEGER;
			ok: BOOLEAN;
	BEGIN
		mod := root; error(0, name); nofimps := 0;
		WHILE (mod # NIL) & ~CmpStr(name, mod.name) DO mod := mod.next END;
		IF mod = NIL THEN (*load*)
			Check(name);
			IF res = 0 THEN F := ThisFile(name) ELSE F := NIL END;
				IF F # NIL THEN
					Files.Set(R, F, 0); Files.ReadString(R, name1);
					ReadInt(R, key); Files.Read(R, ch);
					ReadInt(R, size); importing := name1;
					IF ch = versionkey THEN
						Files.ReadString(R, impname); (*imports*)
						WHILE (impname[0] # 0X) & (res = 0) DO
							ReadInt(R, impkey);
							Load(impname, impmod);
							import[nofimps] := impmod; importing := name1;
							IF res = 0 THEN
							IF impmod.key = impkey THEN INC(nofimps)
							ELSE error(3, name1); imported := impname
							END
						END;
						Files.ReadString(R, impname)
					END
				ELSE error(2, name1)
			END
		ELSE error(1, name(*$*))
		END;

		IF res = 0 THEN NEW(mod); mod.next := root;
			IF root = NIL THEN mod.num := 0
			ELSE mod.num := root.num + 1
			END;
			root := mod
		END;

		IF res = 0 THEN (*read file*)
			COPY(name, mod.name); mod.key := key;
			mod.data := memW;
			modules[mod.num] := mod;

			(* type descriptors *)
				ReadInt(R, n); ASSERT(n MOD 4 = 0, 100);
				INC(memW, n);
				n := n DIV 4;
				IF n > 0 THEN NEW(mod.typeds, n) END;
					mod.typedsLen := n;
				i := 0;
				WHILE n > 0 DO ReadInt(R, w);
					mod.typeds[i] := w; INC(i);
					DEC(n)
				END;

			(* variable space *)
				ReadInt(R, n); INC(memW, n);

			(* strings *)
				mod.strs := memW - mod.data;
				ReadInt(R, n); ASSERT(n MOD 4 = 0, 101);
				INC(memW, n);
				n := n DIV 4;
				IF n > 0 THEN NEW(mod.strings, n) END;
					mod.stringsLen := n;
				i := 0;
				WHILE n > 0 DO ReadInt(R, w);
					mod.strings[i] := w; INC(i);
					DEC(n)
				END;

			(* program *)
				IF ODD(flashW) THEN
					(* align, required for modules with
						"LDR r, [pc, offset]" instructions, pc must be multiple of 4;
						used for constants loading *)
					ARMv6M.EmitNOP(flash, flashW)
				END;
				mod.code := flashW;
				(* program code *)
					ReadInt(R, n);
					WHILE n > 0 DO ReadInt(R, w);
						flash[flashW] := w; INC(flashW);
						DEC(n)
					END;
				(* copy imports *)
					i := 0;
					WHILE i < nofimps DO
						mod.imports[i] := import[i];
						INC(i)
					END;

			(* skip commands *)
				Files.Read(R, ch);
				WHILE ch # 0X DO
					REPEAT Files.Read(R, ch) UNTIL ch = 0X; ReadInt(R, n);
					Files.Read(R, ch)
				END;

			(* entries *)
				ReadInt(R, n);
				NEW(mod.entries, n); mod.entriesLen := n; i := 0;
				WHILE n > 0 DO ReadInt(R, w);
					mod.entries[i] := w; INC(i);
					DEC(n)
				END;

			(* pointer references *)
				mod.nPtrs := 0;
				ReadInt(R, w);
				IF (w >= 0) & ODD(flashW) THEN (* align *)
					flash[flashW] := 0; INC(flashW)
				END;
				mod.ptr := flashW;
				WHILE w >= 0 DO
					ASSERT(w < mod.strs, 100);
					flash[flashW] := mod.data + w; (* will be fixed up in Link1 *)
					INC(flashW, 2); INC(mod.nPtrs);
					ReadInt(R, w)
				END;
				IF mod.nPtrs # 0 THEN
					flash[flashW] := 0; INC(flashW);
					flash[flashW] := 0; INC(flashW);
					INC(nPtrs)
				END;

			ReadInt(R, fixorgP);
			ReadInt(R, fixorgD);
			ReadInt(R, mod.fixorgT);

			(* entry point *)
				ReadInt(R, w); ASSERT(w MOD 4 = 0, 100);
				mod.body := mod.code + w DIV 4;

			Files.Read(R, ch);
			IF ch # "O" THEN (* corrupted file *) mod := NIL; error(4, name(*$*)) END
		END;

		IF res = 0 THEN

			(* fixup of BL *)
				adr := mod.code + fixorgP;
				WHILE adr # mod.code DO
					inst := flash[adr];
					ASSERT(inst DIV 10H * 10H = tagBL);
					a := inst MOD 10H;
					DEC(adr);
					inst := flash[adr];
					ASSERT(inst DIV 1000000H MOD 100H = 0F7H, 101); (* BL *)
					mno := inst DIV 100000H MOD 10H + a * 10H;
					pno := inst DIV 1000H MOD 100H;
					disp := inst MOD 1000H;
					impmod := mod.imports[mno-1];
					dest := impmod.entries[pno];
					ASSERT(dest MOD 4 = 0, 102); dest := dest DIV 4;
					dest := dest + impmod.code;
					offset := dest - adr - 1;
					i := adr; ARMv6M.EmitBL(flash, i, offset - 1);
					adr := adr - disp
				END;

			(* fixup of LDR/STR/ADD *)
				adr := (mod.code + fixorgD) * 4;
				WHILE adr DIV 4 # mod.code DO
					inst := flash[adr DIV 4];
					mno := inst DIV 100000H MOD 10H;
					disp := inst MOD 1000H;
					a := inst DIV 1000000H MOD 10H;
					ASSERT(a = SB, 103);
					ASSERT(inst DIV 10000000H MOD 10H = 8, 103); (* Ldr *)
					ASSERT(flash[adr DIV 4 + 1] DIV 10H * 10H = tagLdrSB);
					mno := mno + flash[adr DIV 4 + 1] MOD 10H * 10H;

					IF mno = 0 THEN (* global *)
						i := adr DIV 4;
						ARMv7M.EmitLWImW(flash, i, a, MT, mod.num * 4)
					ELSE (* import *)
						impmod := mod.imports[mno-1]; v := impmod.num;
						i := adr DIV 4; ARMv7M.EmitLWImW(flash, i, a, MT, v * 4);

						inst := flash[adr DIV 4 + 2];
						vno := inst MOD 100H;
						a := inst DIV 1000000H MOD 10H;
						b := inst DIV 100000H MOD 10H; ASSERT(b = SB, 100);
						nxt := flash[adr DIV 4 + 3];
						CASE inst DIV 10000000H MOD 10H OF 4:
							ASSERT(nxt = tagFixup);
							IF inst DIV 10000H MOD 10H = 8 (* Add *) THEN op := 2
							ELSE HALT(1)
							END
						| 8: (* Ldr *)
							IF nxt = tagFixup THEN op := 0
							ELSIF nxt = tagVLDR THEN op := 5
							ELSE HALT(2)
							END
						| 9: (* LdrB *)
							ASSERT(nxt = tagFixup);
							op := 1
						| 10: (* Str *)
							ASSERT(nxt = tagFixup);
							op := 3
						| 11: (* StrB *)
							ASSERT(nxt = tagFixup);
							op := 4
						END;

						offset := impmod.entries[vno];
						IF ODD(inst DIV 100H) THEN
							ASSERT(offset MOD 4 = 0);
							offset := offset DIV 2; (* now offset in bytes *)
							offset := offset + impmod.code * 2;
							HALT(126);
							offset := offset - impmod.data
						END;
						i := adr DIV 4 + 2;
						CASE op OF 0: ASSERT(offset MOD 4 = 0, 100);
							ARMv7M.EmitLWImW(flash, i, a, b, offset)
						| 1: ARMv7M.EmitLBImW(flash, i, a, b, offset)
						| 2: ASSERT(a # b, 102);
							EmitADDSIm0(flash, i, a, b, offset)
						| 3: ASSERT(offset MOD 4 = 0, 126);
							ARMv7M.EmitSWImW(flash, i, a, b, offset)
						| 4: ARMv7M.EmitSBImW(flash, i, a, b, offset)
						| 5: ASSERT(offset MOD 4 = 0);
							ARMv7M.EmitVLDR(flash, i, a, b, 1, offset DIV 4)
						END
					END;
					adr := adr - disp * 4
				END

				(* fixup of type descriptors will be made in Link1 *)

			ELSIF res >= 3 THEN COPY(name, importing);
			WHILE nofimps > 0 DO DEC(nofimps) END
			END
		END;
		newmod := mod
	END Load;

	PROCEDURE WriteIHEX32 ((*IN*) VAR name: ARRAY OF CHAR; (*IN*) VAR code: ARRAY OF INTEGER; codeLen: INTEGER; startAdr: INTEGER; SLA: INTEGER; (*OUT*) VAR ok: BOOLEAN);
		CONST maxRecLen = 16; (* <= 255 *)
			(*
				FlashMagic 7.50.3174 incorrectly handles hex files
					with maxRecLen = 255 (actually 252)
				Astrobe produces hex files with maxRecLen = 16
			*)
		VAR F: Files.File; R: Files.Rider;
			a: ARRAY 1 + 2 + 1 + maxRecLen + 1 OF INTEGER;
			r, offset, i: INTEGER;

		PROCEDURE WriteRec;
			VAR cs: INTEGER;
			PROCEDURE WriteH (x: INTEGER);
				PROCEDURE H (x: INTEGER);
				BEGIN
					IF x < 10 THEN Files.Write(R, CHR(x + ORD('0')))
					ELSE Files.Write(R, CHR(x - 10 + ORD('A')))
					END
				END H;
			BEGIN
				ASSERT(x >= 0, 20);
				ASSERT(x < 100H, 21);
				H(x DIV 10H); H(x MOD 10H)
			END WriteH;
		BEGIN
			Files.Write(R, ':');
			cs := 0;
			i := 0;
			WHILE i < 1 + 2 + 1 + a[0] DO
				WriteH(a[i]); cs := cs + a[i];
				INC(i)
			END;
			WriteH((-cs) MOD 100H);
			Files.Write(R, 0DX); Files.Write(R, 0AX)
		END WriteRec;

		PROCEDURE WriteELA (adr: INTEGER);
		BEGIN
			ASSERT(adr >= 0, 20);
			ASSERT(adr < 10000H, 21);
			a[0] := 2; (* len *)
			a[1] := 0; a[2] := 0; (* offset *)
			a[3] := 4; (* type: extended linear address *)
			a[4] := adr DIV 100H;
			a[5] := adr MOD 100H;
			WriteRec
		END WriteELA;

	BEGIN
		ASSERT(codeLen >= 0, 20);
		ASSERT(startAdr MOD 4 = 0, 21);
		F := NewHexFile(name);
		IF F # NIL THEN
			Files.Set(R, F, 0);
			r := 0;

			IF codeLen > 0 THEN
				offset := startAdr MOD 10000H;
				startAdr := startAdr DIV 10000H MOD 10000H;
				WriteELA(startAdr);
				REPEAT
					a[0] := 0;
					a[1] := offset DIV 100H; a[2] := offset MOD 100H;
					a[3] := 0; (* type: data *)
					i := 0;
					WHILE (i <= maxRecLen - 2) & (offset <= 10000H - 2) & (codeLen > 0) DO
						a[4+i] := code[r] MOD 100H;
						a[5+i] := code[r] DIV 100H MOD 100H;
						ASSERT(code[r] DIV 10000H = 0, 100); (* all fixups done *)
						INC(a[0], 2);
						INC(r); DEC(codeLen);
						INC(i, 2);
						INC(offset, 2)
					END;
					WriteRec;
					IF (codeLen > 0) & (offset = 10000H) THEN
						INC(startAdr);
						WriteELA(startAdr);
						offset := 0
					END
				UNTIL codeLen = 0
			END;

			a[0] := 4; (* len *)
			a[1] := 0; a[2] := 0; (* offset *)
			a[3] := 5; (* type: start linear address *)
			a[4] := SLA DIV 1000000H MOD 100H;
			a[5] := SLA DIV 10000H MOD 100H;
			a[6] := SLA DIV 100H MOD 100H;
			a[7] := SLA MOD 100H;
			WriteRec;

			a[0] := 0; a[1] := 0; a[2] := 0; a[3] := 1 (* type: EOF *); WriteRec;

			Files.Register(F);
			ok := TRUE
		ELSE ok := FALSE
		END
	END WriteIHEX32;

	PROCEDURE WriteBin ((*IN*) VAR name: ARRAY OF CHAR; (*IN*) VAR code: ARRAY OF INTEGER; codeLen: INTEGER; (*OUT*) VAR ok: BOOLEAN);
		VAR F: Files.File; R: Files.Rider;
			r: INTEGER;
	BEGIN
		ASSERT(codeLen >= 0, 20);
		F := NewBinFile(name);
		IF F # NIL THEN
			Files.Set(R, F, 0); r := 0;
			WHILE codeLen > 0 DO
				ASSERT(code[r] DIV 10000H = 0, 100); (* all fixups done *)
				Files.Write(*Byte*)(R, CHR(code[r] MOD 100H));
				Files.Write(*Byte*)(R, CHR(code[r] DIV 100H));
				INC(r); DEC(codeLen)
			END;
			Files.Register(F); ok := TRUE
		ELSE ok := FALSE
		END
	END WriteBin;

	PROCEDURE opcode (VAR d: INTEGER; w: LONGINT);
		VAR s: ARRAY 64 OF CHAR;
	BEGIN
		ARMv6M.OpcodeRepr(d, w, s);
		IF s[0] # 0X THEN Texts.WriteString(W, s) END
	END opcode;

	(* R.a := im *)
	(* see ARMv7MG.MovIm *)
	PROCEDURE MovIm0 (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; a: INTEGER; im: INTEGER);
		CONST S = 0;
		VAR shift: INTEGER;
			isLR: BOOLEAN;
			imInv: INTEGER; isMI: BOOLEAN; i, imm3, imm8, imm4: INTEGER;
	BEGIN
		ASSERT(a IN {0..14}, 21);

		isLR := a DIV 8 = 0;
		IF isLR & (im DIV 100H = 0) THEN
			ARMv6M.EmitMOVSIm(code, pc, a, im)
		ELSE
			ARMv7M.EncodeMI12(im, i, imm3, imm8, isMI);
			IF isMI THEN
				(* A7.7.75: MOV (immediate); encoding T2 ARMv7-M *)
					ARMv7M.EmitDPMI(code, pc, i, 4 + S, 0FH, imm3, a, imm8)
				(* S=1: N, Z, C will be updated *) (* NOTE: C *)
			ELSE
				imInv := ORDSET(BITS(im) / {0..31});
				ARMv7M.EncodeMI12(imInv, i, imm3, imm8, isMI);
				IF isMI THEN
					(* A7.7.84: MVN (immediate); encoding T1 ARMv7-M *)
						ARMv7M.EmitDPMI(code, pc, i, 6 + S, 0FH, imm3, a, imm8)
						(* S=1: N, Z, C will be updated *) (* NOTE: C *)
				ELSIF isLR & (im > 255) & (im <= 255 + 255) THEN
					ARMv6M.EmitMOVSIm(code, pc, a, 255);
					ARMv6M.EmitADDSIm(code, pc, a, a, im - 255)
				ELSE
					shift := 8;
					WHILE (shift < 32) & (SYSTEM.ROT(im DIV 100H * 100H, -shift) DIV 100H # 0) DO INC(shift) END;
					IF isLR & (shift < 32) THEN
						ASSERT(im =
							SYSTEM.LSH(SYSTEM.ROT(im DIV 100H * 100H, -shift), shift)
							+ im MOD 100H);
						ARMv6M.EmitMOVSIm(code, pc, a, SYSTEM.ROT(im DIV 100H * 100H, -shift));
						ARMv6M.EmitLSLSIm(code, pc, a, a, shift);
						ARMv6M.EmitADDSIm(code, pc, a, a, im MOD 100H)
					ELSE
						(* TODO: 3 ops: mov; (add, lsl), (lsl, sub), (lsl, sub) | MI12; add, lsl, sub *)
						IF isLR & (im MOD 10000H DIV 100H = 0) THEN
							ARMv6M.EmitMOVSIm(code, pc, a, im MOD 10000H)
						ELSE
							(* A7.7.75: MOV (immediate); encoding T3 ARMv7-M *)
								imm4 := im DIV 1000H MOD 10H;
								i := im DIV 800H MOD 2;
								imm3 := im DIV 100H MOD 8;
								imm8 := im MOD 100H;
								ARMv7M.EmitDPPBI(code, pc, i, 4, imm4, imm3 * 1000H + a * 100H + imm8)
						END;
						im := im DIV 10000H;
						IF im # 0 THEN
							(* A7.7.78: MOVT; encoding T1 ARMv7 *)
								imm4 := im DIV 1000H MOD 10H;
								i := im DIV 800H MOD 2;
								imm3 := im DIV 100H MOD 8;
								imm8 := im MOD 100H;
								ARMv7M.EmitDPPBI(code, pc, i, 12, imm4, imm3 * 1000H + a * 100H + imm8)
						END
					END
				END
			END
		END
	END MovIm0;

	PROCEDURE SubIm0 (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, n, im: INTEGER);
	BEGIN
		IF im DIV 8 = 0 THEN
			ARMv6M.EmitSUBSIm(code, pc, d, n, im)
		ELSE
			IF d # n THEN
				ARMv6M.EmitMOVSR(code, pc, d, n);
			END;
			ARMv6M.EmitSUBSIm(code, pc, d, d, im)
		END
	END SubIm0;

	PROCEDURE StrIm0 (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; t, n, im: INTEGER);
	BEGIN
		IF im DIV 32 = 0 THEN ARMv6M.EmitSTRIm(code, pc, t, n, im)
		ELSE ARMv7M.EmitSWImW(code, pc, t, n, im * 4)
		END
	END StrIm0;

	PROCEDURE Link1 ((*IN*) VAR name: ARRAY OF CHAR);
		VAR MTOrg, StkOrg, i, j: INTEGER;
			ok: BOOLEAN;
			mod, impmod: Module;
			adr, inst, mno, vno, disp, offset: INTEGER;
			r0, r1: INTEGER; r0a, r1a: BOOLEAN;
	BEGIN
		ASSERT(memW MOD 4 = 0, 100); (* should be aligned *)
		(* memW := (memW + 3) DIV 4 * 4; *) (* align *)

		MTOrg := target.SRAMStart + target.SRAMSize
			- (root.num + 1) * 4; (* MTab *)

		(* initial SP *)
			StkOrg := MTOrg - (nPtrs + 1) * 4 - memW;
			flash[0] := StkOrg MOD 10000H;
			flash[1] := StkOrg DIV 10000H MOD 10000H;

		(* reset vector *)
			inst := target.flashStart + flashW * 2 + 1;
			flash[2] := inst MOD 10000H;
			flash[3] := inst DIV 10000H MOD 10000H;

		(* CPU exceptions (NMI..SysTick) *)
			i := 4; WHILE i < 40H DIV 2 DO
				flash[i] := 1; INC(i);
				flash[i] := 0; INC(i)
			END;
		WHILE i < 40H DIV 2 + target.maxExtInts * 2 DO
			flash[i] := 1; INC(i);
			flash[i] := 0; INC(i)
		END;
		WHILE i < target.flashOrg DIV 2 DO
			flash[i] := 0; INC(i);
			flash[i] := 0; INC(i)
		END;
		IF target.isNXP THEN
			(* code read protection (CRP) *)
				flash[2FCH DIV 2] := 0; flash[2FCH DIV 2 + 1] := 0;
			(* NXP checksum *)
				j := 0; i := 0; WHILE i < 7 DO
					j := j + flash[2 * i] + 10000H * flash[2 * i + 1];
					INC(i)
				END;
				flash[2 * i] := (-j) MOD 10000H;
				flash[2 * i + 1] := (-j) DIV 10000H MOD 10000H
		END;

		IF memW > 0 THEN
			(* R[MT] := MTOrg *)
				MovIm0(flash, flashW, MT, MTOrg);

			(* modules ptrs table *)
				(* R[0] := MT - (nPtrs + 1) * 4 *)
					SubIm0(flash, flashW, 0, MT, (nPtrs + 1) * 4);
				i := 0; mod := root;
				WHILE mod # NIL DO
					IF mod.nPtrs # 0 THEN
						(* R[1] := flashStart + mod.ptr * 2 *)
							MovIm0(flash, flashW, 1,
								target.flashStart + mod.ptr * 2);
						(* Mem[R[0] + i * 4] := R[1] *)
							StrIm0(flash, flashW, 1, 0, i);
						INC(i)
					END;
					mod := mod.next
				END;
				ASSERT(i = nPtrs, 101);
				(* R[1] := i *)
					MovIm0(flash, flashW, 1, i);
				(* Mem[R[0] + i * 4] := R[1] *)
					StrIm0(flash, flashW, 1, 0, i);

			(* MT, type descriptors and strings *)
				j := 0;
				r0a := FALSE; r1a := FALSE;
				WHILE j <= root.num DO mod := modules[j];
					IF ~r0a OR (r0 # StkOrg + mod.data) THEN
						(* R[0] := StkOrg + mod.data *)
							MovIm0(flash, flashW, 0, StkOrg + mod.data);
							r0 := StkOrg + mod.data; r0a := TRUE
					END;
					(* MTab *)
						(* Mem[R[MT] + mod.num * 4] := R[0] *)
							StrIm0(flash, flashW, 0, MT, mod.num);

					(* fixup of type descriptors *)
						adr := mod.fixorgT * 4;
						WHILE adr DIV 4 # 0 DO
							inst := mod.typeds[adr DIV 4];
							IF trace THEN Texts.WriteLn(W);
								Texts.WriteString(W, "td fixup: ");
								Texts.WriteInt(W, adr DIV 4, 0);
								Texts.WriteHex(W, inst);
								Texts.WriteString(W, " -> ")
							END;
							mno := inst DIV 1000000H MOD 100H;
							vno := inst DIV 1000H MOD 1000H;
							disp := inst MOD 1000H;
							IF mno = 0 THEN (*global*) inst := StkOrg + mod.data + vno
							ELSE (*import*)
								impmod := mod.imports[mno-1];
								offset := impmod.entries[vno];
								inst := StkOrg + impmod.data + offset
							END;
							IF trace THEN Texts.WriteHex(W, inst) END;
							mod.typeds[adr DIV 4] := inst;
							adr := adr - disp * 4
						END;

					IF mod.typeds # NIL THEN (* type descriptors *)
						i := 0;
						WHILE i < mod.typedsLen DO
							IF ~r1a OR (r1 # mod.typeds[i]) THEN
								(* R[1] := mod.typeds[i] *)
									MovIm0(flash, flashW, 1, mod.typeds[i]);
									r1 := mod.typeds[i]; r1a := TRUE
							END;
							(* Mem[R[0] + i * 4] := R[1] *)
								StrIm0(flash, flashW, 1, 0, i);
							INC(i)
						END
					END;
					IF mod.strings # NIL THEN (* strings *)
						i := 0;
						WHILE i < mod.stringsLen DO
							IF ~r1a OR (r1 # mod.strings[i]) THEN
								(* R[1] := mod.strings[i] *)
									MovIm0(flash, flashW, 1, mod.strings[i]);
									r1 := mod.strings[i]; r1a := TRUE
							END;
							(* Mem[R[0] + mod.strs + i * 4] := R[1] *)
								ASSERT(mod.strs MOD 4 = 0);
								StrIm0(flash, flashW, 1, 0, mod.strs DIV 4 + i);
							INC(i)
						END
					END;

					(* fixup of pointer references *)
						i := 0;
						WHILE i < mod.nPtrs DO
							inst := StkOrg + flash[mod.ptr + i * 2];
							flash[mod.ptr + i * 2] := inst MOD 10000H;
							flash[mod.ptr + i * 2 + 1] := inst DIV 10000H MOD 10000H;
							INC(i)
						END;

					INC(j)
				END
		END;

		(* body calls *)
			i := 0;
			WHILE i <= root.num DO
				ARMv6M.EmitBL(flash, flashW, modules[i].body - flashW - 1 - 1);
				INC(i)
			END;

		(* stop *)
			ARMv6M.EmitB(flash, flashW, -1 - 1);

		IF ODD(flashW) THEN (* align *)
			ARMv6M.EmitNOP(flash, flashW)
		END;

		IF flashW * 2 <= target.flashSize THEN
			WriteIHEX32(name, flash, flashW,
				target.flashStart, target.flashStart + 1, ok);
			IF ~ok THEN res := 9 END;
			WriteBin(name, flash, flashW, ok);
			IF ~ok & (res = 0) THEN res := 10 END
		ELSE
			res := 8
		END
	END Link1;

	PROCEDURE Link*;
		VAR i: INTEGER;
			S: Texts.Scanner;
			mod: Module;
			d: INTEGER;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN
			target := targets;
			WHILE (target # NIL) & ~CmpStr(target.name, S.s) DO
				target := target.next
			END;
			IF target # NIL THEN
				Texts.Scan(S);
				IF S.class = Texts.Name THEN
					Texts.WriteString(W, "linking "); Texts.WriteString(W, S.s); Texts.WriteString(W, " ");

					root := NIL;
					flashW := target.flashOrg DIV 2;
					memW := 0;
					nPtrs := 0;
					Load(S.s, mod);

					IF res = 0 THEN Link1(S.s) END;

					CASE res OF 0:
						IF trace THEN Texts.WriteLn(W) END;
						Texts.WriteString(W, "Ok"); Texts.WriteLn(W);

						i := 0;
						WHILE i <= root.num DO mod := modules[i];
							Texts.Write(W, 9X);
							Texts.WriteString(W, mod.name);
							Texts.Write(W, 9X);
							Texts.WriteInt(W, mod.code, 0); Texts.WriteLn(W);
							INC(i)
						END;

						Texts.WriteString(W, "ROM: ");
							Texts.WriteInt(W, flashW * 2 (* - target.flashOrg *), 0);
							Texts.WriteString(W, " B; RAM: ");
							Texts.WriteInt(W,
								memW + (nPtrs + 1) * 4 + (root.num + 1) * 4, 0);
								Texts.WriteString(W, " B");

						IF trace THEN Texts.WriteLn(W);
							mod := root;
							WHILE mod # NIL DO
								Texts.WriteString(W, mod.name); Texts.WriteString(W, ":"); Texts.WriteLn(W);
									Texts.WriteString(W, "  num: ");
										Texts.WriteInt(W, mod.num, 0); Texts.WriteLn(W);
									Texts.WriteString(W, "  data: ");
										Texts.WriteInt(W, mod.data, 0); Texts.WriteLn(W);
									Texts.WriteString(W, "  strs: ");
										Texts.WriteInt(W, mod.strs, 0); Texts.WriteLn(W);
									Texts.WriteString(W, "  code: ");
										Texts.WriteInt(W, mod.code, 0); Texts.WriteLn(W);
									Texts.WriteString(W, "  entries:");
										i := 0;
										WHILE i < mod.entriesLen DO
											Texts.Write(W, ' ');
											Texts.WriteInt(W, mod.entries[i], 0);
											INC(i)
										END;
										Texts.WriteLn(W);
									Texts.WriteString(W, "  body: ");
										Texts.WriteInt(W, mod.body, 0); Texts.WriteLn(W);
								mod := mod.next
							END;

							i := 0; d := 0;
							WHILE i < flashW DO
								Texts.WriteInt(W, i, 4); Texts.Write(W, 9X);
									Texts.WriteHex(W, flash[i]); Texts.Write(W, 9X); opcode(d, flash[i]);
									Texts.WriteLn(W);
								INC(i)
							END;
							IF d # 0 THEN
								Texts.WriteString(W, "invalid decoder state");
								Texts.WriteLn(W)
							END
						END
					| 1: Texts.WriteString(W, "file not available: "); Texts.WriteString(W, importing)
					| 2: Texts.WriteString(W, "invalid version: "); Texts.WriteString(W, importing)
					| 3: Texts.WriteString(W, "key conflict: "); Texts.WriteString(W, importing); Texts.WriteString(W, ": "); Texts.WriteString(W, imported)
					| 4: Texts.WriteString(W, "corrupted file: "); Texts.WriteString(W, importing)
					| 7: Texts.WriteString(W, "no space: "); Texts.WriteString(W, importing)
					| 8: Texts.WriteString(W, "end of flash")
					| 9: Texts.WriteString(W, "write HEX failed")
					| 10: Texts.WriteString(W, "write BIN failed")
					END;
					Texts.WriteLn(W)
				END
			ELSE Texts.WriteString(W, "invalid target"); Texts.WriteLn(W);
				target := targets;
				WHILE target # NIL DO
					Texts.WriteString(W, target.name); Texts.WriteLn(W);
					target := target.next
				END
			END;

			Texts.Append(Oberon.Log, W.buf)
		END;
		(*Oberon.Collect(0)*)
	END Link;

	PROCEDURE EnterNXP ((*IN*) name: TargetName; maxExtInts, flashSize, SRAMSize, IAPReserve: INTEGER);
		VAR target: Target;
	BEGIN
		ASSERT(maxExtInts > 0, 20);
		ASSERT(maxExtInts <= 240 (* Cortex-M4 *), 21);
		ASSERT(flashSize MOD 4 = 0, 22);
		ASSERT(SRAMSize MOD 4 = 0, 23);

		NEW(target); target.next := targets; targets := target;
		target.name := name;
		target.isNXP := TRUE;
		target.flashStart := 0;
		target.maxExtInts := maxExtInts;
		target.flashOrg := (16 + maxExtInts) * 4;
		IF target.flashOrg <= 2FCH (* CRP *) THEN
			target.flashOrg := 2FCH (* CRP *) + 4
		END;
		target.flashSize := flashSize;
		target.SRAMStart := 10000000H;
		target.SRAMSize := SRAMSize - IAPReserve
	END EnterNXP;

	PROCEDURE EnterSTM ((*IN*) name0, fpo0, fpo1: ARRAY OF CHAR; maxExtInts, flashOrg, SRAMSize: INTEGER);
		VAR target: Target; i, j, k: INTEGER;
	BEGIN
		ASSERT(maxExtInts > 0, 20);
		ASSERT(maxExtInts <= 240 (* Cortex-M4 *), 21);
		ASSERT(flashOrg MOD 4 = 0, 22);
		ASSERT(flashOrg >= (16 + maxExtInts) * 4, 23);
		ASSERT(SRAMSize MOD 4 = 0, 24);

		i := 0;
		WHILE i < StrLen(fpo0) DO
			j := 0;
			WHILE j < StrLen(fpo1) DO
				NEW(target); target.next := targets; targets := target;
				target.name := name0(*$*); k := StrLen(target.name);
					target.name[k] := fpo0[i]; INC(k);
					target.name[k] := fpo1[j]; INC(k);
					target.name[k] := 0X;
				target.isNXP := FALSE;
				target.flashStart := 08000000H;
				target.maxExtInts := maxExtInts;
				target.flashOrg := flashOrg;
				IF fpo1[j] = '4' THEN target.flashSize := 4000H (* 16 KiB *)
				ELSIF fpo1[j] = '6' THEN target.flashSize := 8000H (* 32 KiB *)
				ELSIF fpo1[j] = '8' THEN target.flashSize := 10000H (* 64 KiB *)
				ELSIF fpo1[j] = 'B' THEN target.flashSize := 20000H (* 128 KiB *)
				ELSIF fpo1[j] = 'C' THEN target.flashSize := 40000H (* 256 KiB *)
				ELSIF fpo1[j] = 'D' THEN target.flashSize := 60000H (* 384 KiB *)
				ELSIF fpo1[j] = 'E' THEN target.flashSize := 80000H (* 512 KiB *)
				ELSIF fpo1[j] = 'F' THEN target.flashSize := 0C0000H (* 768 KiB *)
				ELSIF fpo1[j] = 'G' THEN target.flashSize := 100000H (* 1 MiB *)
				ELSIF fpo1[j] = 'I' THEN target.flashSize := 200000H (* 2 MiB *)
				ELSE HALT(100) (* invalid fpo1[j] *)
				END;
				target.SRAMStart := 20000000H;
				target.SRAMSize := SRAMSize;
				INC(j)
			END;
			INC(i)
		END
	END EnterSTM;

	(* Cortex-M3 *)
	PROCEDURE EnterCC1310 ((*IN*) name: TargetName; flashSize, SRAMSize: INTEGER);
		CONST
			maxExtInts = 34;
			CCFGSize = 88;
	BEGIN
		ASSERT(flashSize MOD 4 = 0, 20);
		ASSERT(SRAMSize MOD 4 = 0, 21);

		NEW(target); target.next := targets; targets := target;
		target.name := name;
		target.isNXP := FALSE;
		target.flashStart := 0;
		target.maxExtInts := maxExtInts;
		target.flashOrg := (16 + maxExtInts) * 4;
		target.flashSize := flashSize - CCFGSize;
		target.SRAMStart := 20000000H;
		target.SRAMSize := SRAMSize
	END EnterCC1310;

	(* Cortex-M3 *)
	PROCEDURE EnterLM3S ((*IN*) name: TargetName; flashSize, SRAMSize: INTEGER; maxExtInts: INTEGER);
	BEGIN
		ASSERT(flashSize MOD 4 = 0, 20);
		ASSERT(SRAMSize MOD 4 = 0, 21);
		ASSERT(maxExtInts > 0, 22);
		ASSERT(maxExtInts <= 240 (* Cortex-M4 *), 23);

		NEW(target); target.next := targets; targets := target;
		target.name := name;
		target.isNXP := FALSE;
		target.flashStart := 0;
		target.maxExtInts := maxExtInts;
		target.flashOrg := (16 + maxExtInts) * 4;
		target.flashSize := flashSize;
		target.SRAMStart := 20000000H;
		target.SRAMSize := SRAMSize
	END EnterLM3S;

	PROCEDURE EnterSAM ((*IN*) name0, fpo0: ARRAY OF CHAR; maxExtInts, flashOrg, flashSize, SRAMSize: INTEGER);
		CONST
			flashStart = 400000H;
			internalROMStart = 800000H;
			SRAMStart = 20000000H;
		VAR i, k: INTEGER;
	BEGIN
		ASSERT(maxExtInts > 0, 20);
		ASSERT(maxExtInts <= 240 (* Cortex-M4 *), 21);
		ASSERT(flashOrg MOD 80H = 0, 22);
		ASSERT(flashOrg >= (16 + maxExtInts) * 4, 23);
		ASSERT(flashSize MOD 4 = 0, 24);
		ASSERT(flashStart + flashSize <= internalROMStart, 25);
		ASSERT(SRAMSize MOD 4 = 0, 26);

		i := 0;
		WHILE i < StrLen(fpo0) DO
			NEW(target); target.next := targets; targets := target;
			target.name := name0(*$*); k := StrLen(target.name);
				target.name[k] := fpo0[i]; INC(k);
				target.name[k] := 0X;
			target.isNXP := FALSE;
			target.flashStart := flashStart;
			target.maxExtInts := maxExtInts;
			target.flashOrg := flashOrg;
			target.flashSize := flashSize;
			target.SRAMStart := SRAMStart;
			target.SRAMSize := SRAMSize;
			INC(i)
		END
	END EnterSAM;

BEGIN Texts.OpenWriter(W); Texts.WriteString(W, "OARMv7MLinker 11.1.2017");
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);

	targets := NIL;

	EnterNXP("LPC1311", 58, 2000H (* 8 KiB *), 1000H (* 4 KiB *), 32);
	EnterNXP("LPC1313", 58, 8000H (* 32 KiB *), 2000H (* 8 KiB *), 32);
	EnterNXP("LPC1342", 58, 4000H (* 16 KiB *), 1000H (* 4 KiB *), 32);
	EnterNXP("LPC1343", 58, 8000H (* 32 KiB *), 2000H (* 8 KiB *), 32);

	EnterNXP("LPC1751", 35, 8000H (* 32 KiB *), 2000H (* 8 KiB *), 32);
	EnterNXP("LPC1752", 35, 10000H (* 64 KiB *), 4000H (* 16 KiB *), 32);
	EnterNXP("LPC1754", 35, 20000H (* 128 KiB *), 8000H (* 32 KiB *), 32);
	EnterNXP("LPC1756", 35, 40000H (* 256 KiB *), 8000H (* 32 KiB *), 32);
	EnterNXP("LPC1758", 35, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1759", 35, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1763", 35, 40000H (* 256 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1764", 35, 20000H (* 128 KiB *), 8000H (* 32 KiB *), 32);
	EnterNXP("LPC1765", 35, 40000H (* 256 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1766", 35, 40000H (* 256 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1767", 35, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1768", 35, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1769", 35, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);

	EnterNXP("LPC1773", 41, 20000H (* 128 KiB *), 8000H (* 32 KiB *), 32);
	EnterNXP("LPC1774", 41, 20000H (* 128 KiB *), 8000H (* 32 KiB *), 32);
	EnterNXP("LPC1776", 41, 40000H (* 256 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1777", 41, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1778", 41, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1785", 41, 40000H (* 256 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1786", 41, 40000H (* 256 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1787", 41, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC1788", 41, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);

	(* no FPU *)
		EnterNXP("LPC4072", 41, 10000H (* 64 KiB *), 4000H (* 16 KiB *), 32);
		EnterNXP("LPC4074", 41, 20000H (* 128 KiB *), 8000H (* 32 KiB *), 32);
	EnterNXP("LPC4076", 41, 40000H (* 256 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC4078", 41, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);
	EnterNXP("LPC4088", 41, 80000H (* 512 KiB *), 10000H (* 64 KiB *), 32);

	(* 4 KiB of SRAM *)
		EnterSTM("STM32F100", "CR", "46", 61, 200H, 1000H);
		EnterSTM("STM32F101", "RT", "4", 60, 200H, 1000H);
		EnterSTM("STM32F102", "CR", "4", 60, 200H, 1000H);

	(* 6 KiB of SRAM *)
		EnterSTM("STM32F101", "CRT", "6", 60, 200H, 1800H);
		EnterSTM("STM32F102", "CR", "6", 60, 200H, 1800H);
		EnterSTM("STM32F103", "CRT", "4", 60, 200H, 1800H);

	(* 8 KiB of SRAM *)
		EnterSTM("STM32F100", "CRV", "8B", 61, 200H, 2000H);

	(* 10 KiB of SRAM *)
		EnterSTM("STM32F101", "CRTV", "8", 60, 200H, 2800H);
		EnterSTM("STM32F102", "CR", "8", 60, 200H, 2800H);
		EnterSTM("STM32F103", "CRT", "6", 60, 200H, 2800H);

	(* 16 KiB of SRAM *)
		EnterSTM("STM32F101", "CRTV", "B", 60, 200H, 4000H);
		EnterSTM("STM32F102", "CR", "B", 60, 200H, 4000H);
		EnterSTM("STM32F301", "CKR", "68", 82, 200H, 4000H);
		EnterSTM("STM32F302", "CKR", "68", 82, 200H, 4000H);
		EnterSTM("STM32F303", "CKR", "68", 82, 200H, 4000H);

	(* 20 KiB of SRAM *)
		EnterSTM("STM32F103", "CRTV", "8B", 60, 200H, 5000H);

	(* 24 KiB of SRAM *)
		EnterSTM("STM32F100", "RVZ", "C", 61, 200H, 6000H);

	(* 32 KiB of SRAM *)
		EnterSTM("STM32F100", "RVZ", "DE", 61, 200H, 8000H);
		EnterSTM("STM32F101", "RVZ", "C", 60, 200H, 8000H);
		EnterSTM("STM32F302", "CRV", "B", 85, 200H, 8000H);

	(* 40 KiB of SRAM *)
		EnterSTM("STM32F302", "CRV", "C", 85, 200H, 0A000H);
		EnterSTM("STM32F303", "CRV", "B", 85, 200H, 0A000H);

	(* 48 KiB of SRAM *)
		EnterSTM("STM32F101", "RVZ", "DE", 60, 200H, 0C000H);
		EnterSTM("STM32F103", "RVZ", "C", 60, 200H, 0C000H);
		EnterSTM("STM32F303", "CRV", "C", 85, 200H, 0C000H);

	(* 64 KiB of SRAM *)
		EnterSTM("STM32F103", "RVZ", "DE", 60, 200H, 10000H);
		EnterSTM("STM32F105", "RV", "8BC", 68, 200H, 10000H);
		EnterSTM("STM32F107", "RV", "BC", 68, 200H, 10000H);
		EnterSTM("STM32F302", "RVZ", "DE", 85, 200H, 10000H);
		EnterSTM("STM32F401", "CRV", "BC", 85, 200H, 10000H);

(* memory hole?
	(* 48+16 KiB of SRAM *)
		EnterSTM("STM32F205", "RV", "B", 81, 200H, 10000H);
*)

	(* 80 KiB of SRAM *)
		EnterSTM("STM32F101", "RVZ", "FG", 60, 200H, 14000H);
		EnterSTM("STM32F303", "RVZ", "DE", 85, 200H, 14000H);

	(* 96 KiB of SRAM *)
		EnterSTM("STM32F103", "RVZ", "FG", 60, 200H, 18000H);
		EnterSTM("STM32F401", "CRV", "DE", 85, 200H, 18000H);

(* memory hole?
	(* 80+16 KiB of SRAM *)
		EnterSTM("STM32F205", "RVZ", "C", 81, 200H, 18000H);
*)

	(* 128 KiB of SRAM *)
		EnterSTM("STM32F411", "CRV", "CE", 86, 200H, 20000H);

	(* 112+16 KiB of SRAM *)
		EnterSTM("STM32F205", "RVZ", "EFG", 81, 200H, 20000H);
		EnterSTM("STM32F207", "IVZ", "CEFG", 81, 200H, 20000H);
		EnterSTM("STM32F215", "RVZ", "EG", 81, 200H, 20000H);
		EnterSTM("STM32F217", "IVZ", "EG", 81, 200H, 20000H);
		EnterSTM("STM32F405", "O", "E", 82, 200H, 20000H);
		EnterSTM("STM32F405", "ORVZ", "G", 82, 200H, 20000H);
		EnterSTM("STM32F407", "IVZ", "EG", 82, 200H, 20000H);
		EnterSTM("STM32F415", "ORVZ", "G", 82, 200H, 20000H);
		EnterSTM("STM32F417", "IVZ", "EG", 82, 200H, 20000H);
		EnterSTM("STM32F446", "MRVZ", "CE", 97, 200H, 20000H);

	(* 112+16+64 KiB of SRAM *)
		EnterSTM("STM32F427", "IVZ", "GI", 91, 200H, 30000H);
		EnterSTM("STM32F429", "BINVZ", "EGI", 91, 200H, 30000H);
		EnterSTM("STM32F437", "IVZ", "GI", 91, 200H, 30000H);
		EnterSTM("STM32F439", "BINVZ", "GI", 91, 200H, 30000H);

	(* 64 KiB (DTCM) + 240 KiB (SRAM1) + 16 KiB (SRAM2) *)
		EnterSTM("STM32F756", "BINVZ", "EG",
			240 (* FIXME *), (16 + 240) * 4 (* FIXME *), 50000H);

	EnterCC1310("CC1310F32", 8000H (* 32 KiB *), 4000H (* 16 KiB *));
	EnterCC1310("CC1310F64", 10000H (* 64 KiB *), 4000H (* 16 KiB *));
	EnterCC1310("CC1310F128", 20000H (* 128 KiB *), 5000H (* 20 KiB *));

	EnterLM3S("LM3S811", 10000H (* 64 KiB *), 2000H (* 8 KiB *), 26);
	EnterLM3S("LM3S6965", 40000H (* 256 KiB *), 10000H (* 64 KiB *), 38);

	EnterSAM("SAM3S1", "ABC", 35, 200H,
		10000H (* 64 KiB *), 4000H (* 16 KiB *));
	EnterSAM("SAM3S2", "ABC", 35, 200H,
		20000H (* 128 KiB *), 8000H (* 32 KiB *));
	EnterSAM("SAM3S4", "ABC", 35, 200H,
		40000H (* 256 KiB *), 0C000H (* 48 KiB *))
END O7ARMv7MLinker.
