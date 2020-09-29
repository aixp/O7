MODULE O7ARMv7MG; (* NW  18.4.2016 / 31.5.2019  code generator in Oberon-07 for RISC*)

	(* Modified for ARMv7-M by A. V. Shiryaev, 2018.05.25, 2019.10.21 *)

	(*
http://www.inf.ethz.ch/personal/wirth/FPGA-relatedWork/RISC-Arch.pdf

http://infocenter.arm.com/help/topic/com.arm.doc.ddi0439d/DDI0439D_cortex_m4_processor_r0p1_trm.pdf

		ARMv7-M Architecture Reference Manual
			https://web.eecs.umich.edu/~prabal/teaching/eecs373-f10/readings/ARMv7-M_ARM.pdf
	*)

	(*
		TODO:
			LEN(record.arrayOfChar):
				Reg Stack
				invalid code generated when no Reg Stack compile-time error
			implement "special feautures" (see RISC-Arch.pdf, section 4):
				implement MOV+U F0, c = 1 feature? save flags to register
					when it's required?
					MRS instruction
			check loadCond (IsFlagsUp0 related)
			implement LDPSR
			see PO.Applications.pdf, p. 47
			shifts...
			implementation limits:
				use long B and BC branches:
					use short B and BC where possible (see Put3orig(BC...)),
						else use long B and BC..
			optimizations:
				arrays assignment (see PO.Applications.pdf, 45):
					use special command instead of loop
				bits:
					SYSTEM.BIT(adr, bit)
					...
				register procedures
				MovIm...	https://github.com/aixp/ProjectOberon2013/commit/873fe7ef74a2c41592f9904ad7c3893e4a368d58
		NOTE:
			do not try to optimize CMP, BC -> CB[N]Z:
				fixups:
					fixup problems
				else:
					there is no places where to use
			do not remove redundant cmps in Put3 (fixup problems)
	*)

	IMPORT SYSTEM, Files, ORS := O7S, ORB := O7B, ARMv6M := O7ARMv6M, ARMv7M := O7ARMv7M;
	(*Code generator for Oberon compiler for RISC processor.
		 Procedural interface to Parser OSAP; result in array "code".
		 Procedure Close writes code-files*)

	TYPE
		LONGINT = INTEGER;
		BYTE = CHAR;

	CONST WordSize* = 4;

		parblksize0Proc* = 0; parblksize0Int* = 0;

		(* MT = 12; SB = 13; SP = 14; LNK = 15;	 (*dedicated registers*) *)

		MT = 11; SB = 12; SP = ARMv6M.SP; LNK = ARMv6M.LR;

		maxCode = 16000; maxStrx = 2400; maxTD = 160; C24 = 1000000H;
		Reg = 10; RegI = 11; Cond = 12;	(*internal item modes*)

	(*frequently used opcodes*)	U = 2000H; V = 1000H;
		Mov = 0; Lsl = 1; Asr = 2; Ror= 3; And = 4; Ann = 5; Ior = 6; Xor = 7;
		Add = 8; Sub = 9; Cmp = 9; Mul = 10; Div = 11;
		Ldr = 8; Str = 10;
		BR = 0; BLR = 1; BC = 2; BL = 3;
		MI = 0; PL = 8; EQ = 1; NE = 9; LT = 5; GE = 13; LE = 6; GT = 14;

		TYPE Item* = RECORD
			mode*: INTEGER;
			type*: ORB.Type;
			a-, b-, r: LONGINT;
			rdo-: BOOLEAN	(*read only*)
		END ;

	(* Item forms and meaning of fields:
		mode		r			a			 b
		--------------------------------
		Const	 -		 value (proc adr)	 (immediate value)
		Var		 base	 off		 -							 (direct adr)
		Par			-		 off0		 off1				 (indirect adr)
		Reg		regno											(regno >= 100H: FPU register)
		RegI	 regno	 off		 -
		Cond	cond	 Fchain	Tchain	*)

	VAR pc-, varsize: LONGINT;	 (*program counter, data index*)
		tdx, strx: LONGINT;
		entry: LONGINT;	 (*main entry point*)
		RH: LONGINT;	(*available registers R[0] ... R[H-1]*)
		curSB: LONGINT;	(*current static base in SB*)
		frame: LONGINT;	(*frame offset changed in SaveRegs and RestoreRegs*)
		fixorgP, fixorgD, fixorgT: LONGINT;	 (*origins of lists of locations to be fixed up by loader*)
		check: BOOLEAN;	(*emit run-time checks*)
		version: INTEGER;	(* 0 = RISC-0, 1 = RISC-5 *)

		relmap: ARRAY 6 OF INTEGER;	(*condition codes for relations*)
		armcode: ARRAY maxCode OF LONGINT;
		data: ARRAY maxTD OF LONGINT;	(*type descriptors*)
		str: ARRAY maxStrx OF CHAR;

		RM: SET; (* registers modified *)
		enterPushFixup: INTEGER;

		FR: SET; (* for SaveRegs/RestoreRegs *)

		updateCarry: BOOLEAN;

	PROCEDURE BITS (x: INTEGER): SET;
	BEGIN
		RETURN SYSTEM.VAL(SET, x)
	END BITS;

	PROCEDURE ORDSET (x: SET): INTEGER;
	BEGIN
		RETURN SYSTEM.VAL(INTEGER, x)
	END ORDSET;

	PROCEDURE LSL (x, n: INTEGER): INTEGER;
	BEGIN RETURN SYSTEM.LSH(x, n)
	END LSL;

	(*instruction assemblers according to formats*)

	(* for fixups only *)
		PROCEDURE Put1orig (op, a, b, im: LONGINT);
		BEGIN (*emit format-1 instruction,	-10000H <= im < 10000H*)
			IF im < 0 THEN INC(op, V) END;
			armcode[pc] := (((a+40H) * 10H + b) * 10H + op) * 10000H + (im MOD 10000H); INC(pc)
		END Put1orig;

		PROCEDURE Put2orig (op, a, b, off: LONGINT);
		BEGIN (*emit load/store instruction*)
			ASSERT(op DIV 10H = 0);
			ASSERT(a DIV 10H = 0);
			ASSERT(b DIV 10H = 0);
			armcode[pc] := ((op * 10H + a) * 10H + b) * 100000H + (off MOD 100000H); INC(pc)
		END Put2orig;

		PROCEDURE Put3orig (op, cond, off: LONGINT);
		BEGIN (*emit branch instruction*)
			armcode[pc] := ((op+12) * 10H + cond) * 1000000H + (off MOD 1000000H); INC(pc);
			IF op = BC THEN (* armcode[pc] := 00FFFFFEH; INC(pc) *)
			ELSIF op = BL THEN armcode[pc] := 00FFFFFFH; INC(pc)
			ELSE HALT(1)
			END
		END Put3orig;

	(*
		encode register
		NOTE:
			R0-R3, R12, LR: not need to save on interrupts
			R0-R7: best for Thumb-16 instructions
	*)
	PROCEDURE ER (a: INTEGER): INTEGER;
	BEGIN
		CASE a OF 0: RETURN ARMv6M.R0
		| 1: RETURN ARMv6M.R1
		| 2: RETURN ARMv6M.R2
		| 3: RETURN ARMv6M.R4
		| 4: RETURN ARMv6M.R5
		| 5: RETURN ARMv6M.R7
		| 6: RETURN ARMv6M.R12
		| 7: RETURN ARMv6M.R8
		| 8: RETURN ARMv6M.R9
		| 9: RETURN ARMv6M.R10
		| 10: RETURN ARMv6M.R11
		| MT: RETURN ARMv6M.R6
		| SB: RETURN ARMv6M.R3
		| SP: RETURN ARMv6M.SP
		| LNK: RETURN ARMv6M.LR
		| 15: RETURN ARMv6M.PC
		END
	END ER;

	PROCEDURE ERs (s: SET): SET;
		VAR r: SET; i: INTEGER;
	BEGIN
		r := {}; i := 0;
		WHILE i < 10H DO
			IF i IN s THEN INCL(r, ER(i)) END;
			INC(i)
		END;
		RETURN r
	END ERs;

	(* decode register *)
	PROCEDURE DR (a: INTEGER): INTEGER;
	BEGIN
		CASE a OF ARMv6M.R0: RETURN 0
		| ARMv6M.R1: RETURN 1
		| ARMv6M.R2: RETURN 2
		| ARMv6M.R3: RETURN SB
		| ARMv6M.R4: RETURN 3
		| ARMv6M.R5: RETURN 4
		| ARMv6M.R6: RETURN MT
		| ARMv6M.R7: RETURN 5
		| ARMv6M.R8: RETURN 7
		| ARMv6M.R9: RETURN 8
		| ARMv6M.R10: RETURN 9
		| ARMv6M.R11: RETURN 10
		| ARMv6M.R12: RETURN 6
		| ARMv6M.SP: RETURN SP
		| ARMv6M.LR: RETURN LNK
		| ARMv6M.PC: RETURN 15
		END
	END DR;

	PROCEDURE UpdateFlags (a: INTEGER);
		VAR isMI: BOOLEAN; i, imm3, imm8: INTEGER;
	BEGIN
		a := ER(a);
		IF a DIV 8 = 0 THEN
			ARMv6M.EmitCMPIm(armcode, pc, a, 0)
		ELSE
			ARMv7M.EncodeMI12(0, i, imm3, imm8, isMI);
			ASSERT(isMI, 100);
			ARMv7M.EmitCMPImW(armcode, pc, a, i, imm3, imm8)
		END
	END UpdateFlags;

	(* A6.7.17 *)
	PROCEDURE IsCMPIm (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN c DIV 800H = 5
	END IsCMPIm;

	PROCEDURE RemoveRedundantCmp;
		VAR c: INTEGER;
	BEGIN
		IF (pc >= 2) & (armcode[pc - 1] DIV 10000H = 0) THEN
			IF ARMv6M.IsLThumb32(armcode[pc - 2]) THEN
				c := armcode[pc - 1] * 10000H + armcode[pc - 2];
				IF ARMv7M.IsCMPImW(c) & (c MOD 10H # 0FH) THEN
					DEC(pc, 2)
				END
			ELSIF IsCMPIm(armcode[pc - 1]) THEN
				DEC(pc)
			END
		END
	END RemoveRedundantCmp;

	(* emit RSBS a, a, #0 *)
	PROCEDURE RSBS0 (a: INTEGER);
		CONST S = 1;
		VAR i, imm3, imm8: INTEGER; isMI: BOOLEAN;
	BEGIN
		INCL(RM, a);
		a := ER(a);
		IF a DIV 8 = 0 THEN
			ARMv6M.EmitRSBS0(armcode, pc, a, a)
		ELSE
			ARMv7M.EncodeMI12(0, i, imm3, imm8, isMI); ASSERT(isMI, 100);
			ARMv7M.EmitRSBImW(armcode, pc, S, a, a, i, imm3, imm8)
		END
	END RSBS0;

	PROCEDURE Div0PosB (S: INTEGER; a, b, c: INTEGER);
	BEGIN
		ASSERT(S DIV 2 = 0, 20);
		(* A7.7.125: SDIV; encoding T1 ARMv7-M *)
			ASSERT(a IN {0..12,14}, 21);
			ASSERT(b IN {0..12,14}, 22);
			ASSERT(c IN {0..12,14}, 23);
			ARMv7M.EmitLMLMAAD(armcode, pc, 1, ER(b), 0F0H + ER(a), 0FH, ER(c));
			(* NOTE: overflow: 80000000H / 0FFFFFFFFH = 80000000H *)
		IF S = 1 THEN
			UpdateFlags(a)
		END
	END Div0PosB;

	PROCEDURE ^ Put10 (S: INTEGER; op, a, b, im: LONGINT);

	PROCEDURE ^ fix (at, with: LONGINT);

	PROCEDURE Div0NegB (S: INTEGER; a, b, c: INTEGER);
		VAR r: INTEGER;
	BEGIN
		IF a = c THEN
			r := RH;
			IF (a < MT) & (r <= a) THEN r := a + 1 END;
			IF (b < MT) & (r <= b) THEN r := b + 1 END;
			ASSERT(r < MT, 100)
		ELSE r := a
		END;
		Put10(0, Add, r, b, 1);
		Div0PosB(0, a, r, c);
		Put10(S, Sub, a, a, 1)
	END Div0NegB;

	PROCEDURE Div0 (S: INTEGER; a, b, c: INTEGER);
		VAR pc0, pc1: LONGINT;
	BEGIN
		Put10(1, Cmp, b, b, 0);
		pc0 := pc; Put3orig(BC, GE, 0);
		Div0NegB(S, a, b, c);
		pc1 := pc; Put3orig(BC, 7, 0);
		fix(pc0, pc - pc0 - 1);
		Div0PosB(S, a, b, c);
		fix(pc1, pc - pc1 - 1)
	END Div0;

	(* op # Mov: R.a := R.b op R.c; op = Mov: R.a := R.c *)
	(* S=1: change NZCV according R.a after *)
	PROCEDURE Put00 (S: INTEGER; op, a, b, c: LONGINT);
		VAR u, v: BOOLEAN;
			r: INTEGER;
	BEGIN (*emit format-0 instruction
		code[pc] := ((a*10H + b) * 10H + op) * 10000H + c; *)

		ASSERT(S IN {0,1}, 20);

		IF ORS.errcnt = 0 THEN

			u := 13 IN BITS(op);
			IF u THEN DEC(op, U) END;
			v := 12 IN BITS(op);
			IF v THEN DEC(op, V) END;

			ASSERT(op DIV 10H = 0, 21);
			ASSERT(a DIV 10H = 0, 22);
			ASSERT(b DIV 10H = 0, 23);
			ASSERT(c DIV 10H = 0, 24);

			INCL(RM, a);

			IF ~((op IN {Add,Sub}) & u) THEN RemoveRedundantCmp END;

			CASE op MOD 10H OF Mov: (* R.a := R.c *)
				ASSERT(~v, 100);
				IF ~u THEN
					IF (ER(a) DIV 8 = 0) & ((ER(c) DIV 8 = 0) OR ((c = SP) & (S = 0))) THEN
						IF c = SP THEN
							ARMv6M.EmitADDSPIm(armcode, pc, ER(a), 0)
						ELSE
							ARMv6M.EmitMOVSR(armcode, pc, ER(a), ER(c))
						END
					ELSIF c = SP THEN
						(* A7.7.5: ADD (SP plus immediate); encoding T3 ARMv7-M *)
							ASSERT(a # 15, 103);
							ARMv7M.EmitDPMI(armcode, pc, 0, 16 + S, ER(c), 0, ER(a), 0)
							(* S = 1: N, Z, C, V will be updated *) (* NOTE: C *)
					ELSE
						(* A7.7.76: MOV (register); encoding T3 ARMv7-M *)
							ASSERT(~((S = 1) & ((a IN {13,15}) OR (c IN {13,15}))), 101);
							ASSERT(~((S = 0) & ((a = 15) OR (c = 15) OR (a = 13) & (c = 13))), 102);
							ARMv7M.EmitDPSR(armcode, pc, 2, S, 0FH, 0, ER(a), ER(c))
							(* S = 1: N, Z will be updated *)
					END
				ELSE
					ASSERT(b = 0, 101);
					ASSERT(c IN {0,1}, 102);
					IF c = 0 THEN
						HALT(103)
					ELSE (* c = 1 *)
						HALT(126) (* TODO *)
					END
				END
			| Lsl: (* R.a := R.b <- R.c *)
				ASSERT(~u, 104);
				ASSERT(~v, 105);
				IF (ER(a) DIV 8 = 0) & (a = b) & (ER(c) DIV 8 = 0) THEN
					ARMv6M.EmitLSLSR(armcode, pc, ER(a), ER(c))
				ELSE
					(* A7.7.68: LSL (register); encoding T2 ARMv7-M *)
						ASSERT(~(a IN {13,15}), 106);
						ASSERT(~(b IN {13,15}), 107);
						ASSERT(~(c IN {13,15}), 108);
						ARMv7M.EmitDPR(armcode, pc, 0 + S, ER(b), ER(a), 0, ER(c))
						(* S=1: N, Z, C will be updated *)
				END
			| Asr: (* R.a := R.b -> R.c *)
				ASSERT(~u, 109);
				ASSERT(~v, 110);
				IF (ER(a) DIV 8 = 0) & (a = b) & (ER(c) DIV 8 = 0) THEN
					ARMv6M.EmitASRSR(armcode, pc, ER(a), ER(c))
				ELSE
					(* A7.7.11: ASR (register); encoding T2 ARMv7-M *)
						ASSERT(~(a IN {13,15}), 111);
						ASSERT(~(b IN {13,15}), 112);
						ASSERT(~(c IN {13,15}), 113);
						ARMv7M.EmitDPR(armcode, pc, 4 + S, ER(b), ER(a), 0, ER(c))
						(* S=1: N, Z, C will be updated *)
				END
			| Ror: (* R.a := R.b rot R.c *)
				ASSERT(~u, 114);
				ASSERT(~v, 115);
				IF (ER(a) DIV 8 = 0) & (a = b) & (ER(c) DIV 8 = 0) THEN
					ARMv6M.EmitRORSR(armcode, pc, ER(a), ER(c))
				ELSE
					(* A7.7.115: ROR (register); encoding T2 ARMv7-M *)
						ASSERT(~(a IN {13,15}), 116);
						ASSERT(~(b IN {13,15}), 117);
						ASSERT(~(c IN {13,15}), 118);
						ARMv7M.EmitDPR(armcode, pc, 6 + S, ER(b), ER(a), 0, ER(c))
						(* S=1: N, Z, C will be updated *)
				END
			| And: (* R.a := R.b & R.c *)
				ASSERT(~u, 119);
				ASSERT(~v, 120);
				IF (ER(a) DIV 8 = 0) & (a = b) & (ER(c) DIV 8 = 0) THEN
					ARMv6M.EmitANDSR(armcode, pc, ER(a), ER(c))
				ELSIF (ER(a) DIV 8 = 0) & (a = c) & (ER(b) DIV 8 = 0) THEN
					ARMv6M.EmitANDSR(armcode, pc, ER(a), ER(b))
				ELSIF b = c THEN HALT(1) (* R.a := R.b *)
				ELSE
					(* A7.7.9: AND (register); encoding T2 ARMv7-M *)
						ASSERT(~(a IN {13,15}), 121);
						ASSERT(~(b IN {13,15}), 122);
						ASSERT(~(c IN {13,15}), 123);
						ARMv7M.EmitDPSR(armcode, pc, 0, S, ER(b), 0, ER(a), ER(c)) (* shift = 0 *)
						(* S=1: N, Z, C will be updated *)
				END
			| Ann: (* R.a := R.b & ~R.c *)
				ASSERT(~u, 124);
				ASSERT(~v, 125);
				ASSERT(b # c, 100); (* in this case, emit R.a := 0 *)
				IF (ER(a) DIV 8 = 0) & (a = b) & (ER(c) DIV 8 = 0) THEN (* R.a := R.a & ~R.c *)
					ARMv6M.EmitBICSR(armcode, pc, ER(a), ER(c))
				ELSE
					(* A7.7.16: BIC (register); encoding T2 ARMv7-M *)
						ASSERT(~(a IN {13,15}), 106);
						ASSERT(~(b IN {13,15}), 107);
						ASSERT(~(c IN {13,15}), 108);
						ARMv7M.EmitDPSR(armcode, pc, 1, S, ER(b), 0, ER(a), ER(c)) (* shift = 0 *)
						(* S=1: N, Z, C will be updated *)
				END
			| Ior: (* R.a := R.b or R.c *)
				ASSERT(~u, 104);
				ASSERT(~v, 105);
				IF (ER(a) DIV 8 = 0) & (a = b) & (ER(c) DIV 8 = 0) THEN
					ARMv6M.EmitORRSR(armcode, pc, ER(a), ER(c))
				ELSIF (ER(a) DIV 8 = 0) & (a = c) & (ER(b) DIV 8 = 0) THEN
					ARMv6M.EmitORRSR(armcode, pc, ER(a), ER(b))
				ELSIF b = c THEN HALT(1) (* R.a := R.b *)
				ELSE
					(* A7.7.91: ORR (register); encoding T2 ARMv7-M *)
						ASSERT(~(a IN {13,15}), 111);
						ASSERT(~(b IN {13,15}), 112);
						ASSERT(~(c IN {13,15}), 113);
						ARMv7M.EmitDPSR(armcode, pc, 2, S, ER(b), 0, ER(a), ER(c)) (* shift = 0 *)
						(* S=1: N, Z, C will be updated *)
				END
			| Xor: (* R.a := R.b xor R.c *)
				ASSERT(~u, 109);
				ASSERT(~v, 110);
				IF (ER(a) DIV 8 = 0) & (a = b) & (ER(c) DIV 8 = 0) THEN
					ARMv6M.EmitEORSR(armcode, pc, ER(a), ER(c))
				ELSIF (ER(a) DIV 8 = 0) & (a = c) & (ER(b) DIV 8 = 0) THEN
					ARMv6M.EmitEORSR(armcode, pc, ER(a), ER(b))
				ELSIF b = c THEN HALT(1)
				ELSE
					(* A7.7.35: EOR (register); encoding T2 ARMv7-M *)
						ASSERT(~(a IN {13,15}), 116);
						ASSERT(~(b IN {13,15}), 117);
						ASSERT(~(c IN {13,15}), 118);
						ARMv7M.EmitDPSR(armcode, pc, 4, S, ER(b), 0, ER(a), ER(c)) (* shift = 0 *)
						(* S=1: N, Z, C will be updated *)
				END
			| Add: (* R.a := R.b + R.c *)
				ASSERT(~v, 114);
				ASSERT(a # 15, 120);
				ASSERT(~(c IN {13,15}), 121);
				IF ~u THEN
					IF (ER(a) IN {0..7}) & (ER(b) IN {0..7}) & (ER(c) IN {0..7}) THEN
						ARMv6M.EmitADDSR(armcode, pc, ER(a), ER(b), ER(c))
					ELSIF (b = SP) & (S = 0) THEN
						ARMv6M.EmitADDSPR(armcode, pc, ER(a), ER(c))
					ELSIF ((a = b) OR (a = c)) & (S = 0) THEN
						IF a = b THEN
							ARMv6M.EmitADDR(armcode, pc, ER(a), ER(c))
						ELSE (* a = c *)
							ARMv6M.EmitADDR(armcode, pc, ER(a), ER(b))
						END
					ELSE
						ASSERT(b # 15, 122);
						ASSERT((b = 13) OR (a # 13), 123);
						(* A7.7.4: ADD (register); encoding T3 ARMv7-M *)
						(* A7.7.6: ADD (SP plus register); encoding T3 ARMv7-M *)
							ARMv7M.EmitDPSR(armcode, pc, 8, S, ER(b), 0, ER(a), ER(c)) (* shift = 0 *)
							(* S=1: N, Z, C, V will be updated *)
					END
				ELSE (* with carry *)
					IF (ER(a) DIV 8 = 0) & (a = b) & (ER(c) DIV 8 = 0) THEN
						ARMv6M.EmitADCSR(armcode, pc, ER(a), ER(c))
					ELSIF (ER(a) DIV 8 = 0) & (a = c) & (ER(b) DIV 8 = 0) THEN
						ARMv6M.EmitADCSR(armcode, pc, ER(a), ER(b))
					ELSE
						ASSERT(~(b IN {13,15}), 124);
						(* A7.7.2: ADC(register); encoding T2 ARMv7-M *)
							ARMv7M.EmitDPSR(armcode, pc, 10, S, ER(b), 0, ER(a), ER(c))
							(* S=1: N, Z, C, V will be updated *)
					END
				END
			| Sub: (* R.a := R.b - R.c *)
				ASSERT(~v, 119);
				ASSERT(a # 15, 100);
				ASSERT(~(c IN {13,15}), 101);
				IF ~u THEN
					IF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) & (ER(c) DIV 8 = 0) THEN
						ARMv6M.EmitSUBSR(armcode, pc, ER(a), ER(b), ER(c))
					ELSE
						ASSERT(b # 15, 122);
						ASSERT((b = 13) OR (a # 13), 123);
						(* A7.7.172: SUB (register); encoding T2 ARMv7-M *)
						(* A7.7.174: SUB (SP minus register); encoding T1 *)
							ARMv7M.EmitDPSR(armcode, pc, 13, S, ER(b), 0, ER(a), ER(c))
							(* S=1: N, Z, C, V will be updated *)
					END
				ELSE (* with carry *)
					IF (ER(a) DIV 8 = 0) & (a = b) & (ER(c) DIV 8 = 0) THEN
						ARMv6M.EmitSBCSR(armcode, pc, ER(a), ER(c))
					ELSE
						ASSERT(~(b IN {13,15}), 123);
						(* A7.7.123: SBC (register); encoding T2 ARMv7-M *)
							ARMv7M.EmitDPSR(armcode, pc, 11, S, ER(b), 0, ER(a), ER(c))
							(* S=1: N, Z, C, V will be updated *)
					END
				END
			| Mul: (* R.a := R.b * R.c *)
				ASSERT(~v, 124);
				IF ~u THEN
					IF (a # b) & (a = c) THEN r := b; b := c; c := r END;
					IF (a = b) & (ER(a) DIV 8 = 0) & (ER(c) DIV 8 = 0) THEN
						(* NOTE:
							low word of result does not depend on sign of operands *)
						ARMv6M.EmitMULSR(armcode, pc, ER(a), ER(c))
					ELSE
						(* NOTE:
							low word of result does not depend on sign of operands *)
						ARMv7M.EmitMUL(armcode, pc, ER(a), ER(b), ER(c));
						IF S = 1 THEN
							UpdateFlags(a)
						END
					END
				ELSE
					HALT(126)
				END
			| Div: (* R.a := R.b div R.c *)
				ASSERT(~u, 103);
				ASSERT(~v, 104);
				Div0(S, a, b, c)
			END

		END
	END Put00;

	PROCEDURE Put0 (op, a, b, c: INTEGER);
	BEGIN
		Put00(1, op, a, b, c)
	END Put0;

	(* R.a := im *)
	(* NOTE: ARMv7MLinker.MovIm0 *)
	PROCEDURE MovIm (S: INTEGER; a: INTEGER; im: INTEGER);
		VAR shift: INTEGER;
			isLR: BOOLEAN;
			imInv: INTEGER; isMI: BOOLEAN; i, imm3, imm8, imm4: INTEGER;
	BEGIN
		ASSERT(S IN {0,1}, 20);
		ASSERT(a IN {0..14}, 21);

		INCL(RM, a);

		IF a # SP THEN
			isLR := ER(a) DIV 8 = 0;
			IF isLR & (im DIV 100H = 0) THEN
				ARMv6M.EmitMOVSIm(armcode, pc, ER(a), im)
			ELSE
				ARMv7M.EncodeMI12(im, i, imm3, imm8, isMI);
				IF isMI THEN
					(* A7.7.75: MOV (immediate); encoding T2 ARMv7-M *)
						ARMv7M.EmitDPMI(armcode, pc, i, 4 + S, 0FH, imm3, ER(a), imm8)
					(* S=1: N, Z, C will be updated *) (* NOTE: C *)
				ELSE
					imInv := ORDSET(BITS(im) / {0..31});
					ARMv7M.EncodeMI12(imInv, i, imm3, imm8, isMI);
					IF isMI THEN
						(* A7.7.84: MVN (immediate); encoding T1 ARMv7-M *)
							ARMv7M.EmitDPMI(armcode, pc, i, 6 + S, 0FH, imm3, ER(a), imm8)
							(* S=1: N, Z, C will be updated *) (* NOTE: C *)
					ELSIF isLR & (im > 255) & (im <= 255 + 255) THEN
						ARMv6M.EmitMOVSIm(armcode, pc, ER(a), 255);
						ARMv6M.EmitADDSIm(armcode, pc, ER(a), ER(a), im - 255)
					ELSE
						shift := 8;
						WHILE (shift < 32) & (SYSTEM.ROT(im DIV 100H * 100H, -shift) DIV 100H # 0) DO INC(shift) END;
						IF isLR & (shift < 32) THEN
							ASSERT(im =
								SYSTEM.LSH(SYSTEM.ROT(im DIV 100H * 100H, -shift), shift)
								+ im MOD 100H);
							ARMv6M.EmitMOVSIm(armcode, pc, ER(a), SYSTEM.ROT(im DIV 100H * 100H, -shift));
							ARMv6M.EmitLSLSIm(armcode, pc, ER(a), ER(a), shift);
							ARMv6M.EmitADDSIm(armcode, pc, ER(a), ER(a), im MOD 100H)
						ELSE
							(* TODO: 3 ops: mov; (add, lsl), (lsl, sub), (lsl, sub) | MI12; add, lsl, sub *)
							IF isLR & (im MOD 10000H DIV 100H = 0) THEN
								ARMv6M.EmitMOVSIm(armcode, pc, ER(a), im MOD 10000H)
							ELSE
								(* A7.7.75: MOV (immediate); encoding T3 ARMv7-M *)
									imm4 := im DIV 1000H MOD 10H;
									i := im DIV 800H MOD 2;
									imm3 := im DIV 100H MOD 8;
									imm8 := im MOD 100H;
									ARMv7M.EmitDPPBI(armcode, pc, i, 4, imm4, imm3 * 1000H + ER(a) * 100H + imm8)
							END;
							im := im DIV 10000H;
							IF im # 0 THEN
								(* A7.7.78: MOVT; encoding T1 ARMv7 *)
									imm4 := im DIV 1000H MOD 10H;
									i := im DIV 800H MOD 2;
									imm3 := im DIV 100H MOD 8;
									imm8 := im MOD 100H;
									ARMv7M.EmitDPPBI(armcode, pc, i, 12, imm4, imm3 * 1000H + ER(a) * 100H + imm8)
							END;
							IF S = 1 THEN
								UpdateFlags(a)
							END
						END
					END
				END
			END
		ELSE (* a = SP *)
			ASSERT(RH < MT, 100);
			ASSERT(RH # SP, 101);
			MovIm(S, RH, im);
			Put00(S, Mov, SP, 0, RH)
		END
	END MovIm;

	(* op # Mov: R.a := R.b op im; op = Mov: R.a := im *)
	(* change NZCV according R.a after *)
	PROCEDURE Put10 (S: INTEGER; op, a, b, im: LONGINT);
		VAR u, v: BOOLEAN;
			isMI: BOOLEAN; i, imm3, imm8: INTEGER;
			imm2: INTEGER;
			imInv: INTEGER;
			r: INTEGER;
	BEGIN (*emit format-1 instruction,	-10000H <= im < 10000H
		IF im < 0 THEN INC(op, V) END ;
		code[pc] := (((a+40H) * 10H + b) * 10H + op) * 10000H + (im MOD 10000H); INC(pc) *)

		ASSERT(S IN {0,1}, 20);

		IF ORS.errcnt = 0 THEN

			v := 12 IN BITS(op);
			IF v THEN DEC(op, V) END;
			ASSERT(~v, 100);

			u := 13 IN BITS(op);
			IF u THEN
				ASSERT(im DIV 10000H = 0, 21);
				DEC(op, U);
				ASSERT(op = Mov, 100);
				im := im * 10000H
			END;

			IF op MOD 10H = Ann THEN
				op := (op DIV 10H) * 10H + And;
				im := ORDSET(BITS(im) / {0..31}) (* im := ~im *)
			END;

			(* im: any const *)

			ASSERT(op DIV 10H = 0, 22);
			ASSERT(a DIV 10H = 0, 23);
			ASSERT(b DIV 10H = 0, 24);

			IF ~((op = Cmp) & (a = b) & (im = 0)) THEN (* ~Cmp *)
				INCL(RM, a)
			END;

			RemoveRedundantCmp;

			op := op MOD 10H;
			IF op IN {Lsl,Asr,Ror} THEN
				IF im = 0 THEN
					Put00(S, Mov, a, 0, b)
				ELSIF (im = 32) & (op = Ror) & (S = 1) THEN
					IF a = b THEN
						r := RH; IF (a < MT) & (r <= a) THEN r := a + 1 END;
						ASSERT(r < MT, 100);
						MovIm(0, r, im);
						Put00(S, op, a, b, r)
					ELSE
						MovIm(0, a, im);
						Put00(S, op, a, b, a)
					END
				ELSE
					ASSERT(~(a IN {13,15}), 100);
					ASSERT(~(b IN {13,15}), 101);
					ASSERT(im DIV 32 = 0, 126);
					imm3 := im DIV 4; imm2 := im MOD 4;
					CASE op OF Lsl: (* R.a := R.b <- im *)
						IF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) THEN
							ARMv6M.EmitLSLSIm(armcode, pc, ER(a), ER(b), im)
						ELSE
							(* A7.7.67: LSL (immediate); encoding T2 ARMv7-M *)
								ARMv7M.EmitDPSR(armcode, pc, 2, S, 0FH, imm3, ER(a), imm2 * 40H + ER(b))
								(* S=1: N, Z, C will be updated *)
						END
					| Asr: (* R.a := R.b -> im *)
						IF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) THEN
							ARMv6M.EmitASRSIm(armcode, pc, ER(a), ER(b), im)
						ELSE
							(* A7.7.10: ASR (immediate); encoding T2 ARMv7-M *)
								ARMv7M.EmitDPSR(armcode, pc, 2, S, 0FH, imm3, ER(a), imm2 * 40H + 20H + ER(b))
								(* S=1: N, Z, C will be updated *)
						END
					| Ror: (* R.a := R.b rot im *)
						ARMv7M.EmitRORIm(armcode, pc, S, ER(a), ER(b), im)
						(* S=1: N, Z, C will be updated *)
					END
				END
			ELSIF op = Mov THEN
				MovIm(S, a, im)
			ELSE
				ARMv7M.EncodeMI12(im, i, imm3, imm8, isMI);
				CASE op OF And: (* R.a := R.b & im *)
					IF isMI THEN
						(* A7.7.8: AND (immediate); encoding T1 ARMv7-M *)
							ASSERT(~(a IN {13,15}), 100);
							ASSERT(~(b IN {13,15}), 101);
							ARMv7M.EmitDPMI(armcode, pc, i, S, ER(b), imm3, ER(a), imm8)
							(* S=1: N, Z, C will be updated *) (* NOTE: C *)
					ELSE
						imInv := ORDSET(BITS(im) / {0..31});
						ARMv7M.EncodeMI12(imInv, i, imm3, imm8, isMI);
						IF isMI THEN
							(* A7.7.15: BIC (immediate); encoding T1 ARMv7-M *)
								ASSERT(~(a IN {13,15}), 100);
								ASSERT(~(b IN {13,15}), 102);
								ARMv7M.EmitDPMI(armcode, pc, i, 2 + S, ER(b), imm3, ER(a), imm8)
								(* S=1: N, Z, C will be updated *) (* NOTE: C *)
						ELSE
							(* TODO: MOV, ORN optimization(s) possible?... *)
							IF a = b THEN
								r := RH; IF (a < MT) & (r <= a) THEN r := a + 1 END;
								ASSERT(r < MT, 102);
								MovIm(0, r, im);
								Put00(S, op, a, b, r)
							ELSE
								MovIm(0, a, im);
								Put00(S, op, a, b, a)
							END
						END
					END
				| Ior: (* R.a := R.b or im *)
					IF isMI THEN
						(* A7.7.90: ORR (immediate); encoding T1 ARMv7-M *)
							ASSERT(~(a IN {13,15}), 100);
							ASSERT(~(b IN {13,15}), 102);
							ARMv7M.EmitDPMI(armcode, pc, i, 4 + S, ER(b), imm3, ER(a), imm8)
							(* S=1: N, Z, C will be updated *) (* NOTE: C *)
					ELSE (* try R.a := R.b or~ ~im *)
						imInv := ORDSET(BITS(im) / {0..31});
						ARMv7M.EncodeMI12(imInv, i, imm3, imm8, isMI);
						IF isMI THEN
							(* A7.7.88: ORN (immediate); encoding T1 ARMv7-M *)
								ASSERT(~(a IN {13,15}), 100);
								ASSERT(~(b IN {13,15}), 102);
								ARMv7M.EmitDPMI(armcode, pc, i, 6 + S, ER(b), imm3, ER(a), imm8)
								(* S=1: N, Z, C will be updated *) (* NOTE: C *)
						ELSE
							(* TODO: MOV, ORN optimization(s) possible?... *)
							IF a = b THEN
								r := RH; IF (a < MT) & (r <= a) THEN r := a + 1 END;
								ASSERT(r < MT, 102);
								MovIm(0, r, im);
								Put00(S, op, a, b, r)
							ELSE
								MovIm(0, a, im);
								Put00(S, op, a, b, a)
							END
						END
					END
				| Xor: (* R.a := R.b xor im *)
					IF isMI THEN
						(* A7.7.34: EOR (immediate); encoding T1 ARMv7-M *)
							ASSERT(~(a IN {13,15}), 100);
							ASSERT(~(b IN {13,15}), 103);
							ARMv7M.EmitDPMI(armcode, pc, i, 8 + S, ER(b), imm3, ER(a), imm8)
							(* S=1: N, Z, C will be updated *) (* NOTE: C *)
					ELSIF a = b THEN
						r := RH; IF (a < MT) & (r <= a) THEN r := a + 1 END;
						ASSERT(r < MT, 102);
						MovIm(0, r, im);
						Put00(S, op, a, b, r)
					ELSE
						MovIm(0, a, im);
						Put00(S, op, a, b, a)
					END
				| Add: (* R.a := R.b + im *)
					ASSERT(a # 15, 104);
					IF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) & ((im DIV 8 = 0) OR (im DIV 100H = 0) & (a = b)) THEN
						ARMv6M.EmitADDSIm(armcode, pc, ER(a), ER(b), im)
					ELSIF (b = SP) & (im MOD 4 = 0) & (S = 0) & (((a = SP) & (im DIV 200H = 0)) OR ((ER(a) DIV 8 = 0) & (im DIV 400H = 0))) THEN
						ARMv6M.EmitADDSPIm(armcode, pc, ER(a), im DIV 4)
					ELSIF isMI THEN
						ASSERT(b # 15, 105);
						ASSERT((b = 13) OR (a # 13), 106);
						(* A7.7.3: ADD (immediate); encoding T3 ARMv7-M *)
						(* A7.7.5: ADD (SP plus immediate); encoding T3 ARMv7-M *)
							ARMv7M.EmitDPMI(armcode, pc, i, 16 + S, ER(b), imm3, ER(a), imm8)
							(* S = 1: N, Z, C, V will be updated *) (* NOTE: C *)
					ELSIF im DIV 1000H = 0 THEN
						ASSERT((b = 13) OR ((b # 15) & (a # 13)), 107);
						(* A7.7.3: ADD (immediate); encoding T4 ARMv7-M *)
						(* A7.7.5: ADD (SP plus immediate); encoding T4 ARMv7-M *)
							i := im DIV 800H;
							imm3 := im DIV 100H MOD 8;
							imm8 := im MOD 100H;
							ARMv7M.EmitDPPBI(armcode, pc, i, 0, ER(b), imm3 * 1000H + ER(a) * 100H + imm8);
							IF S = 1 THEN
								UpdateFlags(a)
							END
					ELSIF a = b THEN
						r := RH; IF (a < MT) & (r <= a) THEN r := a + 1 END;
						ASSERT(r < MT, 108);
						MovIm(0, r, im);
						Put00(S, op, a, b, r)
					ELSE
						MovIm(0, a, im);
						Put00(S, op, a, b, a)
					END
				| Sub: (* R.a := R.b - im *)
					ASSERT(a # 15, 107);
					IF (a = b) & (im = 0) THEN (* Cmp *)
						ASSERT(S = 1, 100);
						UpdateFlags(a)
					ELSIF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) & ((im DIV 8 = 0) OR (im DIV 100H = 0) & (a = b)) THEN
						ARMv6M.EmitSUBSIm(armcode, pc, ER(a), ER(b), im)
					ELSIF (a = SP) & (b = SP) & (im MOD 4 = 0) & (S = 0) & (im DIV 200H = 0) THEN
						ARMv6M.EmitSUBSPIm(armcode, pc, im DIV 4)
					ELSIF isMI THEN
						ASSERT(b # 15, 108);
						ASSERT((b = 13) OR (a # 13), 109);
						(* A7.7.171: SUB (immediate); encoding T3 ARMv7-M *)
						(* A7.7.173: SUB (SP minus immediate); encoding T2 ARMv7-M *)
							ARMv7M.EmitDPMI(armcode, pc, i, 1AH + S, ER(b), imm3, ER(a), imm8)
							(* S=1: N, Z, C, V will be updated *) (* NOTE: C *)
					ELSIF (im DIV 1000H = 0) & ((S = 0) OR ~updateCarry) THEN
						ASSERT((b = 13) OR ((b # 15) & (a # 13)), 110);
						(* A7.7.171: SUB (immediate); encoding T4 ARMv7-M *)
						(* A7.7.173: SUB (SP minus immediate); encoding T3 ARMv7-M *)
							i := im DIV 800H;
							imm3 := im DIV 100H MOD 8;
							imm8 := im MOD 100H;
							ARMv7M.EmitDPPBI(armcode, pc, i, 10, ER(b), imm3 * 1000H + ER(a) * 100H + imm8);
							IF S = 1 THEN
								ASSERT(~updateCarry);
								UpdateFlags(a)
									(* NOTE: in this case C flag updated incorrectly *)
							END
					ELSIF a = b THEN
						r := RH; IF (a < MT) & (r <= a) THEN r := a + 1 END;
						ASSERT(r < MT, 111);
						MovIm(0, r, im);
						Put00(S, op, a, b, r)
					ELSE
						MovIm(0, a, im);
						Put00(S, op, a, b, a)
					END
				| Mul: (* R.a := R.b * im *)
					IF a = b THEN
						r := RH; IF (a < MT) & (r <= a) THEN r := a + 1 END;
						ASSERT(r < MT, 112);
						MovIm(0, r, im);
						Put00(S, op, a, b, r)
					ELSE
						MovIm(0, a, im);
						Put00(S, op, a, b, a)
					END
				| Div: (* R.a := R.b div im *)
					IF a = b THEN
						r := RH; IF (a < MT) & (r <= a) THEN r := a + 1 END;
						ASSERT(r < MT, 113);
						MovIm(0, r, im);
						Put00(S, op, a, b, r)
					ELSE
						MovIm(0, a, im);
						Put00(S, op, a, b, a)
					END
				END
			END

		END
	END Put10;

	PROCEDURE Put1 (op, a, b, im: INTEGER);
	BEGIN
		Put10(1, op, a, b, im)
	END Put1;

	PROCEDURE Put1a (op, a, b, im: LONGINT);
	BEGIN (*same as Put1, but with range test	-10000H <= im < 10000H
		IF (im >= -10000H) & (im <= 0FFFFH) THEN Put1(op, a, b, im)
		ELSE Put1(Mov+U, RH, 0, im DIV 10000H);
			IF im MOD 10000H # 0 THEN Put1(Ior, RH, RH, im MOD 10000H) END ;
			Put0(op, a, b, RH)
		END *)

		ASSERT(op DIV 10H = 0, 20);

		Put1(op, a, b, im)
	END Put1a;

	PROCEDURE Put20 (S: INTEGER; op, a, b, off: LONGINT);
		VAR v: BOOLEAN;
			r: INTEGER;
	BEGIN (*emit load/store instruction
		code[pc] := ((op * 10H + a) * 10H + b) * 100000H + (off MOD 100000H); INC(pc) *)

		ASSERT(S IN {0,1}, 20);

		IF ORS.errcnt = 0 THEN

			ASSERT(b DIV 10H = 0, 21);

(*
			ASSERT(off >= 0, 22);
			ASSERT(off < 100000H, 23);
*)
			ASSERT(off >= -80000H, 22);
			ASSERT(off < 80000H, 23);

			v := ODD(op); IF v THEN DEC(op) END;

			RemoveRedundantCmp;

			IF op = Ldr THEN (* R.a := Mem[R.b + off] *)
				ASSERT(a DIV 10H = 0, 24);
				(* http://www.st.com/web/en/resource/technical/document/errata_sheet/DM00037591.pdf, section 1.1 *)
					ASSERT(ER(a) # SP);
				INCL(RM, a);
				IF ~v THEN (* load word *)
					ASSERT(off MOD 4 = 0, 100);
					IF off < 0 THEN
						ARMv7M.EmitLWImWNeg(armcode, pc, ER(a), ER(b), -off)
					ELSIF (ER(a) DIV 8 = 0) & (((b = SP) & (off DIV 400H = 0)) OR ((ER(b) DIV 8 = 0) & (off DIV 4 DIV 32 = 0))) THEN
						ARMv6M.EmitLDRIm(armcode, pc, ER(a), ER(b), off DIV 4)
					ELSIF off < 1000H THEN
						ARMv7M.EmitLWImW(armcode, pc, ER(a), ER(b), off)
					ELSE
						IF a = b THEN
							r := RH;
							IF (a < MT) & (r <= a) THEN r := a + 1 END;
							ASSERT(r < MT, 101)
						ELSE
							r := a
						END;
						IF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) & (ER(r) DIV 8 = 0) THEN
							MovIm(0, r, off);
							ARMv6M.EmitLDRR(armcode, pc, ER(a), ER(b), ER(r))
						ELSIF off MOD 8 = 0 THEN
							MovIm(0, r, off DIV 8);
							ARMv7M.EmitLWRW(armcode, pc, ER(a), ER(b), ER(r), 3)
						ELSE
							MovIm(0, r, off DIV 4);
							ARMv7M.EmitLWRW(armcode, pc, ER(a), ER(b), ER(r), 2)
						END
					END
				ELSE (* load byte *)
					IF off < 0 THEN
						HALT(126)
					ELSIF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) & (off DIV 32 = 0) THEN
						ARMv6M.EmitLDRBIm(armcode, pc, ER(a), ER(b), off)
					ELSIF off < 1000H THEN
						ARMv7M.EmitLBImW(armcode, pc, ER(a), ER(b), off)
					ELSE
						IF a = b THEN
							r := RH;
							IF (a < MT) & (r <= a) THEN r := a + 1 END;
							ASSERT(r < MT, 101)
						ELSE
							r := a
						END;
						IF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) & (ER(r) DIV 8 = 0) THEN
							MovIm(0, r, off);
							ARMv6M.EmitLDRBR(armcode, pc, ER(a), ER(b), ER(r))
						ELSIF off MOD 8 = 0 THEN
							MovIm(0, r, off DIV 8);
							ARMv7M.EmitLBRW(armcode, pc, ER(a), ER(b), ER(r), 3)
						ELSIF off MOD 4 = 0 THEN
							MovIm(0, r, off DIV 4);
							ARMv7M.EmitLBRW(armcode, pc, ER(a), ER(b), ER(r), 2)
						ELSIF off MOD 2 = 0 THEN
							MovIm(0, r, off DIV 2);
							ARMv7M.EmitLBRW(armcode, pc, ER(a), ER(b), ER(r), 1)
						ELSE
							MovIm(0, r, off);
							ARMv7M.EmitLBRW(armcode, pc, ER(a), ER(b), ER(r), 0)
						END
					END
				END;
				IF S = 1 THEN UpdateFlags(a) END
			ELSIF op = Str THEN (* Mem[R.b + off] := R.a *)
				ASSERT(off >= 0, 126);
				IF ~v THEN (* store word *)
					ASSERT(off MOD 4 = 0, 102);
					IF a >= 100H THEN (* FPU register *)
						DEC(a, 100H);
						ARMv7M.EmitVSTR(armcode, pc, ER(a), ER(b), 1, off DIV 4)
					ELSIF (ER(a) DIV 8 = 0) & (((b = SP) & (off DIV 400H = 0)) OR ((ER(b) DIV 8 = 0) & (off DIV 4 DIV 32 = 0))) THEN
						ARMv6M.EmitSTRIm(armcode, pc, ER(a), ER(b), off DIV 4)
					ELSIF off < 1000H THEN
						ARMv7M.EmitSWImW(armcode, pc, ER(a), ER(b), off)
					ELSE
						r := RH;
						IF (a < MT) & (r <= a) THEN r := a + 1 END;
						IF (b < MT) & (r <= b) THEN r := b + 1 END;
						ASSERT(r < MT, 101);
						IF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) & (ER(r) DIV 8 = 0) THEN
							MovIm(0, r, off);
							ARMv6M.EmitSTRR(armcode, pc, ER(a), ER(b), ER(r))
						ELSIF off MOD 8 = 0 THEN
							MovIm(0, r, off DIV 8);
							ARMv7M.EmitSWRW(armcode, pc, ER(a), ER(b), ER(r), 3)
						ELSE
							MovIm(0, r, off DIV 4);
							ARMv7M.EmitSWRW(armcode, pc, ER(a), ER(b), ER(r), 2)
						END
					END
				ELSE (* store byte *)
					ASSERT(a DIV 10H = 0, 100);
					IF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) & (off DIV 32 = 0) THEN
						ARMv6M.EmitSTRBIm(armcode, pc, ER(a), ER(b), off)
					ELSIF off < 1000H THEN
						ARMv7M.EmitSBImW(armcode, pc, ER(a), ER(b), off)
					ELSE
						r := RH;
						IF (a < MT) & (r <= a) THEN r := a + 1 END;
						IF (b < MT) & (r <= b) THEN r := b + 1 END;
						ASSERT(r < MT, 101);
						IF (ER(a) DIV 8 = 0) & (ER(b) DIV 8 = 0) & (ER(r) DIV 8 = 0) THEN
							MovIm(0, r, off);
							ARMv6M.EmitSTRBR(armcode, pc, ER(a), ER(b), ER(r))
						ELSIF off MOD 8 = 0 THEN
							MovIm(0, r, off DIV 8);
							ARMv7M.EmitSBRW(armcode, pc, ER(a), ER(b), ER(r), 3)
						ELSIF off MOD 4 = 0 THEN
							MovIm(0, r, off DIV 4);
							ARMv7M.EmitSBRW(armcode, pc, ER(a), ER(b), ER(r), 2)
						ELSIF off MOD 2 = 0 THEN
							MovIm(0, r, off DIV 2);
							ARMv7M.EmitSBRW(armcode, pc, ER(a), ER(b), ER(r), 1)
						ELSE
							MovIm(0, r, off);
							ARMv7M.EmitSBRW(armcode, pc, ER(a), ER(b), ER(r), 0)
						END
					END
				END
			ELSE HALT(1) (* invalid operation *)
			END

		END
	END Put20;

	PROCEDURE Put2 (op, a, b, off: INTEGER);
	BEGIN
		Put20(1, op, a, b, off)
	END Put2;

	PROCEDURE CondRISCToARM (cond: INTEGER): INTEGER;
	BEGIN
		CASE cond OF MI: RETURN ARMv6M.MI
		| EQ: RETURN ARMv6M.EQ
		| 2: RETURN ARMv6M.CC
		| LT: RETURN ARMv6M.LT
		| LE: RETURN ARMv6M.LE
		| 7: RETURN ARMv6M.AL
		| PL: RETURN ARMv6M.PL
		| NE: RETURN ARMv6M.NE
		| 10: RETURN ARMv6M.CS
		| GE: RETURN ARMv6M.GE
		| GT: RETURN ARMv6M.GT
		(* | 15: RETURN 15 *)
		END
	END CondRISCToARM;

(*
	PROCEDURE CondARMToRISC (armcond: INTEGER): INTEGER;
	BEGIN
		CASE armcond OF ARMv6M.EQ: RETURN EQ
		| ARMv6M.NE: RETURN NE
		| ARMv6M.CS: RETURN 10
		| ARMv6M.CC: RETURN 2
		| ARMv6M.MI: RETURN MI
		| ARMv6M.PL: RETURN PL
		| ARMv6M.GE: RETURN GE
		| ARMv6M.LT: RETURN LT
		| ARMv6M.GT: RETURN GT
		| ARMv6M.LE: RETURN LE
		| ARMv6M.AL: RETURN 7
		(* | 15: RETURN 15 *)
		END
	END CondARMToRISC;
*)

	PROCEDURE ^ negated(cond: LONGINT): LONGINT;

	PROCEDURE Put3 (op, cond, off: LONGINT);
		VAR S, imm10, J1, J2, imm11, imm6: INTEGER;
			pc0, pc1: INTEGER;
	BEGIN (*emit branch instruction
		code[pc] := ((op+12) * 10H + cond) * 1000000H + (off MOD 1000000H); INC(pc) *)

		IF ORS.errcnt = 0 THEN

			ASSERT(op DIV 4 = 0, 20);
			ASSERT(cond DIV 10H = 0, 21);

			CASE op OF BR: (* if cond, then PC := R.c *)
				IF off IN {0..15} THEN
					ASSERT(cond = 7, 102);
					ARMv6M.EmitBX(armcode, pc, ER(off))
				ELSIF off = 10H THEN
					(* return from interrupt *)
					HALT(126)
				ELSE HALT(1)
				END
			| BLR:
				IF off MOD 10H = MT THEN (* Trap or New *)
					off := off DIV 10H MOD 10000000H;
					(* see Kernel.Trap, System.Trap *)
					IF off MOD 10H = 0 THEN (* New *)
						ASSERT(cond = 7, 100);
						(* NOTE: New() arguments in R0, R1 *)
						ARMv6M.EmitSVC(armcode, pc, off MOD 10H)
					ELSIF cond = 7 THEN
						MovIm(0, 1, off DIV 10H); (* R1 := ORS.Pos *)
						ARMv6M.EmitSVC(armcode, pc, off MOD 10H)
					ELSE
						pc0 := pc; Put3(BC, 0, 0);
						MovIm(0, 1, off DIV 10H); (* R1 := ORS.Pos *)
						ARMv6M.EmitSVC(armcode, pc, off MOD 10H);
						pc1 := pc;
						pc := pc0;
						Put3(BC, negated(cond), pc1 - pc0 - 1);
						pc := pc1
					END
				ELSE (* if cond, then LNK := PC+1; PC := R.c *)
					ASSERT(off DIV 10H = 0, 101);
					ASSERT(cond = 7, 102);
					ASSERT(off # 15, 103);
					INCL(RM, LNK);
					ARMv6M.EmitBLX(armcode, pc, ER(off))
				END
			| BC: (* if cond, then PC := PC+1+offset *)
				ASSERT(off >= -800000H, 102);
				ASSERT(off < 800000H, 103);

					DEC(off);

				IF cond = 7 THEN
					IF (off >= -1024) & (off <= 1023) THEN
						ARMv6M.EmitB(armcode, pc, off)
					ELSE
						(*
						(* A7.7.12: B; encoding T4 ARMv7-M *)
							ARMv6M.EncodeBLabel24(off, S, imm10, J1, J2, imm11);
							ARMv7M.EmitBAMC(armcode, pc, S * 40H + imm10 DIV 10H, imm10 MOD 10H, J1 * 2 + 1, J2 * 800H + imm11)
						*)
						ORS.Mark("unconditional branch is too long")
					END
				ELSIF cond = 15 THEN
					ARMv6M.EmitNOP(armcode, pc)
				ELSE
					cond := CondRISCToARM(cond);
					IF (off >= -128) & (off <= 127) THEN
						ARMv6M.EmitBC(armcode, pc, cond, off)
					ELSE
						(*
						(* A7.7.12: B; encoding T3 ARMv7-M *)
							ARMv7M.EncodeBLabel20(off, S, imm6, J1, J2, imm11);
							ARMv7M.EmitBAMC(armcode, pc, S * 40H + cond * 4 + imm6 DIV 10H, imm6 MOD 10H, J1 * 2, J2 * 800H + imm11)
						*)
						ORS.Mark("conditional branch is too long")
					END
				END

			| BL: (* if cond, then LNK := PC+1; PC := PC+1+offset *)
				ASSERT(off >= -800000H, 104);
				ASSERT(off < 800000H, 105);

				INCL(RM, LNK);

				IF cond # 7 THEN
					HALT(126)
				ELSE
						IF off # 0 THEN DEC(off) END;
					ARMv6M.EmitBL(armcode, pc, off)
				END
			END

		END
	END Put3;

	PROCEDURE incR;
	BEGIN
		EXCL(FR, RH);
		IF RH < MT-1 THEN INC(RH) ELSE ORS.Mark("register stack overflow") END
	END incR;

	PROCEDURE CheckRegs*;
	BEGIN
		IF RH # 0 THEN ORS.Mark("Reg Stack"); RH := 0 END ;
		IF pc >= maxCode - 40 THEN ORS.Mark("program too long") END;
		IF frame # 0 THEN ORS.Mark("frame error"); frame := 0 END
	END CheckRegs;

	PROCEDURE SetCC(VAR x: Item; n: LONGINT);
	BEGIN x.mode := Cond; x.a := 0; x.b := 0; x.r := n
	END SetCC;

	PROCEDURE Trap(cond, num: LONGINT);
	BEGIN Put3(BLR, cond, ORS.Pos()*100H + num*10H + MT)
	END Trap;

	(*handling of forward reference, fixups of branch addresses and constant tables*)

	PROCEDURE negated(cond: LONGINT): LONGINT;
	BEGIN
		IF cond < 8 THEN cond := cond+8 ELSE cond := cond-8 END ;
		RETURN cond
	END negated;

	PROCEDURE invalSB;
	BEGIN curSB := 1
	END invalSB;

(*
	PROCEDURE fix(at, with: LONGINT);
	BEGIN
		IF armcode[at] DIV 10000000H MOD 10H = 0EH (* BC *) THEN
			HALT(1);
			ASSERT(armcode[at+1] = 00FFFFFEH, 100);
			armcode[at] := armcode[at] DIV C24 * C24 + (with MOD C24)
		ELSE
			ASSERT(armcode[at] = 00FFFFFEH, 101);
			ASSERT(armcode[at-1] DIV 10000000H MOD 10H = 0EH, 102); (* BC *)
			armcode[at-1] := armcode[at-1] DIV C24 * C24 + (with MOD C24)
		END
	END fix;

	PROCEDURE FixLink*(L: LONGINT);
		VAR L1: LONGINT;
	BEGIN invalSB;
		WHILE L # 0 DO
			IF armcode[L] DIV 10000000H MOD 10H = 0EH (* BC *) THEN
				HALT(1);
				ASSERT(armcode[L+1] = 00FFFFFEH, 100);
				L1 := armcode[L] MOD 40000H;
				fix(L, pc-L-1)
			ELSE
				ASSERT(armcode[L] = 00FFFFFEH, 101);
				ASSERT(armcode[L-1] DIV 10000000H MOD 10H = 0EH, 102); (* BC *)
				L1 := armcode[L-1] MOD 40000H;
				fix(L, pc-L-1+1)
			END;
			L := L1
		END
	END FixLink;

	PROCEDURE FixLinkWith (L0, dst: LONGINT);
		VAR L1: LONGINT;
	BEGIN
		WHILE L0 # 0 DO
			IF armcode[L0] DIV 10000000H MOD 10H = 0EH THEN (* BC *)
				ASSERT(armcode[L0+1] = 00FFFFFEH, 101);
				L1 := armcode[L0] MOD C24;
				armcode[L0] := armcode[L0] DIV C24 * C24 + ((dst - L0 - 1) MOD C24)
			ELSE
				ASSERT(armcode[L0] = 00FFFFFEH, 101);
				ASSERT(armcode[L0-1] DIV 10000000H MOD 10H = 0EH, 102); (* BC *)
				L1 := armcode[L0-1] MOD C24;
				armcode[L0-1] := armcode[L0-1] DIV C24 * C24 + ((dst - L0 - 1 + 1) MOD C24)
			END;
			L0 := L1
		END
	END FixLinkWith;

	PROCEDURE merged (L0, L1: LONGINT): LONGINT;
		VAR L2, L3: LONGINT;
	BEGIN
		IF L0 # 0 THEN L3 := L0;
			HALT(126);
			REPEAT L2 := L3;
			ASSERT(armcode[L2] DIV 10000000H MOD 10H = 0EH, 100); (* BC *)
			ASSERT(armcode[L2+1] = 00FFFFFEH, 101);
			L3 := armcode[L2] MOD 40000H UNTIL L3 = 0;
			ASSERT(armcode[L2] DIV 10000000H MOD 10H = 0EH, 102); (* BC *)
			ASSERT(armcode[L2+1] = 00FFFFFEH, 103);
			armcode[L2] := armcode[L2] + L1; L1 := L0
		END;
		RETURN L1
	END merged;
*)

	PROCEDURE fix (at, with: LONGINT);
	BEGIN
		IF ORS.errcnt = 0 THEN
			ASSERT(armcode[at] DIV 10000000H MOD 10H = 0EH, 100) (* BC *)
		END;
		armcode[at] := armcode[at] DIV C24 * C24 + (with MOD C24)
	END fix;

	PROCEDURE FixOne*(at: LONGINT);
	BEGIN fix(at, pc-at-1)
	END FixOne;

	PROCEDURE FixLink*(L: LONGINT);
		VAR L1: LONGINT;
	BEGIN invalSB;
		WHILE L # 0 DO L1 := armcode[L] MOD 40000H; fix(L, pc-L-1); L := L1 END
	END FixLink;

	PROCEDURE FixLinkWith (L0, dst: LONGINT);
		VAR L1: LONGINT;
	BEGIN
		WHILE L0 # 0 DO
			L1 := armcode[L0] MOD C24;
			armcode[L0] := armcode[L0] DIV C24 * C24 + ((dst - L0 - 1) MOD C24); L0 := L1
		END
	END FixLinkWith;

	PROCEDURE merged (L0, L1: LONGINT): LONGINT;
		VAR L2, L3: LONGINT;
	BEGIN
		IF L0 # 0 THEN L3 := L0;
			REPEAT L2 := L3; L3 := armcode[L2] MOD 40000H UNTIL L3 = 0;
			armcode[L2] := armcode[L2] + L1; L1 := L0
		END;
		RETURN L1
	END merged;

	(* loading of operands and addresses into registers *)

	PROCEDURE GetSB (base: LONGINT);
	BEGIN
		IF (version # 0) & ((base # curSB) OR (base # 0)) THEN
			(* will be fixed up by linker/loader *)
				INCL(RM, SB);
				Put2orig(Ldr, ER(SB), -base, pc-fixorgD); fixorgD := pc-1; curSB := base;
				armcode[pc] := 00FFFFFDH; INC(pc)
		END
	END GetSB;

	PROCEDURE NilCheck;
	BEGIN IF check THEN Trap(EQ, 4) END
	END NilCheck;

	PROCEDURE load0 (S: INTEGER; VAR x: Item);
		VAR op, pc0, pc1: LONGINT;
	BEGIN
		ASSERT(S IN {0,1}, 20);
		IF x.type.size = 1 THEN op := Ldr+1 ELSE op := Ldr END ;
		IF x.mode # Reg THEN
			IF x.mode = ORB.Const THEN
				IF x.type.form = ORB.Proc THEN
					IF x.r > 0 THEN ORS.Mark("not allowed")
					ELSIF x.r = 0 THEN Put3(BL, 7, 0);
						ASSERT(x.a MOD 2 = 0, 100);
						Put10(S, Sub, RH, LNK, (pc*4 - x.a) DIV 2)
					ELSE GetSB(x.r);
						INCL(RM, RH);
						Put1orig(Add, ER(RH), ER(SB), x.a + 100H); (*mark as progbase-relative*)
						armcode[pc] := 00FFFFFFH; INC(pc)
					END
				(*
				ELSIF (x.a <= 0FFFFH) & (x.a >= -10000H) THEN Put1(Mov, RH, 0, x.a)
				ELSE Put1(Mov+U, RH, 0, x.a DIV 10000H MOD 10000H);
					IF x.a MOD 10000H # 0 THEN Put1(Ior, RH, RH, x.a MOD 10000H) END
				*)
				ELSE Put10(S, Mov, RH, 0, x.a)
				END;
				x.r := RH; incR
			ELSIF x.mode = ORB.Var THEN
				IF x.r > 0 THEN (*local*) Put20(S, op, RH, SP, x.a + frame)
				ELSE GetSB(x.r);
					IF x.r # 0 THEN
						INCL(RM, RH);
						Put2orig(op, ER(RH), ER(SB), x.a);
						armcode[pc] := 00FFFFFFH; INC(pc);
						IF S = 1 THEN UpdateFlags(RH) END
					ELSE Put20(S, op, RH, SB, x.a)
					END
				END;
				x.r := RH; incR
			ELSIF x.mode = ORB.Par THEN Put20(0, Ldr, RH, SP, x.a + frame); Put20(S, op, RH, RH, x.b); x.r := RH; incR
			ELSIF x.mode = RegI THEN Put20(S, op, x.r, x.r, x.a)
			ELSIF x.mode = Cond THEN
				pc0 := pc; Put3orig(BC, negated(x.r), 0);
				FixLink(x.b); Put10(S, Mov, RH, 0, 1);
				pc1 := pc; Put3orig(BC, 7, 0);
				fix(pc0, pc - pc0 - 1);
				FixLink(x.a); Put10(S, Mov, RH, 0, 0);
				fix(pc1, pc - pc1 - 1);
				x.r := RH; incR
			END;
			x.mode := Reg
		END
	END load0;

	PROCEDURE load (VAR x: Item);
	BEGIN
		load0(1, x)
	END load;

	PROCEDURE loadReal (VAR x: Item);
		VAR im: INTEGER;
	BEGIN
		RemoveRedundantCmp;
		IF x.mode = ORB.Var THEN
			IF x.r > 0 (* local *) THEN
				im := x.a + frame; ASSERT(im MOD 4 = 0, 100);
				ARMv7M.EmitVLDR(armcode, pc, ER(RH), ER(SP), 1, im DIV 4)
			ELSE GetSB(x.r);
				IF x.r # 0 THEN
					INCL(RM, RH);
					ASSERT(x.type.size = 4, 101);
					Put2orig(Ldr, ER(RH), ER(SB), x.a);
					armcode[pc] := 00FFFFFCH (* VLDR *); INC(pc)
				ELSE
					ASSERT(x.a MOD 4 = 0, 102);
					ARMv7M.EmitVLDR(armcode, pc, ER(RH), ER(SB), 1, x.a DIV 4)
				END
			END;
			x.r := RH + 100H; incR; INCL(FR, x.r - 100H); x.mode := Reg
		ELSIF x.mode = ORB.Par THEN
			Put20(0, Ldr, RH, SP, x.a + frame);
			ASSERT(x.b MOD 4 = 0, 103);
			ARMv7M.EmitVLDR(armcode, pc, ER(RH), ER(RH), 1, x.b DIV 4);
			x.r := RH + 100H; incR; INCL(FR, x.r - 100H); x.mode := Reg
		ELSE
			load0(0, x)
		END;
		IF (x.mode = Reg) & (x.r < 100H) THEN
			ARMv7M.EmitVMOVSPR(armcode, pc, 0, ER(x.r), ER(x.r));
			INCL(FR, x.r); x.r := x.r + 100H
		END
	END loadReal;

	PROCEDURE loadAdr0 (S: INTEGER; VAR x: Item);
	BEGIN
		IF x.mode = ORB.Var THEN
			IF x.r > 0 THEN (*local*) Put10(S, Add, RH, SP, x.a + frame)
			ELSE GetSB(x.r);
				IF x.r # 0 THEN
					INCL(RM, RH);
					Put1orig(Add, ER(RH), ER(SB), x.a);
					armcode[pc] := 00FFFFFFH; INC(pc)
				ELSE Put10(S, Add, RH, SB, x.a)
				END
			END;
			x.r := RH; incR
		ELSIF x.mode = ORB.Par THEN
			IF x.b # 0 THEN Put20(0, Ldr, RH, SP, x.a + frame);
				Put10(S, Add, RH, RH, x.b)
			ELSE Put20(S, Ldr, RH, SP, x.a + frame)
			END;
			x.r := RH; incR
		ELSIF x.mode = RegI THEN
			IF x.a # 0 THEN Put10(S, Add, x.r, x.r, x.a) END
		ELSE ORS.Mark("address error")
		END;
		x.mode := Reg
	END loadAdr0;

	PROCEDURE loadAdr (VAR x: Item);
	BEGIN
		loadAdr0(1, x)
	END loadAdr;

	PROCEDURE IsFlagsUp0 (r: INTEGER): BOOLEAN;
		VAR res: BOOLEAN; c: INTEGER;
	BEGIN
		r := ER(r); ASSERT(r # 15, 100);
		IF r DIV 8 = 0 THEN
			res := ~ARMv6M.IsLThumb32(armcode[pc - 2]) & IsCMPIm(armcode[pc - 1]);
			ASSERT(~res OR (armcode[pc - 1] DIV 100H MOD 8 = r), 101)
		ELSIF ARMv6M.IsLThumb32(armcode[pc - 2]) THEN
			ASSERT(armcode[pc - 1] DIV 10000H = 0, 102);
			c := 10000H * armcode[pc - 1] + armcode[pc - 2];
			res := ARMv7M.IsCMPImW(c);
			ASSERT(~res OR (c MOD 10H = r), 103)
		ELSE
			res := FALSE
		END;
		RETURN res
	END IsFlagsUp0;

	PROCEDURE loadCond (VAR x: Item);
	BEGIN
		IF x.type.form = ORB.Bool THEN
			IF x.mode = ORB.Const THEN x.r := 15 - x.a*8
			ELSE load(x);
				IF ~IsFlagsUp0(x.r) THEN
					Put1(Cmp, x.r, x.r, 0)
				(* ELSE HALT(1) *)
				END;
				x.r := NE; DEC(RH)
			END ;
			x.mode := Cond; x.a := 0; x.b := 0
		ELSE ORS.Mark("not Boolean?")
		END
	END loadCond;

	PROCEDURE loadTypTagAdr0 (S: INTEGER; T: ORB.Type);
		VAR x: Item;
	BEGIN x.mode := ORB.Var; x.a := T.len; x.r := -T.mno; loadAdr0(S, x)
	END loadTypTagAdr0;

	PROCEDURE loadTypTagAdr (T: ORB.Type);
	BEGIN
		loadTypTagAdr0(1, T)
	END loadTypTagAdr;

	PROCEDURE loadStringAdr0 (S: INTEGER; VAR x: Item);
	BEGIN GetSB(0); Put10(S, Add, RH, SB, varsize+x.a); x.mode := Reg; x.r := RH; incR
	END loadStringAdr0;

	PROCEDURE loadStringAdr (VAR x: Item);
	BEGIN
		loadStringAdr0(1, x)
	END loadStringAdr;

	(* Items: Conversion from constants or from Objects on the Heap to Items on the Stack*)

	PROCEDURE MakeConstItem*(VAR x: Item; typ: ORB.Type; val: LONGINT);
	BEGIN x.mode := ORB.Const; x.type := typ; x.a := val
	END MakeConstItem;

	PROCEDURE MakeRealItem*(VAR x: Item; val: REAL);
	BEGIN x.mode := ORB.Const; x.type := ORB.realType; x.a := SYSTEM.VAL(LONGINT, val)
	END MakeRealItem;

	PROCEDURE MakeStringItem*(VAR x: Item; len: LONGINT); (*copies string from ORS-buffer to ORG-string array*)
		VAR i: LONGINT;
	BEGIN x.mode := ORB.Const; x.type := ORB.strType; x.a := strx; x.b := len; i := 0;
		IF strx + len + 4 < maxStrx THEN
			WHILE len > 0 DO str[strx] := ORS.str[i]; INC(strx); INC(i); DEC(len) END ;
			WHILE strx MOD 4 # 0 DO str[strx] := 0X; INC(strx) END
		ELSE ORS.Mark("too many strings")
		END
	END MakeStringItem;

	PROCEDURE MakeItem*(VAR x: Item; y: ORB.Object; curlev: LONGINT);
	BEGIN x.mode := y.class; x.type := y.type; x.a := y.val; x.rdo := y.rdo;
		IF y.class = ORB.Par THEN x.b := 0
		(* ELSIF y.class = ORB.Typ THEN x.a := y.type.len; x.r := -y.lev *)
		ELSIF (y.class = ORB.Const) & (y.type.form = ORB.String) THEN x.b := y.lev	(*len*)
		ELSE x.r := y.lev
		END ;
		IF (y.lev > 0) & (y.lev # curlev) & (y.class # ORB.Const) THEN ORS.Mark("not accessible") END
	END MakeItem;

	(* Code generation for Selectors, Variables, Constants *)

	PROCEDURE Field*(VAR x: Item; y: ORB.Object);	 (* x := x.y *)
	BEGIN;
		IF x.mode = ORB.Var THEN
			IF x.r >= 0 THEN x.a := x.a + y.val
			ELSE loadAdr(x); x.mode := RegI; x.a := y.val
			END
		ELSIF x.mode = RegI THEN x.a := x.a + y.val
		ELSIF x.mode = ORB.Par THEN x.b := x.b + y.val
		END
	END Field;

	PROCEDURE Index*(VAR x, y: Item);	 (* x := x[y] *)
		VAR s, lim: LONGINT;
	BEGIN s := x.type.base.size; lim := x.type.len;
		IF (y.mode = ORB.Const) & (lim >= 0) THEN
			IF (y.a < 0) OR (y.a >= lim) THEN ORS.Mark("bad index") END ;
			IF x.mode IN {ORB.Var, RegI} THEN
				(*
				x.a := y.a * s + x.a
				*)
					IF x.mode = ORB.Var THEN
						IF x.r >= 0 THEN x.a := y.a * s + x.a
						ELSE loadAdr(x); x.mode := RegI; x.a := y.a * s
						END
					ELSE (* x.mode = RegI *) x.a := y.a * s + x.a
					END
			ELSIF x.mode = ORB.Par THEN x.b := y.a * s + x.b
			END
		ELSE load0(0, y);
			IF check THEN	(*check array bounds*)
				updateCarry := TRUE;
				IF lim >= 0 THEN Put1a(Cmp, RH, y.r, lim)
				ELSE (*open array*)
					IF x.mode IN {ORB.Var, ORB.Par} THEN Put20(0, Ldr, RH, SP, x.a+4+frame); Put0(Cmp, RH, y.r, RH)
					ELSE ORS.Mark("error in Index")
					END
				END;
				updateCarry := FALSE;
				Trap(10, 1)	(*BCC*)
			END ;
			IF s = 4 THEN Put10(0, Lsl, y.r, y.r, 2) ELSIF s > 1 THEN Put10(0, Mul, y.r, y.r, s) END ;
			IF x.mode = ORB.Var THEN
				IF x.r > 0 THEN Put0(Add, y.r, SP, y.r); INC(x.a, frame)
				ELSE GetSB(x.r);
					IF x.r = 0 THEN Put0(Add, y.r, SB, y.r)
					ELSE
						INCL(RM, RH); Put1orig(Add, ER(RH), ER(SB), x.a);
						armcode[pc] := 00FFFFFFH; INC(pc);
						Put0(Add, y.r, RH, y.r); x.a := 0
					END
				END;
				x.r := y.r; x.mode := RegI
			ELSIF x.mode = ORB.Par THEN
				Put20(0, Ldr, RH, SP, x.a + frame);
				Put0(Add, y.r, RH, y.r); x.mode := RegI; x.r := y.r; x.a := x.b
			ELSIF x.mode = RegI THEN Put0(Add, x.r, x.r, y.r); DEC(RH)
			ELSE HALT(100)
				(* if reached, then restore back:
					load0(0,y) -> load(y)
					IF s = 4...: Put10(0 -> Put1( ; Put10(0->Put1a
				*)
			END
		END
	END Index;

	PROCEDURE DeRef*(VAR x: Item);
	BEGIN
		IF x.mode = ORB.Var THEN
			IF x.r > 0 THEN (*local*) Put2(Ldr, RH, SP, x.a + frame) ELSE GetSB(x.r);
				IF x.r # 0 THEN
					INCL(RM, RH);
					Put2orig(Ldr, ER(RH), ER(SB), x.a);
					armcode[pc] := 00FFFFFFH; INC(pc);
					UpdateFlags(RH)
				ELSE Put2(Ldr, RH, SB, x.a)
				END
			END;
			NilCheck; x.r := RH; incR
		ELSIF x.mode = ORB.Par THEN
			Put20(0, Ldr, RH, SP, x.a + frame); Put2(Ldr, RH, RH, x.b); NilCheck; x.r := RH; incR
		ELSIF x.mode = RegI THEN Put2(Ldr, x.r, x.r, x.a); NilCheck
		ELSIF x.mode # Reg THEN ORS.Mark("bad mode in DeRef")
		END ;
		x.mode := RegI; x.a := 0; x.b := 0
	END DeRef;

	PROCEDURE Q(T: ORB.Type; VAR dcw: LONGINT);
	BEGIN (*one entry of type descriptor extension table*)
		IF T.base # NIL THEN
			Q(T.base, dcw); data[dcw] := (T.mno*1000H + T.len) * 1000H + dcw - fixorgT;
			fixorgT := dcw; INC(dcw)
		END
	END Q;

	PROCEDURE FindPtrFlds(typ: ORB.Type; off: LONGINT; VAR dcw: LONGINT);
		VAR fld: ORB.Object; i, s: LONGINT;
	BEGIN
		IF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp) THEN data[dcw] := off; INC(dcw)
		ELSIF typ.form = ORB.Record THEN
			fld := typ.dsc;
			WHILE fld # NIL DO FindPtrFlds(fld.type, fld.val + off, dcw); fld := fld.next END
		ELSIF typ.form = ORB.Array THEN
			s := typ.base.size;
			FOR i := 0 TO typ.len-1 DO FindPtrFlds(typ.base, i*s + off, dcw) END
		END
	END FindPtrFlds;

	PROCEDURE BuildTD*(T: ORB.Type; VAR dc: LONGINT);
		VAR dcw, k, s: LONGINT;	(*dcw = word address*)
	BEGIN dcw := dc DIV 4; s := T.size; (*convert size for heap allocation*)
		IF s <= 24 THEN s := 32 ELSIF s <= 56 THEN s := 64 ELSIF s <= 120 THEN s := 128
		ELSE s := (s+263) DIV 256 * 256
		END ;
		T.len := dc; data[dcw] := s; INC(dcw); (*len used as address*)
		k := T.nofpar; (*extension level!*)
		IF k > 3 THEN ORS.Mark("ext level too large")
		ELSE Q(T, dcw);
			WHILE k < 3 DO data[dcw] := -1; INC(dcw); INC(k) END
		END ;
		FindPtrFlds(T, 0, dcw); data[dcw] := -1; INC(dcw); tdx := dcw; dc := dcw*4;
		IF tdx >= maxTD THEN ORS.Mark("too many record types"); tdx := 0 END
	END BuildTD;

	PROCEDURE TypeTest* (VAR x: Item; T: ORB.Type; varpar, isguard: BOOLEAN);
		VAR pc0: LONGINT;
	BEGIN
		IF T = NIL THEN
			IF x.mode >= Reg THEN DEC(RH) END;
			SetCC(x, 7)
		ELSE (*fetch tag into RH*)
			IF varpar THEN Put20(0, Ldr, RH, SP, x.a+4+frame)
			ELSE load(x);
				pc0 := pc; Put3orig(BC, EQ, 0);	(*NIL belongs to every pointer type*)
				Put20(0, Ldr, RH, x.r, -8)
			END ;
			Put20(0, Ldr, RH, RH, T.nofpar*4); incR;
			loadTypTagAdr0(0, T);	(*tag of T*)
			Put0(Cmp, RH-1, RH-1, RH-2); DEC(RH, 2);
			IF ~varpar THEN fix(pc0, pc - pc0 - 1) END;
			IF isguard THEN
				IF check THEN Trap(NE, 2) END
			ELSE SetCC(x, EQ);
				IF ~varpar THEN DEC(RH) END
			END
		END
	END TypeTest;

	(* Code generation for Boolean operators *)

	PROCEDURE Not*(VAR x: Item);	 (* x := ~x *)
		VAR t: LONGINT;
	BEGIN
		IF x.mode # Cond THEN loadCond(x) END ;
		x.r := negated(x.r); t := x.a; x.a := x.b; x.b := t
	END Not;

	PROCEDURE And1*(VAR x: Item);	 (* x := x & *)
	BEGIN
		IF x.mode # Cond THEN loadCond(x) END ;
		Put3orig(BC, negated(x.r), x.a); x.a := pc-1; FixLink(x.b); x.b := 0
	END And1;

	PROCEDURE And2*(VAR x, y: Item);
	BEGIN
		IF y.mode # Cond THEN loadCond(y) END ;
		x.a := merged(y.a, x.a); x.b := y.b; x.r := y.r
	END And2;

	PROCEDURE Or1*(VAR x: Item);	 (* x := x OR *)
	BEGIN
		IF x.mode # Cond THEN loadCond(x) END ;
		Put3orig(BC, x.r, x.b);	x.b := pc-1; FixLink(x.a); x.a := 0
	END Or1;

	PROCEDURE Or2*(VAR x, y: Item);
	BEGIN
		IF y.mode # Cond THEN loadCond(y) END ;
		x.a := y.a; x.b := merged(y.b, x.b); x.r := y.r
	END Or2;

	(* Code generation for arithmetic operators *)

	PROCEDURE Neg*(VAR x: Item);	 (* x := -x *)
	BEGIN
		IF x.type.form = ORB.Int THEN
			IF x.mode = ORB.Const THEN x.a := -x.a
			ELSE load0(0, x);
				(* Put10(0, Mov, RH, 0, 0); Put0(Sub, x.r, RH, x.r) *)
					RSBS0(x.r)
			END
		ELSIF x.type.form = ORB.Real THEN
			IF x.mode = ORB.Const THEN x.a := x.a + 7FFFFFFFH + 1
			ELSE
				(* load0(0, x); Put10(0, Mov, RH, 0, 0); Put0(Fsb, x.r, RH, x.r) *)
					loadReal(x);
					ARMv7M.EmitVNEG(armcode, pc, ER(x.r - 100H), ER(x.r - 100H))
			END
		ELSE (*form = Set*)
			IF x.mode = ORB.Const THEN x.a := -x.a-1
			ELSE load0(0, x); Put1(Xor, x.r, x.r, -1)
			END
		END
	END Neg;

	PROCEDURE AddOp*(op: LONGINT; VAR x, y: Item);	 (* x := x +- y *)
	BEGIN
		IF op = ORS.plus THEN
			IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a + y.a
			ELSIF y.mode = ORB.Const THEN
				IF y.a # 0 THEN load0(0, x); Put1a(Add, x.r, x.r, y.a)
				ELSE load(x)
				END
			ELSE load0(0, x); load0(0, y); Put0(Add, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
			END
		ELSE (*op = ORS.minus*)
			IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a - y.a
			ELSIF y.mode = ORB.Const THEN
				IF y.a # 0 THEN load0(0, x); Put1a(Sub, x.r, x.r, y.a)
				ELSE load(x)
				END
			ELSE load0(0, x); load0(0, y); Put0(Sub, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
			END
		END
	END AddOp;

	PROCEDURE log2(m: LONGINT; VAR e: LONGINT): LONGINT;
	BEGIN e := 0;
		WHILE ~ODD(m) DO m := m DIV 2; INC(e) END ;
		RETURN m
	END log2;

	PROCEDURE MulOp*(VAR x, y: Item);	 (* x := x * y *)
		VAR e: LONGINT;
	BEGIN
		IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN x.a := x.a * y.a
		ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN load0(0, x); Put1(Lsl, x.r, x.r, e)
		ELSIF y.mode = ORB.Const THEN load0(0, x); Put1a(Mul, x.r, x.r, y.a)
		ELSIF (x.mode = ORB.Const) & (x.a >= 2) & (log2(x.a, e) = 1) THEN load0(0, y); Put1(Lsl, y.r, y.r, e); x.mode := Reg; x.r := y.r
		ELSIF x.mode = ORB.Const THEN load0(0, y); Put1a(Mul, y.r, y.r, x.a); x.mode := Reg; x.r := y.r
		ELSE load0(0, x); load0(0, y); Put0(Mul, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
		END
	END MulOp;

	(* R.d := R.a - R.n * R.m *)
	PROCEDURE MLS (S: INTEGER; d, n, m, a: INTEGER);
	BEGIN
		ASSERT(S DIV 2 = 0, 20);
		INCL(RM, d);
		ARMv7M.EmitMLS(armcode, pc, ER(d), ER(n), ER(m), ER(a));
		IF S = 1 THEN UpdateFlags(d) END
	END MLS;

	PROCEDURE DivOp*(op: LONGINT; VAR x, y: Item);	 (* x := x op y *)
		VAR e: LONGINT;
	BEGIN
		IF op = ORS.div THEN
			IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
				IF y.a > 0 THEN x.a := x.a DIV y.a ELSE ORS.Mark("bad divisor") END
			ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN load0(0, x); Put1(Asr, x.r, x.r, e)
			ELSIF y.mode = ORB.Const THEN
				IF y.a > 0 THEN load0(0, x); Put1a(Div, x.r, x.r, y.a) ELSE ORS.Mark("bad divisor") END
			ELSE load(y);
				IF check THEN Trap(LE, 6) END ;
				load0(0, x); Put0(Div, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
			END
		ELSE (*op = ORS.mod*)
			IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
				IF y.a > 0 THEN x.a := x.a MOD y.a ELSE ORS.Mark("bad modulus") END
			ELSIF (y.mode = ORB.Const) & (y.a >= 2) & (log2(y.a, e) = 1) THEN load0(0, x);
				IF e <= 16 THEN Put1(And, x.r, x.r, y.a-1) ELSE Put10(0, Lsl, x.r, x.r, 32-e); Put1(Ror, x.r, x.r, 32-e) END
			ELSIF y.mode = ORB.Const THEN
				IF y.a > 0 THEN
					load0(0, x);
					(*
					Put1a(Div, x.r, x.r, y.a);
					Put0(Mov+U, x.r, 0, 0)
					*)
					incR; incR;
						Put10(0, Mov, RH-2, 0, y.a);
						Put00(0, Div, RH-1, x.r, RH-2);
						(*
						Put00(0, Mul, RH-2, RH-2, RH-1);
						Put0(Sub, x.r, x.r, RH-2);
						*)
							MLS(1, x.r, RH-2, RH-1, x.r);
					DEC(RH, 2)
				ELSE ORS.Mark("bad modulus")
				END
			ELSE load(y);
				IF check THEN Trap(LE, 6) END;
				load0(0, x);
				(*
				Put0(Div, RH-2, x.r, y.r);
				Put0(Mov+U, RH-2, 0, 0);
				*)
				incR;
					Put00(0, Div, RH-1, x.r, y.r);
					(*
					Put00(0, Mul, RH-1, RH-1, y.r);
					Put0(Sub, RH-2-1, x.r, RH-1);
					*)
						MLS(1, RH-2-1, RH-1, y.r, x.r);
				DEC(RH);
				DEC(RH); x.r := RH-1
			END
		END
	END DivOp;

	(* Code generation for REAL operators *)

	PROCEDURE RealOp*(op: INTEGER; VAR x, y: Item);	 (* x := x op y *)
	BEGIN
		(*
		load0(0, x); load0(0, y);
		IF op = ORS.plus THEN Put0(Fad, RH-2, x.r, y.r)
		ELSIF op = ORS.minus THEN Put0(Fsb, RH-2, x.r, y.r)
		ELSIF op = ORS.times THEN Put0(Fml, RH-2, x.r, y.r)
		ELSIF op = ORS.rdiv THEN Put0(Fdv, RH-2, x.r, y.r)
		END;
		DEC(RH); x.r := RH-1
		*)
			loadReal(x); loadReal(y);
			IF op = ORS.plus THEN
				ARMv7M.EmitVADD(armcode, pc,
					ER(RH-2), ER(x.r - 100H), ER(y.r - 100H))
			ELSIF op = ORS.minus THEN
				ARMv7M.EmitVSUB(armcode, pc,
					ER(RH-2), ER(x.r - 100H), ER(y.r - 100H))
			ELSIF op = ORS.times THEN
				ARMv7M.EmitVMUL(armcode, pc,
					ER(RH-2), ER(x.r - 100H), ER(y.r - 100H))
			ELSIF op = ORS.rdiv THEN
				ARMv7M.EmitVDIV(armcode, pc,
					ER(RH-2), ER(x.r - 100H), ER(y.r - 100H))
			END;
			DEC(RH); x.r := RH-1+100H; INCL(FR, RH-1)
	END RealOp;

	(* Code generation for set operators *)

	PROCEDURE Singleton*(VAR x: Item);	(* x := {x} *)
	BEGIN
		IF x.mode = ORB.Const THEN x.a := LSL(1, x.a)
		ELSE load0(0, x); Put10(0, Mov, RH, 0, 1); Put0(Lsl, x.r, RH,	x.r)
		END
	END Singleton;

	PROCEDURE Set*(VAR x, y: Item);	 (* x := {x .. y} *)
	BEGIN
		IF (x.mode = ORB.Const) & ( y.mode = ORB.Const) THEN
			IF x.a <= y.a THEN x.a := LSL(2, y.a) - LSL(1, x.a) ELSE x.a := 0 END
		ELSE
			IF (x.mode = ORB.Const) & (x.a <= 16) THEN x.a := LSL(-1, x.a)
			ELSE load0(0, x); Put10(0, Mov, RH, 0, -1); Put0(Lsl, x.r, RH, x.r)
			END ;
			IF (y.mode = ORB.Const) & (y.a < 16) THEN Put1(Mov, RH, 0, LSL(-2, y.a)); y.mode := Reg; y.r := RH; incR
			ELSE load0(0, y); Put10(0, Mov, RH, 0, -2); Put0(Lsl, y.r, RH, y.r)
			END ;
			IF x.mode = ORB.Const THEN
				IF x.a # 0 THEN Put10(0, Xor, y.r, y.r, -1); Put1a(And, RH-1, y.r, x.a) END ;
				x.mode := Reg; x.r := RH-1
			ELSE DEC(RH); Put0(Ann, RH-1, x.r, y.r);
				ASSERT(x.mode = Reg); x.r := RH-1
			END
		END
	END Set;

	PROCEDURE In*(VAR x, y: Item);	(* x := x IN y *)
	BEGIN load0(0, y);
		IF x.mode = ORB.Const THEN Put1(Ror, y.r, y.r, (x.a + 1) MOD 20H); DEC(RH)
		ELSE load0(0, x); Put10(0, Add, x.r, x.r, 1); Put0(Ror, y.r, y.r, x.r); DEC(RH, 2)
		END ;
		SetCC(x, MI)
	END In;

	PROCEDURE SetOp*(op: LONGINT; VAR x, y: Item);	 (* x := x op y *)
		VAR xset, yset: SET; (*x.type.form = Set*)
	BEGIN
		IF (x.mode = ORB.Const) & (y.mode = ORB.Const) THEN
			xset := SYSTEM.VAL(SET, x.a); yset := SYSTEM.VAL(SET, y.a);
			IF op = ORS.plus THEN xset := xset + yset
			ELSIF op = ORS.minus THEN xset := xset - yset
			ELSIF op = ORS.times THEN xset := xset * yset
			ELSIF op = ORS.rdiv THEN xset := xset / yset
			END ;
			x.a := SYSTEM.VAL(LONGINT, xset)
		ELSIF y.mode = ORB.Const THEN
			load0(0, x);
			IF op = ORS.plus THEN Put1a(Ior, x.r, x.r, y.a)
			ELSIF op = ORS.minus THEN Put1a(Ann, x.r, x.r, y.a)
			ELSIF op = ORS.times THEN Put1a(And, x.r, x.r, y.a)
			ELSIF op = ORS.rdiv THEN Put1a(Xor, x.r, x.r, y.a)
			END ;
		ELSE load0(0, x); load0(0, y);
			IF op = ORS.plus THEN Put0(Ior, RH-2, x.r, y.r)
			ELSIF op = ORS.minus THEN Put0(Ann, RH-2, x.r, y.r)
			ELSIF op = ORS.times THEN Put0(And, RH-2, x.r, y.r)
			ELSIF op = ORS.rdiv THEN Put0(Xor, RH-2, x.r, y.r)
			END ;
			DEC(RH); x.r := RH-1
		END
	END SetOp;

	(* Code generation for relations *)

	PROCEDURE IntRelation*(op: INTEGER; VAR x, y: Item); (* x := x < y *)
	BEGIN
		IF (y.mode = ORB.Const) & (y.type.form # ORB.Proc) THEN
			load(x);
			Put1a(Cmp, x.r, x.r, y.a);
			DEC(RH)
		ELSE
			IF (x.mode = Cond) OR (y.mode = Cond) THEN ORS.Mark("not implemented") END;
			load0(0, x); load0(0, y); Put0(Cmp, x.r, x.r, y.r); DEC(RH, 2)
		END;
		SetCC(x, relmap[op - ORS.eql])
	END IntRelation;

(*
	PROCEDURE SetRelation*(op: INTEGER; VAR x, y: Item); (* x := x < y *)
	BEGIN load0(0, x);
		IF (op = ORS.eql) OR (op = ORS.neq) THEN
			IF y.mode = ORB.Const THEN Put1a(Cmp, x.r, x.r, y.a); DEC(RH)
			ELSE load0(0, y); Put0(Cmp, x.r, x.r, y.r); DEC(RH, 2)
			END;
			SetCC(x, relmap[op - ORS.eql])
		ELSE ORS.Mark("illegal relation")
		END
	END SetRelation;
*)

	PROCEDURE FPUToARMReg (VAR x: Item);
	BEGIN
		IF (x.mode = Reg) & (x.r >= 100H) THEN
			x.r := x.r - 100H;
			EXCL(FR, x.r);
			INCL(RM, x.r);
			ARMv7M.EmitVMOVSPR(armcode, pc, 1, ER(x.r), ER(x.r))
		END
	END FPUToARMReg;

	PROCEDURE RealRelation*(op: INTEGER; VAR x, y: Item); (* x := x < y *)
	BEGIN
		IF (y.mode = ORB.Const) & (y.a = 0) THEN
			IF (x.mode = Reg) & (x.r >= 100H) THEN
				FPUToARMReg(x);
				UpdateFlags(x.r)
			ELSE load(x); Put1a(Cmp, x.r, x.r, y.a)
			END;
			DEC(RH)
		ELSE
			loadReal(x); loadReal(y);
			ARMv7M.EmitVCMPER(armcode, pc, 1, ER(x.r - 100H), ER(y.r - 100H));
			ARMv7M.EmitVMRS(armcode, pc, 15 (* APSR_nzcv *));
			DEC(RH, 2)
		END;
		SetCC(x, relmap[op - ORS.eql])
	END RealRelation;

	PROCEDURE StringRelation*(op: INTEGER; VAR x, y: Item); (* x := x < y *)
		(*x, y are char arrays or strings*)
		VAR pc0, pc1: LONGINT;
	BEGIN
		IF x.type.form = ORB.String THEN loadStringAdr0(0, x) ELSE loadAdr0(0, x) END;
		IF y.type.form = ORB.String THEN loadStringAdr0(0, y) ELSE loadAdr0(0, y) END;
		pc0 := pc;
		Put20(0, Ldr+1, RH, x.r, 0); Put10(0, Add, x.r, x.r, 1);
		Put20(0, Ldr+1, RH+1, y.r, 0); Put10(0, Add, y.r, y.r, 1);
		Put0(Cmp, RH+2, RH, RH+1); pc1 := pc; Put3orig(BC, NE, 0);
		Put1(Cmp, RH+2, RH, 0); Put3orig(BC, NE, pc0 - pc - 1);
		fix(pc1, pc - pc1 - 1);
		DEC(RH, 2); SetCC(x, relmap[op - ORS.eql])
	END StringRelation;

	(* Code generation of Assignments *)

	PROCEDURE StrToChar*(VAR x: Item);
	BEGIN x.type := ORB.charType; DEC(strx, 4); x.a := ORD(str[x.a])
	END StrToChar;

	PROCEDURE Store*(VAR x, y: Item); (* x := y *)
		VAR op: LONGINT;
	BEGIN load0(0, y);
		IF x.type.size = 1 THEN op := Str+1 ELSE op := Str END ;
		IF x.mode = ORB.Var THEN
			IF x.r > 0 THEN (*local*) Put2(op, y.r, SP, x.a + frame)
			ELSE
				IF x.r # 0 THEN FPUToARMReg(y) END;
				GetSB(x.r);
				IF x.r # 0 THEN
					Put2orig(op, ER(y.r), ER(SB), x.a);
					armcode[pc] := 00FFFFFFH; INC(pc)
				ELSE Put2(op, y.r, SB, x.a)
				END
			END
		ELSIF x.mode = ORB.Par THEN Put20(0, Ldr, RH, SP, x.a + frame); Put2(op, y.r, RH, x.b);
		ELSIF x.mode = RegI THEN Put2(op, y.r, x.r, x.a); DEC(RH);
		ELSE ORS.Mark("bad mode in Store")
		END;
		DEC(RH)
	END Store;

	PROCEDURE StoreStruct* (VAR x, y: Item); (* x := y, frame = 0 *)
		VAR s, pc0, pc1: LONGINT;
	BEGIN
		IF y.type.size # 0 THEN
			loadAdr0(0, x); loadAdr0(0, y);
			pc0 := -1;
			IF (x.type.form = ORB.Array) & (x.type.len > 0) THEN
				IF y.type.len >= 0 THEN
					IF x.type.size = y.type.size THEN Put10(0, Mov, RH, 0, (y.type.size+3) DIV 4)
					ELSE ORS.Mark("different length/size, not implemented")
					END
				ELSE (*y is open array*) Put2(Ldr, RH, SP, y.a+4); s := y.type.base.size; (*element size*)
					pc0 := pc; Put3orig(BC, EQ, 0);
					IF s = 1 THEN Put10(0, Add, RH, RH, 3); Put10(0, Asr, RH, RH, 2)
					ELSIF s # 4 THEN Put10(0, Mul, RH, RH, s DIV 4)
					END;
					IF check THEN
						ASSERT(x.type.len >= 0);
						Put10(0, Mov, RH+1, 0, (x.type.size+3) DIV 4); Put0(Cmp, RH+1, RH, RH+1); Trap(GT, 3)
					END
				END
			ELSIF x.type.form = ORB.Record THEN Put10(0, Mov, RH, 0, x.type.size DIV 4)
			ELSE ORS.Mark("inadmissible assignment")
			END;
			pc1 := pc;
			Put20(0, Ldr, RH+1, y.r, 0); Put10(0, Add, y.r, y.r, 4);
			Put2(Str, RH+1, x.r, 0); Put10(0, Add, x.r, x.r, 4);
			Put1(Sub, RH, RH, 1); Put3orig(BC, NE, pc1 - pc - 1);
				DEC(RH, 2); ASSERT(RH = 0);
			IF pc0 # -1 THEN fix(pc0, pc - pc0 - 1) END
		END;
		RH := 0
	END StoreStruct;

	PROCEDURE CopyString* (VAR x, y: Item); (* x := y *)
		 VAR len, pc0: LONGINT;
	BEGIN loadAdr0(0, x); len := x.type.len;
		IF len >= 0 THEN
			IF len < y.b THEN ORS.Mark("string too long") END
		ELSIF check THEN Put20(0, Ldr, RH, SP, x.a+4); (*open array len, frame = 0*)
			Put1(Cmp, RH, RH, y.b); Trap(LT, 3)
		END;
		loadStringAdr0(0, y);
		pc0 := pc;
		Put20(0, Ldr, RH, y.r, 0); Put10(0, Add, y.r, y.r, 4);
		Put2(Str, RH, x.r, 0); Put10(0, Add, x.r, x.r, 4);
		Put1(Asr, RH, RH, 24); Put3orig(BC, NE, pc0 - pc - 1); RH := 0
	END CopyString;

	(* Code generation for parameters *)

	PROCEDURE OpenArrayParam*(VAR x: Item);
	BEGIN loadAdr0(0, x);
		IF x.type.len >= 0 THEN Put10(0, Mov, RH, 0, x.type.len) ELSE Put20(0, Ldr, RH, SP, x.a+4+frame) END;
		incR
	END OpenArrayParam;

	PROCEDURE VarParam*(VAR x: Item; ftype: ORB.Type);
		VAR xmd: INTEGER;
	BEGIN xmd := x.mode; loadAdr0(0, x);
		IF (ftype.form = ORB.Array) & (ftype.len < 0) THEN (*open array*)
			IF x.type.len >= 0 THEN Put10(0, Mov, RH, 0, x.type.len) ELSE	Put20(0, Ldr, RH, SP, x.a+4+frame) END;
			incR
		ELSIF ftype.form = ORB.Record THEN
			IF xmd = ORB.Par THEN Put20(0, Ldr, RH, SP, x.a+4+frame); incR ELSE loadTypTagAdr0(0, x.type) END
		END
	END VarParam;

	PROCEDURE ValueParam*(VAR x: Item);
	BEGIN load0(0, x); FPUToARMReg(x)
	END ValueParam;

	PROCEDURE StringParam*(VAR x: Item);
	BEGIN loadStringAdr0(0, x); Put10(0, Mov, RH, 0, x.b); incR	(*len*)
	END StringParam;

	(*For Statements*)

	PROCEDURE For0*(VAR x, y: Item);
	BEGIN load(y)
	END For0;

	PROCEDURE For1*(VAR x, y, z, w: Item; VAR L: LONGINT);
	BEGIN
		IF z.mode = ORB.Const THEN Put1a(Cmp, RH, y.r, z.a)
		ELSE load0(0, z); Put0(Cmp, RH-1, y.r, z.r); DEC(RH)
		END ;
		L := pc;
		IF w.a > 0 THEN Put3orig(BC, GT, 0)
		ELSIF w.a < 0 THEN Put3orig(BC, LT, 0)
		ELSE ORS.Mark("zero increment"); Put3orig(BC, MI, 0)
		END;
		Store(x, y)
	END For1;

	PROCEDURE For2*(VAR x, y, w: Item);
	BEGIN load0(0, x); DEC(RH); Put1a(Add, x.r, x.r, w.a)
	END For2;

	(* Branches, procedure calls, procedure prolog and epilog *)

	PROCEDURE Here*(): LONGINT;
	BEGIN invalSB; RETURN pc
	END Here;

	PROCEDURE FJump*(VAR L: LONGINT);
	BEGIN Put3orig(BC, 7, L); L := pc-1
	END FJump;

	PROCEDURE CFJump*(VAR x: Item);
	BEGIN
		IF x.mode # Cond THEN loadCond(x) END ;
		Put3orig(BC, negated(x.r), x.a); FixLink(x.b); x.a := pc-1
	END CFJump;

	PROCEDURE BJump*(L: LONGINT);
	BEGIN Put3orig(BC, 7, L-pc-1)
	END BJump;

	PROCEDURE CBJump*(VAR x: Item; L: LONGINT);
	BEGIN
		IF x.mode # Cond THEN loadCond(x) END ;
		Put3orig(BC, negated(x.r), L-pc-1); FixLink(x.b); FixLinkWith(x.a, L)
	END CBJump;

	PROCEDURE Fixup*(VAR x: Item);
	BEGIN FixLink(x.a)
	END Fixup;

	PROCEDURE SaveRegs(r: LONGINT);	(* R[0 .. r-1]*)
		VAR r0: LONGINT;
	BEGIN (*r > 0*) r0 := 0;
		Put10(0, Sub, SP, SP, r*4); INC(frame, 4*r);
		REPEAT
			IF r0 IN FR THEN Put2(Str, r0 + 100H, SP, (r-r0-1)*4)
			ELSE Put2(Str, r0, SP, (r-r0-1)*4)
			END;
			INC(r0)
		UNTIL r0 = r
	END SaveRegs;

	PROCEDURE RestoreRegs(r: LONGINT); (*R[0 .. r-1]*)
		VAR r0: LONGINT;
	BEGIN (*r > 0*) r0 := r;
		REPEAT DEC(r0);
			IF r0 IN FR THEN
				ARMv7M.EmitVLDR(armcode, pc, ER(r0), ER(SP), 1, r-r0-1)
			ELSE Put20(0, Ldr, r0, SP, (r-r0-1)*4)
			END
		UNTIL r0 = 0;
		Put10(0, Add, SP, SP, r*4); DEC(frame, 4*r)
	END RestoreRegs;

	PROCEDURE PrepCall*(VAR x: Item; VAR r: LONGINT);
	BEGIN (*x.type.form = ORB.Proc*)
		IF x.mode > ORB.Par THEN load(x) END;
		ASSERT(RH < 16); ASSERT(FR * {16..31} = {});
			IF RH = 0 THEN r := 0
			ELSE r := RH + 16 * ORDSET(FR * {0..RH-1})
			END;
		IF RH > 0 THEN SaveRegs(RH); RH := 0 END
	END PrepCall;

	PROCEDURE Call*(VAR x: Item; r: LONGINT);
	BEGIN (*x.type.form = ORB.Proc*)
		IF x.mode = ORB.Const THEN
			IF x.r >= 0 THEN Put3(BL, 7, (x.a DIV 4)-pc-1)
			ELSE (*imported*)
				IF pc - fixorgP < 1000H THEN
					(* will be fixed up by linker/loader *)
					Put3orig(BL, 7, ((-x.r) * 100H + x.a) * 1000H + pc-fixorgP);
					fixorgP := pc-1
				ELSE ORS.Mark("fixup impossible")
				END
			END
		ELSE
			IF x.mode <= ORB.Par THEN load(x); DEC(RH)
			ELSE
				Put20(0, Ldr, RH, SP, 0); Put10(0, Add, SP, SP, 4);
				Put1(Cmp, RH, RH, 0);
				DEC(r); DEC(frame, 4)
			END;
			IF check THEN Trap(EQ, 5) END;
			Put3(BLR, 7, RH)
		END;
		IF x.type.base.form = ORB.NoTyp THEN (*procedure*) RH := 0
		ELSE (*function*)
			FR := BITS(r DIV 16); ASSERT(FR * {16..31} = {}); r := r MOD 16;
			RH := MT;
			IF r > 0 THEN Put00(0, Mov, r, 0, 0); RestoreRegs(r) END;
			x.mode := Reg; x.r := r; RH := r+1
		END;
		invalSB; RM := {0..31}
	END Call;

	PROCEDURE Enter* (parblksize, locblksize: LONGINT; int: BOOLEAN);
		VAR a, r: LONGINT;
	BEGIN invalSB; frame := 0;
		enterPushFixup := pc;
		IF ~int THEN (*procedure prolog*)
			(* IF locblksize >= 10000H THEN ORS.Mark("too many locals") END; *)
			ARMv6M.EmitPUSH(armcode, pc, {LNK});
			a := parblksize0Proc; r := 0;
			IF locblksize # parblksize0Proc THEN Put10(0, Sub, SP, SP, locblksize) END;
			WHILE a < parblksize DO Put2(Str, r, SP, a); INC(r); INC(a, 4) END
		ELSE (*interrupt procedure*)
			(* IF locblksize > 0H THEN ORS.Mark("locals not allowed") END; *)
			ARMv7M.EmitPUSHW(armcode, pc, {LNK});
			a := parblksize0Int; r := 0;
			IF locblksize # parblksize0Int THEN Put10(0, Sub, SP, SP, locblksize) END;
			WHILE a < parblksize DO Put2(Str, r, SP, a); INC(r); INC(a, 4) END
		END;
		RM := {}
	END Enter;

(*
		PROCEDURE Fix (VAR code: ARRAY OF INTEGER; i: INTEGER);
			VAR cond, off, pc0: INTEGER;
		BEGIN
			IF ORS.errcnt = 0 THEN
				IF code[i] DIV 10000000H MOD 10H = 0EH THEN (* BC *)
					ASSERT(code[i+1] = 00FFFFFEH, 100);
					cond := code[i] DIV 1000000H MOD 10H;
					off := (code[i] MOD 1000000H * 100H) DIV 100H;
					pc0 := pc; pc := i;
					Put3(BC, cond, off);
					IF pc - i = 1 THEN ARMv6M.EmitNOP(armcode, pc) END;
					IF ORS.errcnt = 0 THEN
						ASSERT(pc - i = 2, 101)
					END;
					pc := pc0
				END
			END
		END Fix;
*)

		PROCEDURE Fix (VAR code: ARRAY OF INTEGER; i: INTEGER);
			VAR cond, off, pc0: INTEGER;
		BEGIN
			IF ORS.errcnt = 0 THEN
				IF code[i] DIV 10000000H MOD 10H = 0EH THEN (* BC *)
					cond := code[i] DIV 1000000H MOD 10H;
					off := (code[i] MOD 1000000H * 100H) DIV 100H;
					pc0 := pc; pc := i;
					Put3(BC, cond, off);
					IF ORS.errcnt = 0 THEN
						ASSERT(pc - i = 1, 100)
					END;
					pc := pc0
				END
			END
		END Fix;

		PROCEDURE FixRng (from, to: INTEGER);
		BEGIN
			WHILE from < to DO
				Fix(armcode, from); INC(from)
			END
		END FixRng;

	PROCEDURE Return* (form: INTEGER; VAR x: Item; size: LONGINT; int: BOOLEAN);
		VAR pc0: INTEGER;
	BEGIN
		IF form # ORB.NoTyp THEN load(x); FPUToARMReg(x) END ;
		IF ~int THEN (*procedure epilog*)
			IF size # parblksize0Proc THEN Put10(0, Add, SP, SP, size) END;
			IF LNK IN RM THEN
				ARMv6M.EmitPOP(armcode, pc, {ARMv6M.PC})
			ELSE
				Put3(BR, 7, LNK);
				pc0 := pc; pc := enterPushFixup;
				ARMv6M.EmitNOP(armcode, pc);
				pc := pc0
			END
		ELSE (*interrupt return*)
			IF size # parblksize0Int THEN Put10(0, Add, SP, SP, size) END;
			ARMv7M.EmitPOPW(armcode, pc, ERs(RM) * {4..11} - {ER(MT)} + {ARMv6M.PC});
			pc0 := pc; pc := enterPushFixup;
			ARMv7M.EmitPUSHW(armcode, pc, ERs(RM) * {4..11} - {ER(MT)} + {LNK});
			pc := pc0
		END;
		RH := 0;
		FixRng(enterPushFixup, pc)
	END Return;

	(* In-line code procedures*)

	PROCEDURE Increment*(upordown: LONGINT; VAR x, y: Item);
		VAR op, zr, v: LONGINT;
	BEGIN (*frame = 0*)
		IF upordown = 0 THEN op := Add ELSE op := Sub END ;
		IF x.type = ORB.byteType THEN v := 1 ELSE v := 0 END ;
		IF y.type.form = ORB.NoTyp THEN y.mode := ORB.Const; y.a := 1 END ;
		IF (x.mode = ORB.Var) & (x.r > 0) THEN
			zr := RH; Put20(0, Ldr+v, zr, SP, x.a); incR;
			IF y.mode = ORB.Const THEN Put10(0, op, zr, zr, y.a) ELSE load0(0, y); Put00(0, op, zr, zr, y.r); DEC(RH) END ;
			Put2(Str+v, zr, SP, x.a); DEC(RH)
		ELSE loadAdr0(0, x); zr := RH; Put20(0, Ldr+v, RH, x.r, 0); incR;
			IF y.mode = ORB.Const THEN Put10(0, op, zr, zr, y.a) ELSE load0(0, y); Put00(0, op, zr, zr, y.r); DEC(RH) END ;
			Put2(Str+v, zr, x.r, 0); DEC(RH, 2)
		END
	END Increment;

	PROCEDURE Include*(inorex: LONGINT; VAR x, y: Item);
		VAR op, zr: LONGINT;
	BEGIN loadAdr0(0, x); zr := RH; Put20(0, Ldr, RH, x.r, 0); incR;
		IF inorex = 0 THEN op := Ior ELSE op := Ann END ;
		IF y.mode = ORB.Const THEN Put10(0, op, zr, zr, LSL(1, y.a))
		ELSE load0(0, y); Put10(0, Mov, RH, 0, 1); Put00(0, Lsl, y.r, RH, y.r); Put00(0, op, zr, zr, y.r); DEC(RH)
		END ;
		Put2(Str, zr, x.r, 0); DEC(RH, 2)
	END Include;

	PROCEDURE Assert*(VAR x: Item);
		VAR cond: LONGINT;
	BEGIN
		IF x.mode # Cond THEN loadCond(x) END ;
		IF x.a = 0 THEN cond := negated(x.r)
		ELSE Put3orig(BC, x.r, x.b); FixLink(x.a); x.b := pc-1; cond := 7
		END;
		Trap(cond, 7); FixLink(x.b)
	END Assert;

	PROCEDURE New*(VAR x: Item);
	BEGIN loadAdr0(0, x); loadTypTagAdr0(0, x.type.base); Trap(7, 0); RH := 0; invalSB
	END New;

	PROCEDURE Pack*(VAR x, y: Item);
		VAR z: Item;
	BEGIN z := x; load0(0, x); load0(0, y);
		Put10(0, Lsl, y.r, y.r, 23); Put00(0, Add, x.r, x.r, y.r); DEC(RH); Store(z, x)
	END Pack;

	PROCEDURE Unpk*(VAR x, y: Item);
		VAR z, e0: Item;
	BEGIN	z := x; load0(0, x); e0.mode := Reg; e0.r := RH; e0.type := ORB.intType;
		Put10(0, Asr, RH, x.r, 23); Put10(0, Sub, RH, RH, 127); Store(y, e0); incR;
		Put10(0, Lsl, RH, RH, 23); Put00(0, Sub, x.r, x.r, RH); Store(z, x)
	END Unpk;

	PROCEDURE Led*(VAR x: Item);
	BEGIN (* load0(0, x); Put10(0, Mov, RH, 0, -60); Put2(Str, x.r, RH, 0); DEC(RH) *)
		ORS.Mark("not supported")
	END Led;

	PROCEDURE Get*(VAR x, y: Item);
	BEGIN load0(0, x); x.type := y.type; x.mode := RegI; x.a := 0; Store(y, x)
	END Get;

	PROCEDURE Put*(VAR x, y: Item);
	BEGIN load0(0, x); x.type := y.type; x.mode := RegI; x.a := 0; Store(x, y)
	END Put;

	PROCEDURE Copy*(VAR x, y, z: Item);
		VAR pc0, pc1: LONGINT;
	BEGIN load0(0, x); load0(0, y);
		pc0 := -1;
		IF z.mode = ORB.Const THEN
			IF z.a > 0 THEN load0(0, z) ELSE ORS.Mark("bad count") END
		ELSE load(z);
			IF check THEN Trap(LT, 3) END ;
			pc0 := pc; Put3orig(BC, EQ, 0)
		END;
		pc1 := pc;
		Put20(0, Ldr, RH, x.r, 0); Put10(0, Add, x.r, x.r, 4);
		Put2(Str, RH, y.r, 0); Put10(0, Add, y.r, y.r, 4);
		Put1(Sub, z.r, z.r, 1); Put3orig(BC, NE, pc1 - pc - 1); DEC(RH, 3);
		IF pc0 # -1 THEN fix(pc0, pc - pc0 - 1) END
	END Copy;

	PROCEDURE LDPSR*(VAR x: Item);
	BEGIN (*x.mode = Const*)	Put3(0, 15, x.a + 20H)
	END LDPSR;

	PROCEDURE LDREG* (VAR x, y: Item);
	BEGIN
		IF x.mode = ORB.Const THEN
			IF x.a IN {0..15} THEN
				IF y.mode = ORB.Const THEN Put10(0, Mov, DR(x.a), 0, y.a)
				ELSE load0(0, y); Put00(0, Mov, DR(x.a), 0, y.r); DEC(RH)
				END
			ELSE ORS.Mark("invalid register")
			END
		ELSE ORS.Mark("not supported")
		END
	END LDREG;

	(*In-line code functions*)

	PROCEDURE Abs*(VAR x: Item);
		VAR pc0: LONGINT;
	BEGIN
		IF x.mode = ORB.Const THEN x.a := ABS(x.a)
		ELSIF x.type.form = ORB.Real THEN
			(* load0(0, x); Put10(0, Lsl, x.r, x.r, 1); Put1(Ror, x.r, x.r, 1) *)
				loadReal(x);
				ARMv7M.EmitVABS(armcode, pc, ER(x.r - 100H), ER(x.r - 100H))
		ELSE
			load0(0, x);
			Put1(Cmp, x.r, x.r, 0);
			pc0 := pc; Put3orig(BC, GE, 0);
			(* Put10(0, Mov, RH, 0, 0); Put0(Sub, x.r, RH, x.r) *)
				RSBS0(x.r);
			fix(pc0, pc - pc0 - 1)
		END
	END Abs;

	PROCEDURE Odd*(VAR x: Item);
	BEGIN load0(0, x); Put1(And, x.r, x.r, 1); SetCC(x, NE); DEC(RH)
	END Odd;

(* this is Trunc
	PROCEDURE Floor*(VAR x: Item);
	BEGIN
		(*
		load0(0, x); Put10(0, Mov+U, RH, 0, 4B00H); Put0(Fad+V, x.r, x.r, RH)
		*)
			loadReal(x);
			ARMv7M.EmitVCVTRInt(armcode, pc,
				TRUE, FALSE, TRUE, ER(x.r - 100H), ER(x.r - 100H));
			FPUToARMReg(x)
	END Floor;
*)

	PROCEDURE Floor*(VAR x: Item);
		CONST S = 0;
		VAR i, imm3, imm8: INTEGER;
			ok: BOOLEAN;
	BEGIN
		(*
		load0(0, x); Put10(0, Mov+U, RH, 0, 4B00H); Put0(Fad+V, x.r, x.r, RH)
		*)
			loadReal(x);
			ASSERT(RH < MT, 100);
			ASSERT(RH # SP, 101);
			(* save FPSCR *)
				ARMv7M.EmitVMRS(armcode, pc, ER(RH));
			(* FPSCR.RMode := RM (A2.6.2) *)
				(* FPSCR - {22,23} *)
					ARMv7M.EncodeMI12(0C00000H, i, imm3, imm8, ok);
					ASSERT(ok, 102);
					ARMv7M.EmitDPMI(armcode, pc,
						i, 2 + S, ER(RH), imm3, ER(x.r - 100H), imm8);
							(* S=1: N, Z, C will be updated *) (* NOTE: C *)
				(* FPSCR - {22} + {23} *)
					ARMv7M.EncodeMI12(800000H, i, imm3, imm8, ok);
					ASSERT(ok, 103);
					ARMv7M.EmitDPMI(armcode, pc,
						i, 4 + S, ER(x.r - 100H), imm3, ER(x.r - 100H), imm8);
							(* S=1: N, Z, C will be updated *) (* NOTE: C *)
				(* FPSCR := FPSCR - {22} + {23} *)
					ARMv7M.EmitVMSR(armcode, pc, ER(x.r - 100H));
			ARMv7M.EmitVCVTRInt(armcode, pc,
				TRUE, TRUE, TRUE, ER(x.r - 100H), ER(x.r - 100H));
			(* restore saved FPSCR *)
				ARMv7M.EmitVMSR(armcode, pc, ER(RH));
			FPUToARMReg(x)
	END Floor;

	PROCEDURE Float*(VAR x: Item);
	BEGIN
		(*
		load0(0, x); Put10(0, Mov+U, RH, 0, 4B00H); Put0(Fad+U, x.r, x.r, RH)
		*)
			loadReal(x);
			ARMv7M.EmitVCVTRInt(armcode, pc,
				FALSE, FALSE, TRUE, ER(x.r - 100H), ER(x.r - 100H))
	END Float;

	PROCEDURE Ord*(VAR x: Item);
	BEGIN
		IF x.mode IN {ORB.Var, ORB.Par, RegI, Cond} THEN load(x) END
	END Ord;

	PROCEDURE Len*(VAR x: Item);
	BEGIN
		IF x.type.len >= 0 THEN
			IF x.mode = RegI THEN DEC(RH) END;
			x.mode := ORB.Const; x.a := x.type.len
		ELSE (*open array*) Put2(Ldr, RH, SP, x.a + 4 + frame); x.mode := Reg; x.r := RH; incR
		END
	END Len;

	PROCEDURE Shift*(fct: LONGINT; VAR x, y: Item);
		VAR op: LONGINT;
	BEGIN load0(0, x);
		IF fct = 0 THEN op := Lsl ELSIF fct = 1 THEN op := Asr ELSE op := Ror END ;
		IF y.mode = ORB.Const THEN Put1(op, x.r, x.r, y.a MOD 20H)
		ELSE load0(0, y); Put0(op, RH-2, x.r, y.r); DEC(RH); x.r := RH-1
		END
	END Shift;

	PROCEDURE ADC*(VAR x, y: Item);
	BEGIN load0(0, x); load0(0, y); Put0(Add+U, x.r, x.r, y.r); DEC(RH)
	END ADC;

	PROCEDURE SBC*(VAR x, y: Item);
	BEGIN load0(0, x); load0(0, y); Put0(Sub+U, x.r, x.r, y.r); DEC(RH)
	END SBC;

	PROCEDURE UML*(VAR x, y: Item);
	BEGIN load0(0, x); load0(0, y); Put0(Mul+U, x.r, x.r, y.r); DEC(RH)
	END UML;

	PROCEDURE Bit*(VAR x, y: Item);
	BEGIN load0(0, x); Put20(0, Ldr, x.r, x.r, 0);
		IF y.mode = ORB.Const THEN Put1(Ror, x.r, x.r, y.a+1); DEC(RH)
		ELSE load0(0, y); Put10(0, Add, y.r, y.r, 1); Put0(Ror, x.r, x.r, y.r); DEC(RH, 2)
		END;
		SetCC(x, MI)
	END Bit;

	PROCEDURE Register*(VAR x: Item);
	BEGIN (*x.mode = Const*)
		Put0(Mov, RH, 0, DR(x.a MOD 10H)); x.mode := Reg; x.r := RH; incR
	END Register;

	PROCEDURE H* (VAR x: Item);
	BEGIN (*x.mode = Const*)
		(* Put0(Mov+U + x.a MOD 2 * V, RH, 0, 0); *) ORS.Mark("not supported");
		x.mode := Reg; x.r := RH; incR
	END H;

	PROCEDURE Adr*(VAR x: Item);
	BEGIN
		IF x.mode IN {ORB.Var, ORB.Par, RegI} THEN loadAdr(x)
		ELSIF (x.mode = ORB.Const) & (x.type.form = ORB.Proc) THEN load(x)
		ELSIF (x.mode = ORB.Const) & (x.type.form = ORB.String) THEN loadStringAdr(x)
		ELSE ORS.Mark("not addressable")
		END
	END Adr;

	PROCEDURE Condition*(VAR x: Item);
	BEGIN (*x.mode = Const*) SetCC(x, x.a)
	END Condition;

	PROCEDURE Open* (v: INTEGER);
	BEGIN pc := 0; tdx := 0; strx := 0; RH := 0; FR := {}; updateCarry := FALSE; fixorgP := 0; fixorgD := 0; fixorgT := 0; check := v # 0; version := v;
		IF v = 0 THEN
			armcode[0] := 0; armcode[1] := 0;
			(* CPU exceptions (NMI..SysTick) *)
				pc := 4; WHILE pc < 40H DIV 2 DO
					armcode[pc] := 1; INC(pc);
					armcode[pc] := 0; INC(pc)
				END;
			(* IRQ 0..239 (Cortex-M4 allows up to 240 IRQs) *)
				WHILE pc < 40H DIV 2 + 240 * 2 DO
					armcode[pc] := 1; INC(pc);
					armcode[pc] := 0; INC(pc)
				END
		ELSE ARMv6M.EmitNOP(armcode, pc) (* pc must be not zero (fixups) *)
		END
	END Open;

	PROCEDURE SetDataSize* (dc: LONGINT);
	BEGIN varsize := dc
	END SetDataSize;

	PROCEDURE Header*;
		VAR i, cs: INTEGER;
	BEGIN entry := pc*4;
		IF version = 0 THEN (*RISC-0*)
			armcode[2] := (entry DIV 2 + 1) MOD 10000H;
			armcode[3] := (entry DIV 2 + 1) DIV 10000H MOD 10000H;
			(* NXP checksum *)
				cs := 0; i := 0;
				WHILE i < 7 DO
					cs := cs + armcode[2 * i] + 10000H * armcode[2 * i + 1];
					INC(i)
				END;
				armcode[2 * i] := (-cs) MOD 10000H;
				armcode[2 * i + 1] := (-cs) DIV 10000H MOD 10000H
		ELSE ARMv6M.EmitPUSH(armcode, pc, {LNK}); invalSB
		END
	END Header;

	PROCEDURE NofPtrs(typ: ORB.Type): LONGINT;
		VAR fld: ORB.Object; n: LONGINT;
	BEGIN
		IF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp) THEN n := 1
		ELSIF typ.form = ORB.Record THEN
			fld := typ.dsc; n := 0;
			WHILE fld # NIL DO n := NofPtrs(fld.type) + n; fld := fld.next END
		ELSIF typ.form = ORB.Array THEN n := NofPtrs(typ.base) * typ.len
		ELSE n := 0
		END ;
		RETURN n
	END NofPtrs;

	PROCEDURE FindPtrs(VAR R: Files.Rider; typ: ORB.Type; adr: LONGINT);
		VAR fld: ORB.Object; i, s: LONGINT;
	BEGIN
		IF (typ.form = ORB.Pointer) OR (typ.form = ORB.NilTyp) THEN Files.WriteLInt(R, adr)
		ELSIF typ.form = ORB.Record THEN
			fld := typ.dsc;
			WHILE fld # NIL DO FindPtrs(R, fld.type, fld.val + adr); fld := fld.next END
		ELSIF typ.form = ORB.Array THEN
			s := typ.base.size;
			FOR i := 0 TO typ.len-1 DO FindPtrs(R, typ.base, i*s + adr) END
		END
	END FindPtrs;

	PROCEDURE Close* (VAR modid: ORS.Ident; key, nofent: LONGINT);
		VAR obj: ORB.Object;
			i, comsize, nofimps, nofptrs, size: LONGINT;
			name: ORS.Ident;
			F: Files.File; R: Files.Rider;
	BEGIN	(*exit code*)
		FixRng(0, pc);
		IF version = 0 THEN Put3(BC, 7, -1)	(*RISC-0*)
		ELSE ARMv6M.EmitPOP(armcode, pc, {ARMv6M.PC})
		END;
		obj := ORB.topScope.next; nofimps := 0; comsize := 4; nofptrs := 0;
		WHILE obj # NIL DO
			IF (obj.class = ORB.Mod) & (obj.dsc # ORB.system) THEN INC(nofimps) (*count imports*)
			ELSIF (obj.exno # 0) & (obj.class = ORB.Const) & (obj.type.form = ORB.Proc)
					& (obj.type.nofpar = 0) & (obj.type.base = ORB.noType) THEN i := 0; (*count commands*)
				WHILE obj.name[i] # 0X DO INC(i) END ;
				i := (i+4) DIV 4 * 4; INC(comsize, i+4)
			ELSIF obj.class = ORB.Var THEN INC(nofptrs, NofPtrs(obj.type))	(*count pointers*)
			END;
			obj := obj.next
		END;
		size := varsize + strx + comsize + (pc + nofimps + nofent + nofptrs + 1)*4;	(*varsize includes type descriptors*)

		ORB.MakeFileName(name, modid, ".a7m"); (*write code file*)
		F := Files.New(name); Files.Set(R, F, 0); Files.WriteString(R, modid); Files.WriteLInt(R, key); Files.Write(R, CHR(version));
		Files.WriteLInt(R, size);
		obj := ORB.topScope.next;
		WHILE (obj # NIL) & (obj.class = ORB.Mod) DO	(*imports*)
			IF obj.dsc # ORB.system THEN Files.WriteString(R, obj(ORB.Module).orgname); Files.WriteLInt(R, obj.val) END ;
			obj := obj.next
		END;
		Files.Write(R, 0X);
		Files.WriteLInt(R, tdx*4);
		i := 0;
		WHILE i < tdx DO Files.WriteLInt(R, data[i]); INC(i) END ; (*type descriptors*)
		Files.WriteLInt(R, varsize - tdx*4);	(*data*)
		Files.WriteLInt(R, strx);
		FOR i := 0 TO strx-1 DO Files.Write(R, str[i]) END ;	(*strings*)
		Files.WriteLInt(R, pc);	(*code len*)
		FOR i := 0 TO pc-1 DO
			Files.WriteLInt(R, armcode[i])
		END; (*program*)
		obj := ORB.topScope.next;
		WHILE obj # NIL DO	(*commands*)
			IF (obj.exno # 0) & (obj.class = ORB.Const) & (obj.type.form = ORB.Proc) &
					(obj.type.nofpar = 0) & (obj.type.base = ORB.noType) THEN
				Files.WriteString(R, obj.name); Files.WriteLInt(R, obj.val)
			END;
			obj := obj.next
		END;
		Files.Write(R, 0X);
		Files.WriteLInt(R, nofent); Files.WriteLInt(R, entry);
		obj := ORB.topScope.next;
		WHILE obj # NIL DO	(*entries*)
			IF obj.exno # 0 THEN
				IF (obj.class = ORB.Const) & (obj.type.form = ORB.Proc) OR (obj.class = ORB.Var) THEN
					Files.WriteLInt(R, obj.val)
				ELSIF obj.class = ORB.Typ THEN
					IF obj.type.form = ORB.Record THEN Files.WriteLInt(R,	obj.type.len MOD 10000H)
					ELSIF (obj.type.form = ORB.Pointer) & ((obj.type.base.typobj = NIL) OR (obj.type.base.typobj.exno = 0)) THEN
						Files.WriteLInt(R, obj.type.base.len MOD 10000H)
					END
				END
			END;
			obj := obj.next
		END;
		obj := ORB.topScope.next;
		WHILE obj # NIL DO	(*pointer variables*)
			IF obj.class = ORB.Var THEN FindPtrs(R, obj.type, obj.val) END ;
			obj := obj.next
		END;
		Files.WriteLInt(R, -1);
		Files.WriteLInt(R, fixorgP); Files.WriteLInt(R, fixorgD); Files.WriteLInt(R, fixorgT); Files.WriteLInt(R, entry);
		Files.Write(R, "O"); Files.Register(F)
	END Close;

BEGIN
	relmap[0] := 1; relmap[1] := 9; relmap[2] := 5; relmap[3] := 6; relmap[4] := 14; relmap[5] := 13
END O7ARMv7MG.

(!)DevCompiler.CompileThis O7Files O7Texts O7Oberon O7S O7B O7ARMv6M O7ARMv7M O7ARMv7MG (!)

(!)DevDebug.UnloadThis O7ARMv7MLinker O7ARMv7MTool O7ARMv7MP O7ARMv7MG O7ARMv7M O7ARMv6M O7B O7S O7Oberon O7Texts O7Files (!)