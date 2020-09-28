MODULE O7ARMv6M;

	(*
		Alexander Shiryaev, 2014.09

		ARMv6-M Architecture Reference Manual
http://ecee.colorado.edu/ecen3000/labs/lab3/files/DDI0419C_arm_architecture_v6m_reference_manual.pdf
	*)

	IMPORT SYSTEM, Strings := VT100, Out;

(*
	TYPE
		LONGINT = INTEGER;
*)

	CONST
		(* registers *)
			R0* = 0; R1* = 1; R2* = 2; R3* = 3;
			R4* = 4; R5* = 5; R6* = 6; R7* = 7;
			R8* = 8; R9* = 9; R10* = 10; R11* = 11; R12* = 12;
			SP* = 13; LR* = 14; PC* = 15;
		(* conditions *)
			EQ* = 0; NE* = 1; CS* = 2; CC* = 3;
			MI* = 4; PL* = 5; VS* = 6; VC* = 7;
			HI* = 8; LS* = 9; GE* = 10; LT* = 11;
			GT* = 12; LE* = 13; AL* = 14;

	PROCEDURE BITS (x: INTEGER): SET;
	BEGIN
		RETURN SYSTEM.VAL(SET, x)
	END BITS;

	PROCEDURE ORDSET (x: SET): INTEGER;
	BEGIN
		RETURN SYSTEM.VAL(INTEGER, x)
	END ORDSET;

	(* A6.7.1 *)
	PROCEDURE EmitADCSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(m DIV 8 = 0, 20);
		ASSERT(dn DIV 8 = 0, 21);
		code[pc] := 4140H + m * 8 + dn; INC(pc)
	END EmitADCSR;

	(* A6.7.2 *)
	PROCEDURE EmitADDSIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, n, im: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		IF im DIV 8 = 0 THEN
			code[pc] := 1C00H + im * 40H + n * 8 + d; INC(pc)
		ELSIF (im DIV 100H = 0) & (d = n) THEN
			code[pc] := 3000H + d * 100H + im; INC(pc)
		ELSE HALT(1)
		END
	END EmitADDSIm;

	(* A6.7.3, encoding T1 *)
	PROCEDURE EmitADDSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, n, m: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		ASSERT(m DIV 8 = 0, 22);
		code[pc] := 1800H + m * 40H + n * 8 + d; INC(pc)
	END EmitADDSR;

	(* A6.7.3, encoding T2 *)
	PROCEDURE EmitADDR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(dn IN {0..12,14..15}, 20);
		ASSERT(m IN {0..12,14..15}, 21);
		ASSERT(~((dn = PC) & (m = PC)), 22);
		ASSERT(dn # PC, 23);
		code[pc] := 4400H + dn DIV 8 * 80H + m * 8 + dn MOD 8; INC(pc)
	END EmitADDR;

	(* A6.7.4 *)
	PROCEDURE EmitADDSPIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, im: INTEGER);
	BEGIN
		IF d = SP THEN
			ASSERT(im DIV 80H = 0, 20);
			code[pc] := 0B000H + im; INC(pc)
		ELSE
			ASSERT(d DIV 8 = 0, 21);
			ASSERT(im DIV 100H = 0, 22);
			code[pc] := 0A800H + d * 100H + im; INC(pc)
		END
	END EmitADDSPIm;

	(* A6.7.5 *)
	PROCEDURE EmitADDSPR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, m: INTEGER);
	BEGIN
		ASSERT(d DIV 10H = 0, 20);
		ASSERT(m DIV 10H = 0, 21);
		IF d = SP THEN
			code[pc] := 4485H + m * 8; INC(pc)
		ELSE
			ASSERT(d = m, 22);
			ASSERT(d # PC, 22);
			code[pc] := 4468H + d DIV 8 * 80H + d MOD 8; INC(pc)
		END
	END EmitADDSPR;

	(* A6.7.7 *)
	PROCEDURE EmitANDSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(dn DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := 4000H + m * 8 + dn; INC(pc)
	END EmitANDSR;

	(* A6.7.8 *)
	PROCEDURE EmitASRSIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, m, im: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		ASSERT(im DIV 32 = 0, 22);
		code[pc] := 1000H + im * 40H + m * 8 + d; INC(pc)
	END EmitASRSIm;

	(* A6.7.9 *)
	PROCEDURE EmitASRSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(dn DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := 4100H + m * 8 + dn; INC(pc)
	END EmitASRSR;

	(* A6.7.10, encoding T1 *)
	PROCEDURE EmitBC* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; cond, im: INTEGER);
	BEGIN
		ASSERT(cond IN {0..13}, 20);
		ASSERT(im >= -128, 21);
		ASSERT(im <= 127, 22);
		code[pc] := 0D000H + cond * 100H + im MOD 100H; INC(pc)
	END EmitBC;

	(* A6.7.10, encoding T2 *)
	PROCEDURE EmitB* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; im: INTEGER);
	BEGIN
		ASSERT(im >= -1024, 21);
		ASSERT(im <= 1023, 22);
		code[pc] := 0E000H + im MOD 800H; INC(pc)
	END EmitB;

	(* A6.7.11 *)
	PROCEDURE EmitBICSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(dn DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := 4380H + m * 8 + dn; INC(pc)
	END EmitBICSR;

(*
	PROCEDURE DecodeBLabel24* (S, imm10, J1, J2, imm11: INTEGER): INTEGER;
	BEGIN
		RETURN ((S * 1000000H + (J1 + S + 1) MOD 2 * 800000H + (J2 + S + 1) MOD 2 * 400000H + imm10 * 1000H + imm11 * 2) * 80H) DIV 80H
	END DecodeBLabel24;
*)

	PROCEDURE DecodeBLabel24* (S, imm10, J1, J2, imm11: INTEGER): INTEGER;
		VAR t0, t1, t2, t3, t4, t5: INTEGER;
	BEGIN
		t0 := S * 1000000H;
		t1 := ((J1 + S + 1) MOD 2) * 800000H;
		t2 := ((J2 + S + 1) MOD 2) * 400000H;
		t3 := imm10 * 1000H;
		t4 := imm11 * 2;
		t5 := (t0 + t1 + t2 + t3 + t4) * 80H;
		RETURN t5 DIV 80H
	END DecodeBLabel24;

	PROCEDURE EncodeBLabel24* (off: INTEGER; (*OUT*)VAR S, imm10, J1, J2, imm11: INTEGER);
		VAR test: INTEGER;
	BEGIN
		ASSERT(off * 2 >= -16777216, 20);
		ASSERT(off * 2 <= 16777214, 21);
		imm11 := off MOD 800H;
		imm10 := off DIV 800H MOD 400H;
		S := off DIV 800000H MOD 2;
		J1 := (off DIV 400000H + S + 1) MOD 2;
		J2 := (off DIV 200000H + S + 1) MOD 2;

		off := off * 2;
		test := DecodeBLabel24(S, imm10, J1, J2, imm11);
		IF off # test THEN
			Out.String("O7ARMv6M.EncodeBLabel24: off="); Out.Int(off, 0); Out.String(" test="); Out.Int(test, 0); Out.Ln;
			Out.String("  S="); Out.Int(S, 0); Out.String(" imm10="); Out.Int(imm10, 0);
				Out.String(" J1="); Out.Int(J1, 0); Out.String(" J2="); Out.Int(J2, 0);
				Out.String(" imm11="); Out.Int(imm11, 0); Out.Ln
		END;
		ASSERT(off = test, 100)
	END EncodeBLabel24;

	(* A6.7.13 *)
	PROCEDURE EmitBL* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; off: INTEGER);
		VAR S, imm10, J1, J2, imm11: INTEGER;
	BEGIN
		EncodeBLabel24(off, S, imm10, J1, J2, imm11);
		code[pc] := 0F000H + S * 400H + imm10; INC(pc);
		code[pc] := 0D000H + J1 * 2000H + J2 * 800H + imm11; INC(pc)
	END EmitBL;

	PROCEDURE DecodeBL* (c: INTEGER): INTEGER;
		VAR S, imm10, J1, J2, imm11: INTEGER;

		PROCEDURE IsBL (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {11..15,28,30,31} = {12..15,28,30,31}
		END IsBL;

	BEGIN
		ASSERT(IsBL(c), 20);
		imm11 := c DIV 10000H MOD 800H;
		J2 := c DIV 8000000H MOD 2;
		J1 := c DIV 20000000H MOD 2;
		imm10 := c MOD 400H;
		S := c DIV 400H MOD 2;
		RETURN DecodeBLabel24(S, imm10, J1, J2, imm11)
	END DecodeBL;

	(* A6.7.14 *)
	PROCEDURE EmitBLX* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; m: INTEGER);
	BEGIN
		ASSERT(m IN {0..14}, 20);
		code[pc] := 4780H + m * 8; INC(pc)
	END EmitBLX;

	(* A6.7.15 *)
	PROCEDURE EmitBX* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; m: INTEGER);
	BEGIN
		ASSERT(m IN {0..14}, 20);
		code[pc] := 4700H + m * 8; INC(pc)
	END EmitBX;

	(* A6.7.17 *)
	PROCEDURE EmitCMPIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; n, im: INTEGER);
	BEGIN
		ASSERT(n DIV 8 = 0, 20);
		ASSERT(im DIV 100H = 0, 21);
		code[pc] := 2800H + n * 100H + im; INC(pc)
	END EmitCMPIm;

	(* A6.7.23 *)
	PROCEDURE EmitEORSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(m DIV 8 = 0, 20);
		ASSERT(dn DIV 8 = 0, 21);
		code[pc] := 4040H + m * 8 + dn; INC(pc)
	END EmitEORSR;

	(* A6.7.26 *)
	PROCEDURE EmitLDRIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; t, n, im: INTEGER);
	BEGIN
		ASSERT(t DIV 8 = 0, 20);
		IF n = SP THEN
			ASSERT(im DIV 100H = 0, 21);
			code[pc] := 9800H + t * 100H + im; INC(pc)
		ELSE
			ASSERT(n DIV 8 = 0, 22);
			ASSERT(im DIV 32 = 0, 23);
			code[pc] := 6800H + im * 40H + n * 8 + t; INC(pc)
		END
	END EmitLDRIm;

	(* A6.7.28 *)
	PROCEDURE EmitLDRR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; t, n, m: INTEGER);
	BEGIN
		ASSERT(t DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		ASSERT(m DIV 8 = 0, 22);
		code[pc] := 5800H + m * 40H + n * 8 + t; INC(pc)
	END EmitLDRR;

	(* A6.7.29 *)
	PROCEDURE EmitLDRBIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; t, n, im: INTEGER);
	BEGIN
		ASSERT(t DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		ASSERT(im DIV 32 = 0, 22);
		code[pc] := 7800H + im * 40H + n * 8 + t; INC(pc)
	END EmitLDRBIm;

	(* A6.7.30 *)
	PROCEDURE EmitLDRBR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; t, n, m: INTEGER);
	BEGIN
		ASSERT(t DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		ASSERT(m DIV 8 = 0, 22);
		code[pc] := 5C00H + m * 40H + n * 8 + t; INC(pc)
	END EmitLDRBR;

	(* A6.7.35 *)
	PROCEDURE EmitLSLSIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, m, im: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		ASSERT(im IN {1..31}, 22);
		code[pc] := im * 40H + m * 8 + d; INC(pc)
	END EmitLSLSIm;

	(* A6.7.36 *)
	PROCEDURE EmitLSLSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(dn DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := 4080H + m * 8 + dn; INC(pc)
	END EmitLSLSR;

	(* A6.7.37 *)
	PROCEDURE EmitLSRSIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, m, im: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		ASSERT(im DIV 32 = 0, 22);
		code[pc] := 800H + im * 40H + m * 8 + d; INC(pc)
	END EmitLSRSIm;

	(* A6.7.38 *)
	PROCEDURE EmitLSRSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(dn DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := 40C0H + m * 8 + dn; INC(pc)
	END EmitLSRSR;

	(* A6.7.39 *)
	PROCEDURE EmitMOVSIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, im: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(im DIV 100H = 0, 21);
		code[pc] := 2000H + d * 100H + im; INC(pc)
	END EmitMOVSIm;

	(* A6.7.40, encoding T2 *)
	PROCEDURE EmitMOVSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, m: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := m * 8 + d; INC(pc)
	END EmitMOVSR;

	(* A6.7.44 *)
	PROCEDURE EmitMULSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dm, n: INTEGER);
	BEGIN
		ASSERT(dm DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		code[pc] := 4340H + n * 8 + dm; INC(pc)
	END EmitMULSR;

	(* A6.7.45 *)
	PROCEDURE EmitMVNSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, m: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := 43C0H + m * 8 + d; INC(pc)
	END EmitMVNSR;

	(* A6.7.47 *)
	PROCEDURE EmitNOP* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER);
	BEGIN
		code[pc] := 0BF00H; INC(pc)
	END EmitNOP;

	(* A6.7.48 *)
	PROCEDURE EmitORRSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(dn DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := 4300H + m * 8 + dn; INC(pc)
	END EmitORRSR;

	(* A6.7.49 *)
	PROCEDURE EmitPOP* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; regs: SET);
		VAR P: INTEGER;
	BEGIN
		ASSERT(regs * {8..14,16..31} = {}, 20);
		ASSERT(regs # {}, 21);
		IF PC IN regs THEN EXCL(regs, PC); P := 1 ELSE P := 0 END;
		code[pc] := 0BC00H + P * 100H + ORDSET(regs); INC(pc)
	END EmitPOP;

	(* A6.7.50 *)
	PROCEDURE EmitPUSH* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; regs: SET);
		VAR M: INTEGER;
	BEGIN
		ASSERT(regs * {8..13,15..31} = {}, 20);
		ASSERT(regs # {}, 21);
		IF LR IN regs THEN EXCL(regs, LR); M := 1 ELSE M := 0 END;
		code[pc] := 0B400H + M * 100H + ORDSET(regs); INC(pc)
	END EmitPUSH;

	(* A6.7.54 *)
	PROCEDURE EmitRORSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(dn DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := 41C0H + m * 8 + dn; INC(pc)
	END EmitRORSR;

	(* A6.7.55 *)
	PROCEDURE EmitRSBS0* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, n: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		code[pc] := 4240H + n * 8 + d; INC(pc)
	END EmitRSBS0;

	(* A6.7.56 *)
	PROCEDURE EmitSBCSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; dn, m: INTEGER);
	BEGIN
		ASSERT(dn DIV 8 = 0, 20);
		ASSERT(m DIV 8 = 0, 21);
		code[pc] := 4180H + m * 8 + dn; INC(pc)
	END EmitSBCSR;

	(* A6.7.59 *)
	PROCEDURE EmitSTRIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; t, n, im: INTEGER);
	BEGIN
		ASSERT(t DIV 8 = 0, 20);
		IF n = SP THEN
			ASSERT(im DIV 100H = 0, 21);
			code[pc] := 9000H + t * 100H + im; INC(pc)
		ELSE
			ASSERT(n DIV 8 = 0, 22);
			ASSERT(im DIV 32 = 0, 23);
			code[pc] := 6000H + im * 40H + n * 8 + t; INC(pc)
		END
	END EmitSTRIm;

	(* A6.7.60 *)
	PROCEDURE EmitSTRR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; t, n, m: INTEGER);
	BEGIN
		ASSERT(t DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		ASSERT(m DIV 8 = 0, 22);
		code[pc] := 5000H + m * 40H + n * 8 + t; INC(pc)
	END EmitSTRR;

	(* A6.7.61 *)
	PROCEDURE EmitSTRBIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; t, n, im: INTEGER);
	BEGIN
		ASSERT(t DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		ASSERT(im DIV 32 = 0, 22);
		code[pc] := 7000H + im * 40H + n * 8 + t; INC(pc)
	END EmitSTRBIm;

	(* A6.7.62 *)
	PROCEDURE EmitSTRBR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; t, n, m: INTEGER);
	BEGIN
		ASSERT(t DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		ASSERT(m DIV 8 = 0, 22);
		code[pc] := 5400H + m * 40H + n * 8 + t; INC(pc)
	END EmitSTRBR;

	(* A6.7.65 *)
	PROCEDURE EmitSUBSIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, n, im: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		IF im DIV 8 = 0 THEN
			code[pc] := 1E00H + im * 40H + n * 8 + d; INC(pc)
		ELSIF (im DIV 100H = 0) & (d = n) THEN
			code[pc] := 3800H + d * 100H + im; INC(pc)
		ELSE HALT(1)
		END
	END EmitSUBSIm;

	(* A6.7.66 *)
	PROCEDURE EmitSUBSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; d, n, m: INTEGER);
	BEGIN
		ASSERT(d DIV 8 = 0, 20);
		ASSERT(n DIV 8 = 0, 21);
		ASSERT(m DIV 8 = 0, 22);
		code[pc] := 1A00H + m * 40H + n * 8 + d; INC(pc)
	END EmitSUBSR;

	(* A6.7.67 *)
	PROCEDURE EmitSUBSPIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; imm7: INTEGER);
	BEGIN
		ASSERT(imm7 DIV 80H = 0, 20);
		code[pc] := 0B080H + imm7; INC(pc)
	END EmitSUBSPIm;

	(* A6.7.68 *)
	PROCEDURE EmitSVC* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; im: INTEGER);
	BEGIN
		ASSERT(im DIV 100H = 0, 20);
		code[pc] := 0DF00H + im; INC(pc)
	END EmitSVC;

	(* A6.7.76 *)
	PROCEDURE EmitWFI* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER);
	BEGIN
		code[pc] := 0BF30H; INC(pc)
	END EmitWFI;

	PROCEDURE RegRepr* (r: INTEGER; (*OUT*)VAR s: ARRAY OF CHAR);
	BEGIN
		CASE r OF R0: COPY("r0", s)
		| R1: COPY("r1", s)
		| R2: COPY("r2", s)
		| R3: COPY("r3", s)
		| R4: COPY("r4", s)
		| R5: COPY("r5", s)
		| R6: COPY("r6", s)
		| R7: COPY("r7", s)
		| R8: COPY("r8", s)
		| R9: COPY("r9", s)
		| R10: COPY("r10", s)
		| R11: COPY("r11", s)
		| R12: COPY("r12", s)
		| SP: COPY("SP", s)
		| LR: COPY("LR", s)
		| PC: COPY("PC", s)
		END
	END RegRepr;

	PROCEDURE CondRepr* (cond: INTEGER; (*OUT*)VAR s: ARRAY OF CHAR);
	BEGIN
		CASE cond OF EQ: COPY("EQ", s)
		| NE: COPY("NE", s)
		| CS: COPY("CS", s)
		| CC: COPY("CC", s)
		| MI: COPY("MI", s)
		| PL: COPY("PL", s)
		| VS: COPY("VS", s)
		| VC: COPY("VC", s)
		| HI: COPY("HI", s)
		| LS: COPY("LS", s)
		| GE: COPY("GE", s)
		| LT: COPY("LT", s)
		| GT: COPY("GT", s)
		| LE: COPY("LE", s)
		ELSE COPY("?", s)
		END
	END CondRepr;

	PROCEDURE IsLThumb32* (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN (c DIV 2000H = 7) & (c DIV 800H MOD 4 # 0)
	END IsLThumb32;

	(* d: decoder state *)
	PROCEDURE OpcodeRepr* (VAR d: INTEGER; c: INTEGER; (*OUT*)VAR s: ARRAY OF CHAR);
		VAR w: INTEGER;
			s0: ARRAY 3 OF CHAR;
			a, b: INTEGER;

		PROCEDURE WStr ((*IN*) s0: ARRAY OF CHAR);
			VAR i: INTEGER;
		BEGIN
			i := 0;
			WHILE (i < LEN(s0(*$*))) & (s0[i] # 0X) DO
				s[w] := s0[i]; INC(w);
				INC(i)
			END
		END WStr;

		PROCEDURE WReg (r: INTEGER);
			VAR s0: ARRAY 4 OF CHAR;
		BEGIN
			RegRepr(r, s0);
			WStr(s0)
		END WReg;

		PROCEDURE WInt (x: INTEGER);
			VAR s0: ARRAY 12 OF CHAR;
		BEGIN
			Strings.IntToStr(x, s0);
			WStr(s0)
		END WInt;

	BEGIN
		ASSERT(c DIV 10000H = 0, 20);
		w := 0;
		IF d = 0 THEN
			IF c DIV 4000H = 0 THEN
					(* shift (immediate), add, substract, move, and compare *)
				IF c DIV 800H = 0 THEN (* MOVSR | LSLSIm *)
					IF c DIV 40H = 0 THEN (* MOVSR *)
						WStr("MOVS "); WReg(c MOD 8);
						WStr(", "); WReg(c DIV 8 MOD 8)
					ELSE (* LSLSIm *)
						WStr("LSLS "); WReg(c MOD 8);
						WStr(", "); WReg(c DIV 8 MOD 8);
						WStr(", #"); WInt(c DIV 40H)
					END
				ELSIF c DIV 800H = 1 THEN (* LSRSIm *)
					WStr("LSRS "); WReg(c MOD 8); WStr(", "); WReg(c DIV 8 MOD 8);
					WStr(", #"); WInt(c DIV 40H MOD 32)
				ELSIF c DIV 800H = 2 THEN (* ASRSIm *)
					WStr("ASRS "); WReg(c MOD 8); WStr(", "); WReg(c DIV 8 MOD 8);
					WStr(", #"); WInt(c DIV 40H MOD 32)
				ELSIF c DIV 200H = 12 THEN (* ADDSR *)
					WStr("ADDS "); WReg(c MOD 8); WStr(", "); WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8)
				ELSIF c DIV 200H = 13 THEN (* SUBSR *)
					WStr("SUBS "); WReg(c MOD 8); WStr(", "); WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8)
				ELSIF c DIV 200H = 14 THEN (* ADDSIm (3-bit) *)
					WStr("ADDS "); WReg(c MOD 8); WStr(", "); WReg(c DIV 8 MOD 8);
					WStr(", #"); WInt(c DIV 40H MOD 8)
				ELSIF c DIV 200H = 15 THEN (* SUBSIm (3-bit) *)
					WStr("SUBS "); WReg(c MOD 8); WStr(", "); WReg(c DIV 8 MOD 8);
					WStr(", #"); WInt(c DIV 40H MOD 8)
				ELSIF c DIV 800H = 4 THEN (* MOVSIm *)
					WStr("MOVS "); WReg(c DIV 100H MOD 8);
					WStr(", #"); WInt(c MOD 100H)
				ELSIF c DIV 800H = 5 THEN (* CMPIm *)
					WStr("CMP "); WReg(c DIV 100H MOD 8);
					WStr(", #"); WInt(c MOD 100H)
				ELSIF c DIV 800H = 6 THEN (* ADDSIm (8-bit) *)
					WStr("ADDS "); WReg(c DIV 100H MOD 8);
					WStr(", #"); WInt(c MOD 100H)
				ELSIF c DIV 800H = 7 THEN (* SUBSIm (8-bit) *)
					WStr("SUBS "); WReg(c DIV 100H MOD 8);
					WStr(", #"); WInt(c MOD 100H)
				END
			ELSIF c DIV 400H = 16 THEN (* data processing *)
				CASE c DIV 40H MOD 16 OF 0: WStr("ANDS")
				| 1: WStr("EORS")
				| 2: WStr("LSLS")
				| 3: WStr("LSRS")
				| 4: WStr("ASRS")
				| 5: WStr("ADCS")
				| 6: WStr("SBCS")
				| 7: WStr("RORS")
				| 8: WStr("TST")
				| 9: WStr("RSBS")
				| 10: WStr("CMP")
				| 11: WStr("CMN")
				| 12: WStr("ORRS")
				| 13: WStr("MULS")
				| 14: WStr("BICS")
				| 15: WStr("MVNS")
				END; s[w] := ' '; INC(w);
				WReg(c MOD 8); WStr(", "); WReg(c DIV 8 MOD 8);
				IF c DIV 40H MOD 16 = 9 THEN (* RSBS *)
					WStr(", #0")
				ELSIF c DIV 40H MOD 16 = 13 THEN (* MULS *)
					WStr(", "); WReg(c MOD 8)
				END
			ELSIF c DIV 400H = 17 THEN
					(* special data instructions and branch and exchange *)
				IF c DIV 100H MOD 4 = 0 THEN (* ADDR *)
					a := c DIV 80H MOD 2 * 8 + c MOD 8;
					b := c DIV 8 MOD 10H;
					IF b = SP THEN (* A6.7.5: ADD (SP plus register), encoding T1 *)
						WStr("ADD "); WReg(a); WStr(", SP, "); WReg(a)
					ELSIF a = SP THEN
							(* A6.7.5: ADD (SP plus register), encoding T2 *)
						WStr("ADD SP, "); WReg(b)
					ELSE
						WStr("ADD "); WReg(a); WStr(", "); WReg(b);
						IF (a = PC) & (b = PC) THEN WStr(" (UNPREDICTABLE)") END
					END
				ELSIF c DIV 40H MOD 10H = 0 THEN
					WStr("UNPREDICTABLE")
				ELSIF (c DIV 40H MOD 10H = 5) OR (c DIV 80H MOD 8H = 3) THEN
						(* CMPR, encoding T2 *)

				ELSIF c DIV 100H MOD 4 = 2 THEN (* MOVR *)

				ELSIF c DIV 80H MOD 8 = 6 THEN (* BX *)
					IF c MOD 8 = 0 THEN
						WStr("BX "); WReg(c DIV 8 MOD 10H);
						IF c DIV 8 MOD 10H = 15 THEN
							WStr(" (UNPREDICTABLE)")
						END
					END
				ELSIF c DIV 80H MOD 8 = 7 THEN (* BLX *)
					IF c MOD 8 = 0 THEN
						WStr("BLX "); WReg(c DIV 8 MOD 10H);
						IF c DIV 8 MOD 10H = 15 THEN
							WStr(" (UNPREDICTABLE)")
						END
					END
				END
			ELSIF c DIV 800H = 9 THEN (* load from literal pool *)
				WStr("LDR "); WReg(c DIV 100H MOD 8); WStr(", [PC, #");
				WInt(c MOD 100H * 4); WStr("] ; "); WInt(c MOD 100H * 2)
			ELSIF (c DIV 1000H = 5) OR (c DIV 2000H IN {3,4}) THEN
					(* load/store single data item *)
				IF c DIV 200H = 28H THEN (* STRR *)
					WStr("STR "); WReg(c MOD 8); WStr(", ["); WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8); s[w] := ']'; INC(w)
				ELSIF c DIV 200H = 29H THEN (* STRHR *)
					WStr("STRH "); WReg(c MOD 8); WStr(", [");
					WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8); s[w] := ']'; INC(w)
				ELSIF c DIV 200H = 2AH THEN (* STRBR *)
					WStr("STRB "); WReg(c MOD 8); WStr(", [");
					WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8); s[w] := ']'; INC(w)
				ELSIF c DIV 200H = 2BH THEN (* LDRSBR *)
					WStr("LDRSB "); WReg(c MOD 8); WStr(", [");
					WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8); s[w] := ']'; INC(w)
				ELSIF c DIV 200H = 2CH THEN (* LDRR *)
					WStr("LDR "); WReg(c MOD 8); WStr(", ["); WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8); s[w] := ']'; INC(w)
				ELSIF c DIV 200H = 2DH THEN (* LDRHR *)
					WStr("LDRH "); WReg(c MOD 8); WStr(", [");
					WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8); s[w] := ']'; INC(w)
				ELSIF c DIV 200H = 2EH THEN (* LDRBR *)
					WStr("LDRB "); WReg(c MOD 8); WStr(", [");
					WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8); s[w] := ']'; INC(w)
				ELSIF c DIV 200H = 2FH THEN (* LDRSHR *)
					WStr("LDRSH "); WReg(c MOD 8); WStr(", [");
					WReg(c DIV 8 MOD 8);
					WStr(", "); WReg(c DIV 40H MOD 8); s[w] := ']'; INC(w)
				ELSIF c DIV 800H = 0CH THEN (* STRIm *)
					WStr("STR "); WReg(c MOD 8); WStr(", ["); WReg(c DIV 8 MOD 8);
					IF c DIV 40H MOD 32 # 0 THEN
						WStr(", #"); WInt(c DIV 40H MOD 32); WStr("] ; ");
						WInt(c DIV 40H MOD 32 * 4)
					ELSE s[w] := ']'; INC(w)
					END
				ELSIF c DIV 800H = 0DH THEN (* LDRIm *)
					WStr("LDR "); WReg(c MOD 8); WStr(", ["); WReg(c DIV 8 MOD 8);
					IF c DIV 40H MOD 32 # 0 THEN
						WStr(", #"); WInt(c DIV 40H MOD 32); WStr("] ; ");
						WInt(c DIV 40H MOD 32 * 4)
					ELSE s[w] := ']'; INC(w)
					END
				ELSIF c DIV 800H = 0EH THEN (* STRBIm *)
					WStr("STRB "); WReg(c MOD 8);
					WStr(", ["); WReg(c DIV 8 MOD 8);
					IF c DIV 40H MOD 32 # 0 THEN
						WStr(", #"); WInt(c DIV 40H MOD 32)
					END; s[w] := ']'; INC(w)
				ELSIF c DIV 800H = 0FH THEN (* LDRBIm *)
					WStr("LDRB "); WReg(c MOD 8);
					WStr(", ["); WReg(c DIV 8 MOD 8);
					IF c DIV 40H MOD 32 # 0 THEN
						WStr(", #"); WInt(c DIV 40H MOD 32)
					END; s[w] := ']'; INC(w)
				ELSIF c DIV 800H = 10H THEN (* STRHIm *)

				ELSIF c DIV 800H = 11H THEN (* LDRHIm *)

				ELSIF c DIV 800H = 12H THEN (* STRIm, SP *)
					WStr("STR "); WReg(c DIV 100H MOD 8); WStr(", [SP");
					IF c MOD 100H # 0 THEN WStr(", #");
						WInt(c MOD 100H); WStr("] ; "); WInt(c MOD 100H * 4)
					ELSE s[w] := ']'; INC(w)
					END
				ELSIF c DIV 800H = 13H THEN (* LDRIm, SP *)
					WStr("LDR "); WReg(c DIV 100H MOD 8); WStr(", [SP");
					IF c MOD 100H # 0 THEN WStr(", #");
						WInt(c MOD 100H); WStr("] ; "); WInt(c MOD 100H * 4)
					ELSE s[w] := ']'; INC(w)
					END
				END
			ELSIF c DIV 800H = 16 + 4 THEN (* ADR *)

			ELSIF c DIV 800H = 16 + 5 THEN (* ADDSPIm, encoding T1 *)
				WStr("ADD "); WReg(c DIV 100H MOD 8); WStr(", SP, #");
				WInt(c MOD 100H);
				IF c MOD 100H # 0 THEN
					WStr(" ; "); WInt(c MOD 100H * 4)
				END
			ELSIF c DIV 1000H = 0BH THEN (* miscellaneous 16-bit instructions *)
				c := c MOD 1000H;
				IF c DIV 80H = 0 THEN (* ADDSPIm, encoding T2 *)
					WStr("ADD SP, SP, #"); WInt(c MOD 80H);
					IF c MOD 80H # 0 THEN
						WStr(" ; "); WInt(c MOD 80H * 4)
					END
				ELSIF c DIV 80H = 1 THEN (* SUBSPIm *)
					WStr("SUB SP, SP, #"); WInt(c MOD 80H);
					IF c MOD 80H # 0 THEN
						WStr(" ; "); WInt(c MOD 80H * 4)
					END
				ELSIF c DIV 40H = 8 THEN (* SXTH *)

				ELSIF c DIV 40H = 9 THEN (* SXTB *)

				ELSIF c DIV 40H = 10 THEN (* UXTH *)

				ELSIF c DIV 40H = 11 THEN (* UXTB *)

				ELSIF c DIV 200H = 2 THEN (* PUSH *)
					WStr("PUSH {");
					a := 0; b := 0;
					WHILE a < 8 DO
						IF a IN BITS(c MOD 100H) THEN
							IF b # 0 THEN WStr(", ") END;
							WReg(a);
							INC(b)
						END;
						INC(a)
					END;
					IF ODD(c DIV 100H) THEN
						IF b # 0 THEN WStr(", ") END;
						WReg(LR);
						INC(b)
					END;
					s[w] := '}'; INC(w);
					IF b < 1 THEN
						WStr(" (UNPREDICTABLE)")
					END
				ELSIF c DIV 20H = 32 + 16 + 3 THEN (* CPS *)

				ELSIF c DIV 40H = 40 THEN (* REV *)

				ELSIF c DIV 40H = 41 THEN (* REV16 *)

				ELSIF c DIV 40H = 43 THEN (* REVSH *)

				ELSIF c DIV 200H = 6 THEN (* POP *)
					WStr("POP {");
					a := 0; b := 0;
					WHILE a < 8 DO
						IF a IN BITS(c MOD 100H) THEN
							IF b # 0 THEN WStr(", ") END;
							WReg(a);
							INC(b)
						END;
						INC(a)
					END;
					IF ODD(c DIV 100H) THEN
						IF b # 0 THEN WStr(", ") END;
						WReg(PC);
						INC(b)
					END;
					s[w] := '}'; INC(w);
					IF b < 1 THEN
						WStr(" (UNPREDICTABLE)")
					END
				ELSIF c DIV 100H = 14 THEN (* BKPT *)

				ELSIF c DIV 100H = 15 THEN (* hint instructions *)
					IF c MOD 10H # 0 THEN WStr("UNDEFINED")
					ELSE
						CASE c DIV 10H MOD 10H OF 0: WStr("NOP")
						| 1: WStr("YIELD")
						| 2: WStr("WFE")
						| 3: WStr("WFI")
						| 4: WStr("SEV")
						ELSE
						END
					END
				END
			ELSIF c DIV 800H = 16 + 8 THEN (* store multiple registers *)

			ELSIF c DIV 800H = 16 + 9 THEN (* load multiple registers *)

			ELSIF c DIV 1000H = 0DH THEN (* conditional branch, and SVC *)
				IF c DIV 100H MOD 10H = 15 THEN
					WStr("SVC #"); WInt(c MOD 100H)
				ELSIF c DIV 100H MOD 10H = 14 THEN
					WStr("UNDEFINED")
				ELSE s[w] := 'B'; INC(w);
					CondRepr(c DIV 100H MOD 10H, s0);
					WStr(s0); s[w] := ' '; INC(w);
					WInt((c * 1000000H) DIV 1000000H); WStr(" ; ");
					WInt((c * 1000000H) DIV 1000000H + 1)
				END
			ELSIF c DIV 800H = 16 + 12 THEN (* unconditional branch *)
				WStr("B "); WInt((c * 200000H) DIV 200000H);
				WStr(" ; "); WInt((c * 200000H) DIV 200000H + 1)
			ELSIF IsLThumb32(c) THEN (* 32-bit Thumb instruction *)
				d := 10000H + c;
				WStr("...")
			END
		ELSIF d DIV 10000H = 1 THEN
			c := 10000H * c + d MOD 10000H; d := 0;
			IF c DIV 800H MOD 2 = 1 THEN
				WStr("UNDEFINED")
			ELSIF 31 IN BITS(c) THEN (* branch and miscellaneous control *)
				a := DecodeBL(c);
				ASSERT(a MOD 2 = 0, 102);
				WStr("BL "); WInt(a);
				IF a # 0 THEN WStr(" ; "); WInt(a DIV 2) END
			ELSE
				WStr("UNDEFINED")
			END
		ELSE HALT(1)
		END;
		s[w] := 0X
	END OpcodeRepr;

END O7ARMv6M.
