MODULE O7ARMv7M;

	(*
		Alexander Shiryaev, 2015.01, 2019.11, 2020.08

		ARMv7-M Architecture Reference Manual
			https://web.eecs.umich.edu/~prabal/teaching/eecs373-f10/readings/ARMv7-M_ARM.pdf
	*)

	IMPORT SYSTEM, Strings := VT100, ARMv6M := O7ARMv6M;

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

	PROCEDURE LSL (x, n: INTEGER): INTEGER;
	BEGIN
		RETURN SYSTEM.LSH(x, n)
	END LSL;

	PROCEDURE BITS (x: INTEGER): SET;
	BEGIN
		RETURN SYSTEM.VAL(SET, x)
	END BITS;

	PROCEDURE ORDSET (x: SET): INTEGER;
	BEGIN
		RETURN SYSTEM.VAL(INTEGER, x)
	END ORDSET;

	PROCEDURE Emit2 (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; c: INTEGER);
	BEGIN
		code[pc] := c MOD 10000H; INC(pc);
		code[pc] := c DIV 10000H MOD 10000H; INC(pc)
	END Emit2;

	(* A5.3: emit 32-bit Thumb instruction *)
	(* 111 op1:2 op2:7 x0:4	op:1 x1:15 *)
	PROCEDURE EmitThumb2 (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op1, op2, x0, op, x1: INTEGER);
	BEGIN
		ASSERT(op1 IN {1,2,3}, 20);
		ASSERT(op2 >= 0, 21);
		ASSERT(op2 < 80H, 22);
		ASSERT(x0 IN {0..15}, 23);
		ASSERT(op IN {0,1}, 24);
		ASSERT(x1 >= 0, 25);
		ASSERT(x1 < 8000H, 26);
		Emit2(code, pc, LSL(op, 31) + x1 * 10000H + 0E000H + op1 * 800H + op2 * 10H + x0)
	END EmitThumb2;

	(* A5.3.5: emit Thumb-2 Load Multiple and Store Multiple instruction *)
	(* 111 0100 op:2 0 W:1 L:1 Rn:4	x0:16 *)
	PROCEDURE EmitLMASM (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op, W, L, Rn, x0: INTEGER);
	BEGIN
		ASSERT(op IN {1,2}, 20);
		ASSERT(W IN {0,1}, 21);
		ASSERT(L IN {0,1}, 22);
		ASSERT(Rn IN {0..15}, 23);
		ASSERT(x0 DIV 10000H = 0, 24);
		EmitThumb2(code, pc, 1, op * 8 + W * 2 + L, Rn, x0 DIV 8000H, x0 MOD 8000H)
	END EmitLMASM;

	(* A5.3.11: emit Thumb-2 data processing (shifted register) instruction *)
	(* 111 0101 op:4 S:1 Rn:4	x0:4 Rd:4 x1:8 *)
	PROCEDURE EmitDPSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op, S, Rn, x0, Rd, x1: INTEGER);
	BEGIN
		ASSERT(op IN {0..15}, 20);
		ASSERT(S IN {0,1}, 21);
		ASSERT(Rn IN {0..15}, 22);
		ASSERT(x0 IN {0..15}, 23);
		ASSERT(Rd IN {0..15}, 24);
		ASSERT(x1 >= 0, 25);
		ASSERT(x1 < 100H, 26);
		EmitThumb2(code, pc, 1, 20H + op * 2 + S, Rn, x0 DIV 8, x0 MOD 8 * 1000H + Rd * 100H + x1)
	END EmitDPSR;

		(* A7.7.114: ROR (immediate); encoding T1 ARMv7-M *)
		PROCEDURE EmitRORIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; S, Rd, Rm, im: INTEGER);
		BEGIN
			ASSERT(S DIV 2 = 0, 20);
			ASSERT(Rd IN {0..12,14}, 21);
			ASSERT(Rm IN {0..12,14}, 22);
			ASSERT(im IN {1..31}, 23);
			EmitDPSR(code, pc, 2, S, 0FH, im DIV 4, Rd, (im MOD 4) * 40H + 30H + Rm)
		END EmitRORIm;

	(* A5.3.1: emit Thumb-2 data processing (modified immediate) instruction *)
	(* 111 10 x0:1 0 op:5 Rn:4	0 x1:3 Rd:4 x2:8 *)
	PROCEDURE EmitDPMI* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; x0, op, Rn, x1, Rd, x2: INTEGER);
	BEGIN
		ASSERT(x0 IN {0,1}, 20);
		ASSERT(op IN {0..31}, 21);
		ASSERT(Rn IN {0..15}, 22);
		ASSERT(x1 IN {0..7}, 23);
		ASSERT(Rd IN {0..15}, 24);
		ASSERT(x2 >= 0, 25);
		ASSERT(x2 < 100H, 26);
		EmitThumb2(code, pc, 2, x0 * 40H + op, Rn, 0, x1 * 1000H + Rd * 100H + x2)
	END EmitDPMI;

		(* A7.7.185: TST (immediate); encoding T1 ARMv7-M *)
		PROCEDURE EmitTSTIm* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rn, i, imm3, imm8: INTEGER);
		BEGIN
			ASSERT(Rn IN {0..12,14}, 20);
			EmitDPMI(code, pc, i, 1, Rn, imm3, 0FH, imm8)
		END EmitTSTIm;

		(* A7.7.27: CMP (immediate); encoding T2 ARMv7-M *)
		PROCEDURE EmitCMPImW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rn, i, imm3, imm8: INTEGER);
		BEGIN
			ASSERT(Rn IN {0..14}, 20);
			EmitDPMI(code, pc, i, 16 + 8 + 2 + 1, Rn, imm3, 0FH, imm8)
		END EmitCMPImW;

		(* A7.7.117: RSB (immediate); encoding T2 ARMv7-M *)
		PROCEDURE EmitRSBImW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; S, Rd, Rn, i, imm3, imm8: INTEGER);
		BEGIN
			ASSERT(Rd IN {0..12,14}, 20);
			ASSERT(Rn IN {0..12,14}, 20);
			EmitDPMI(code, pc, i, 28 + S, Rn, imm3, Rd, imm8)
		END EmitRSBImW;

	(* A5.3.3: emit Thumb-2 data processing (plain binary immediate) instruction *)
	(* 111 10 x0:1 1 op:5 Rn:4	0 x1:15 *)
	PROCEDURE EmitDPPBI* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; x0, op, Rn, x1: INTEGER);
	BEGIN
		ASSERT(x0 IN {0,1}, 20);
		ASSERT(op IN {0..31}, 21);
		ASSERT(Rn IN {0..15}, 22);
		ASSERT(x1 >= 0, 23);
		ASSERT(x1 < 8000H, 24);
		EmitThumb2(code, pc, 2, x0 * 40H + 20H + op, Rn, 0, x1)
	END EmitDPPBI;

	(* A5.3.12: emit Thumb-2 data processing (register) instruction *)
	(* 111 1101 0 op1:4 Rn:4	1111 x0:4 op2:4 x1:4 *)
	PROCEDURE EmitDPR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op1, Rn, x0, op2, x1: INTEGER);
	BEGIN
		ASSERT(op1 IN {0..15}, 20);
		ASSERT(Rn IN {0..15}, 21);
		ASSERT(x0 IN {0..15}, 22);
		ASSERT(op2 IN {0..15}, 23);
		ASSERT(x1 IN {0..15}, 24);
		EmitThumb2(code, pc, 3, 20H + op1, Rn, 1, 7000H + x0 * 100H + op2 * 10H + x1)
	END EmitDPR;

	(* A5.3.16: Multiply, multiply accumulate, and absolute difference *)
	PROCEDURE EmitMMAAAD* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op1, x0, Ra, x1, op2, x2: INTEGER);
	BEGIN
		ASSERT(op1 IN {0..7}, 20);
		ASSERT(x0 IN {0..15}, 21);
		ASSERT(Ra IN {0..15}, 22);
		ASSERT(x1 IN {0..15}, 23);
		ASSERT(op2 IN {0..3}, 24);
		ASSERT(x2 IN {0..15}, 25);
		EmitThumb2(code, pc, 3, 30H + op1, x0, Ra DIV 8, Ra MOD 8 * 1000H + x1 * 100H + op2 * 10H + x2)
	END EmitMMAAAD;

		(* A7.7.73: MLA; encoding T1 ARMv7-M *)
		PROCEDURE EmitMLA* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rd, Rn, Rm, Ra: INTEGER);
		BEGIN
			ASSERT(Rd IN {0..12,14}, 20);
			ASSERT(Rn IN {0..12,14}, 21);
			ASSERT(Rm IN {0..12,14}, 22);
			ASSERT(Ra IN {0..12,14}, 23);
			EmitMMAAAD(code, pc, 0, Rn, Ra, Rd, 0, Rm)
		END EmitMLA;

		(* A7.7.74: MLS; encoding T1 ARMv7-M *)
		PROCEDURE EmitMLS* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rd, Rn, Rm, Ra: INTEGER);
		BEGIN
			ASSERT(Rd IN {0..12,14}, 20);
			ASSERT(Rn IN {0..12,14}, 21);
			ASSERT(Rm IN {0..12,14}, 22);
			ASSERT(Ra IN {0..12,14}, 23);
			EmitMMAAAD(code, pc, 0, Rn, Ra, Rd, 1, Rm)
		END EmitMLS;

		(* A7.7.83: MUL; encoding T2 ARMv7-M *)
		PROCEDURE EmitMUL* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rd, Rn, Rm: INTEGER);
		BEGIN
			ASSERT(Rd IN {0..12,14}, 20);
			ASSERT(Rn IN {0..12,14}, 21);
			ASSERT(Rm IN {0..12,14}, 22);
			EmitMMAAAD(code, pc, 0, Rn, 0FH, Rd, 0, Rm)
		END EmitMUL;

	(* A5.3.15: Long multiply, long multiply accumulate, and divide *)
	PROCEDURE EmitLMLMAAD* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op1, x0, x1, op2, x2: INTEGER);
	BEGIN
		ASSERT(op1 IN {0..7}, 20);
		ASSERT(x0 IN {0..15}, 21);
		ASSERT(x1 >= 0, 22);
		ASSERT(x1 < 100H, 23);
		ASSERT(op2 IN {0..15}, 24);
		ASSERT(x2 IN {0..15}, 25);
		EmitThumb2(code, pc, 3, 38H + op1, x0, x1 DIV 80H, x1 MOD 80H * 100H + op2 * 10H + x2)
	END EmitLMLMAAD;

	(* A5.3.7: emit Thumb-2 load word instruction *)
	(* 111 1100 op1:2 10 1 Rn:4  x0:4 op2:6 x1:6 *)
	PROCEDURE EmitLW (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op1, Rn, x0, op2, x1: INTEGER);
	BEGIN
		ASSERT(op1 IN {0..3}, 20);
		ASSERT(Rn IN {0..15}, 21);
		ASSERT(x0 IN {0..15}, 22);
		ASSERT(op2 >= 0, 23);
		ASSERT(op2 < 40H, 24);
		ASSERT(x1 >= 0, 25);
		ASSERT(x1 < 40H, 26);
		EmitThumb2(code, pc, 3, op1 * 8 + 5, Rn, x0 DIV 8, x0 MOD 8 * 1000H + op2 * 40H + x1)
	END EmitLW;

		(* A7.7.42: LDR (immediate); encoding T3 ARMv7-M *)
		PROCEDURE EmitLWImW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, imm12: INTEGER);
		BEGIN
			ASSERT(Rn IN {0..14}, 20);
			ASSERT(Rt IN {0..14}, 21);
			ASSERT(imm12 >= 0, 22);
			ASSERT(imm12 < 1000H, 23);
			EmitLW(code, pc, 1, Rn, Rt, imm12 DIV 40H, imm12 MOD 40H)
		END EmitLWImW;

		(* A7.7.42: LDR (immediate); encoding T4 ARMv7-M *)
		PROCEDURE EmitLWImWT4 (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, imm8, P, U, W: INTEGER);
		BEGIN
			ASSERT(Rn IN {0..14}, 20);
			ASSERT(Rt IN {0..15}, 21);
			ASSERT(imm8 DIV 100H = 0, 22);
			ASSERT(P DIV 2 = 0, 23);
			ASSERT(U DIV 2 = 0, 24);
			ASSERT(W DIV 2 = 0, 25);
			ASSERT(~((P = 1) & (U = 1) & (W = 0)), 26);
			ASSERT(~((Rn = 13) & (P = 0) & (U = 1) & (W = 1) & (imm8 = 4)), 27);
			ASSERT(~((P = 0) & (W = 0)), 28);
			EmitLW(code, pc, 0, Rn, Rt, imm8 DIV 40H + W * 4 + U * 8 + P * 16 + 32, imm8 MOD 40H)
		END EmitLWImWT4;

		PROCEDURE EmitLWImWNeg* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, imm8: INTEGER);
		BEGIN
			EmitLWImWT4(code, pc, Rt, Rn, imm8, 1, 0, 0)
		END EmitLWImWNeg;

		(* A7.7.44: LDR (register); encoding T2 ARMv7-M *)
		PROCEDURE EmitLWRW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, Rm, imm2: INTEGER);
		BEGIN
			ASSERT(Rt IN {0..15}, 20);
			ASSERT(Rn IN {0..14}, 21);
			ASSERT(Rm IN {0..12,14}, 22);
			ASSERT(imm2 DIV 4 = 0, 23);
			EmitLW(code, pc, 0, Rn, Rt, 0, imm2 * 10H + Rm)
		END EmitLWRW;

	(* A5.3.: emit Thumb-2 load byte, memory hints instruction *)
	(* 111 1100 op1:2 00 1 Rn:4  Rt:4 op2:6 x0:6 *)
	PROCEDURE EmitLBMH (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op1, Rn, Rt, op2, x0: INTEGER);
	BEGIN
		ASSERT(op1 IN {0..3}, 20);
		ASSERT(Rn IN {0..15}, 21);
		ASSERT(Rt IN {0..15}, 22);
		ASSERT(op2 >= 0, 23);
		ASSERT(op2 < 40H, 24);
		ASSERT(x0 >= 0, 25);
		ASSERT(x0 < 40H, 26);
		EmitThumb2(code, pc, 3, op1 * 8 + 1, Rn, Rt DIV 8, Rt MOD 8 * 1000H + op2 * 40H + x0)
	END EmitLBMH;

		(* A7.7.45: LDRB (immediate); encoding T2 ARMv7-M *)
		PROCEDURE EmitLBImW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, imm12: INTEGER);
		BEGIN
			ASSERT(Rt IN {0..12,14}, 20);
			ASSERT(Rn IN {0..14}, 21);
			ASSERT(imm12 >= 0, 22);
			ASSERT(imm12 < 1000H, 23);
			EmitLBMH(code, pc, 1, Rn, Rt, imm12 DIV 40H, imm12 MOD 40H)
		END EmitLBImW;

		(* A7.7.47: LDRB (register); encoding T2 ARMv7-M *)
		PROCEDURE EmitLBRW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, Rm, imm2: INTEGER);
		BEGIN
			ASSERT(Rt IN {0..12,14}, 20);
			ASSERT(Rn IN {0..14}, 21);
			ASSERT(Rm IN {0..12,14}, 22);
			ASSERT(imm2 DIV 4 = 0, 23);
			EmitLBMH(code, pc, 0, Rn, Rt, 0, imm2 * 10H + Rm)
		END EmitLBRW;

	(* A5.3.10: emit Thumb-2 store single data item instruction *)
	(* 111 1100 0 op1:3 0 x0:4  x1:4 op2:6 x2:6 *)
	PROCEDURE EmitSSDI (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op1, x0, x1, op2, x2: INTEGER);
	BEGIN
		ASSERT(op1 IN {0..7}, 20);
		ASSERT(x0 IN {0..15}, 21);
		ASSERT(x1 IN {0..15}, 22);
		ASSERT(op2 >= 0, 23);
		ASSERT(op2 < 40H, 24);
		ASSERT(x2 >= 0, 25);
		ASSERT(x2 < 40H, 26);
		EmitThumb2(code, pc, 3, op1 * 2, x0, x1 DIV 8, x1 MOD 8 * 1000H + op2 * 40H + x2)
	END EmitSSDI;

		(* A7.7.160: STRB (immediate); encoding T2 ARMv7-M *)
		PROCEDURE EmitSBImW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, imm12: INTEGER);
		BEGIN
			ASSERT(Rt IN {0..12,14}, 20);
			ASSERT(Rn IN {0..14}, 21);
			ASSERT(imm12 >= 0, 110);
			ASSERT(imm12 < 1000H, 111);
			EmitSSDI(code, pc, 4, Rn, Rt, imm12 DIV 40H, imm12 MOD 40H)
		END EmitSBImW;

		(* A7.7.161: STRB (register); encoding T2 ARMv7-M *)
		PROCEDURE EmitSBRW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, Rm, imm2: INTEGER);
		BEGIN
			ASSERT(Rt IN {0..12,14}, 20);
			ASSERT(Rn IN {0..14}, 21);
			ASSERT(Rm IN {0..12,14}, 22);
			ASSERT(imm2 IN {0..3}, 23);
			EmitSSDI(code, pc, 0, Rn, Rt, 0, imm2 * 10H + Rm)
		END EmitSBRW;

		(* A7.7.158: STR (immediate); encoding T3 ARMv7-M *)
		PROCEDURE EmitSWImW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, imm12: INTEGER);
		BEGIN
			ASSERT(Rt IN {0..14}, 20);
			ASSERT(Rn IN {0..14}, 21);
			ASSERT(imm12 >= 0, 110);
			ASSERT(imm12 < 1000H, 111);
			EmitSSDI(code, pc, 6, Rn, Rt, imm12 DIV 40H, imm12 MOD 40H)
		END EmitSWImW;

		(* A7.7.159: STR (register); encoding T2 ARMv7-M *)
		PROCEDURE EmitSWRW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt, Rn, Rm, imm2: INTEGER);
		BEGIN
			ASSERT(Rt IN {0..14}, 20);
			ASSERT(Rn IN {0..14}, 21);
			ASSERT(Rm IN {0..12,14}, 22);
			ASSERT(imm2 IN {0..3}, 23);
			EmitSSDI(code, pc, 2, Rn, Rt, 0, imm2 * 10H + Rm)
		END EmitSWRW;

	(* A7.7.79: PUSH *)
	PROCEDURE EmitPUSHW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; regs: SET);
		VAR i, n, r: INTEGER;
	BEGIN
		ASSERT(regs * {13,15..31} = {}, 20);
		ASSERT(regs # {}, 21);
		i := 16; n := 0;
		REPEAT DEC(i); IF i IN regs THEN INC(n); r := i END UNTIL i = 0;
		IF n = 1 THEN (* encoding T3 ARMv7-M *)
			EmitSSDI(code, pc, 2, 13, r, 32 + 16 + 4, 4)
		ELSE (* encoding T2 ARMv7-M *)
			EmitLMASM(code, pc, 2, 1, 0, 13, ORDSET(regs))
		END
	END EmitPUSHW;

	(* A7.7.98: POP *)
	PROCEDURE EmitPOPW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; regs: SET);
		VAR i, n, r: INTEGER;
	BEGIN
		ASSERT(regs * {13,16..31} = {}, 20);
		ASSERT(regs # {}, 21);
		i := 16; n := 0;
		REPEAT DEC(i); IF i IN regs THEN INC(n); r := i END UNTIL i = 0;
		IF n = 1 THEN (* encoding T3 ARMv7-M *)
			EmitLW(code, pc, 0, 13, r, 32 + 8 + 4, 4)
		ELSE (* encoding T2 ARMv7-M *)
			EmitLMASM(code, pc, 1, 1, 1, 13, ORDSET(regs))
		END
	END EmitPOPW;

	PROCEDURE DecodeBLabel20 (S, imm6, J1, J2, imm11: INTEGER): INTEGER;
	BEGIN
		RETURN ((S * 100000H + J2 * 80000H + J1 * 40000H + imm6 * 1000H + imm11 * 2) * 800H) DIV 800H
	END DecodeBLabel20;

	PROCEDURE EncodeBLabel20* (off: INTEGER; (*OUT*)VAR S, imm6, J1, J2, imm11: INTEGER);
		VAR test: INTEGER;
	BEGIN
		ASSERT(off * 2 >= -1048576, 21);
		ASSERT(off * 2 <= 1048574, 22);
		imm11 := off MOD 800H;
		imm6 := off DIV 800H MOD 40H;
		S := off DIV 80000H MOD 2;
		J2 := off DIV 40000H MOD 2;
		J1 := off DIV 20000H MOD 2;

		off := off * 2;
		test := DecodeBLabel20(S, imm6, J1, J2, imm11);
		ASSERT(off = test, 100)
	END EncodeBLabel20;

	(* A5.3.4: emit Thumb-2 branch and miscellaneous control instruction *)
	(* 111 10 op:7 x0:4  1 op1:3 x1:12 *)
	PROCEDURE EmitBAMC* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op, x0, op1, x1: INTEGER);
	BEGIN
		ASSERT(op >= 0, 20);
		ASSERT(op < 80H, 21);
		ASSERT(x0 IN {0..15}, 22);
		ASSERT(op1 IN {0..7}, 23);
		ASSERT(x1 >= 0, 24);
		ASSERT(x1 < 1000H, 25);
		EmitThumb2(code, pc, 2, op, x0, 1, op1 * 1000H + x1)
	END EmitBAMC;

	(* A7.7.236: emit VMOV (between ARM core register and single-precision register) instruction; encoding T1 FPv4-SP *)
	PROCEDURE EmitVMOVSPR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; op, n, t: INTEGER);
	BEGIN
		ASSERT(op IN {0,1}, 20);
		ASSERT(n IN {0..31}, 21);
		ASSERT(t IN {0..12,14}, 22);
		Emit2(code, pc, 0A10EE00H + op * 10H + n DIV 2 + n MOD 2 * 800000H + t * 10000000H)
	END EmitVMOVSPR;

	(* A7.7.239: emit VMRS instruction; encoding T1 FPv4-SP *)
	PROCEDURE EmitVMRS* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt: INTEGER);
	BEGIN
		ASSERT(Rt IN {0..12,14,15}, 20);
		Emit2(code, pc, 0A10EEF1H + Rt * 10000000H)
	END EmitVMRS;

	(* A7.7.240: emit VMSR instruction; encoding T1 FPv4-SP *)
	PROCEDURE EmitVMSR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Rt: INTEGER);
	BEGIN
		ASSERT(Rt IN {0..12,14}, 20);
		Emit2(code, pc, 0A10EEE1H + Rt * 10000000H)
	END EmitVMSR;

	(* A6.4: emit Floating-point data-processing instruction *)
	(* 111 0 1110 opc1:4 opc2:4	x0:4 101 0 opc3:2 x1:1 0 opc4:4 *)
	PROCEDURE EmitFPDP (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; opc1, opc2, x0, opc3, x1, opc4: INTEGER);
	BEGIN
		ASSERT(opc1 IN {0..15}, 20);
		ASSERT(opc2 IN {0..15}, 21);
		ASSERT(x0 IN {0..15}, 22);
		ASSERT(opc3 IN {0..3}, 23);
		ASSERT(x1 IN {0,1}, 24);
		ASSERT(opc4 IN {0..15}, 25);
		Emit2(code, pc, 0A00EE00H + opc1 * 10H + opc2 + x0 * 10000000H + opc3 * 400000H + x1 * 200000H + opc4 * 10000H)
	END EmitFPDP;

		(* A7.7.241: emit VMUL instruction; encoding T1 FPv4-SP *)
		PROCEDURE EmitVMUL* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Sd, Sn, Sm: INTEGER);
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Sn IN {0..31}, 21);
			ASSERT(Sm IN {0..31}, 22);
			EmitFPDP(code, pc, 2 + Sd MOD 2 * 4, Sn DIV 2, Sd DIV 2, Sn MOD 2 * 2, Sm MOD 2, Sm DIV 2)
		END EmitVMUL;

		(* A7.7.221: emit VADD instruction; encoding T1 FPv4-SP *)
		PROCEDURE EmitVADD* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Sd, Sn, Sm: INTEGER);
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Sn IN {0..31}, 21);
			ASSERT(Sm IN {0..31}, 22);
			EmitFPDP(code, pc, 3 + Sd MOD 2 * 4, Sn DIV 2, Sd DIV 2, Sn MOD 2 * 2, Sm MOD 2, Sm DIV 2)
		END EmitVADD;

		(* A7.7.249: emit VSUB instruction; encoding T1 FPv4-SP *)
		PROCEDURE EmitVSUB* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Sd, Sn, Sm: INTEGER);
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Sn IN {0..31}, 21);
			ASSERT(Sm IN {0..31}, 22);
			EmitFPDP(code, pc, 3 + Sd MOD 2 * 4, Sn DIV 2, Sd DIV 2, Sn MOD 2 * 2 + 1, Sm MOD 2, Sm DIV 2)
		END EmitVSUB;

		(* A7.7.226: emit VDIV instruction; encoding T1 FPv4-SP *)
		PROCEDURE EmitVDIV* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Sd, Sn, Sm: INTEGER);
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Sn IN {0..31}, 21);
			ASSERT(Sm IN {0..31}, 22);
			EmitFPDP(code, pc, 8 + Sd MOD 2 * 4, Sn DIV 2, Sd DIV 2, Sn MOD 2 * 2, Sm MOD 2, Sm DIV 2)
		END EmitVDIV;

		(* A7.7.220: emit VABS instruction; encoding T1 FPv4-SP *)
		PROCEDURE EmitVABS* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Sd, Sm: INTEGER);
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Sm IN {0..31}, 21);
			EmitFPDP(code, pc, 11 + Sd MOD 2 * 4, 0, Sd DIV 2, 3, Sm MOD 2, Sm DIV 2)
		END EmitVABS;

		(* A7.7.242: emit VNEG instruction; encoding T1 FPv4-SP *)
		PROCEDURE EmitVNEG* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Sd, Sm: INTEGER);
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Sm IN {0..31}, 21);
			EmitFPDP(code, pc, 11 + Sd MOD 2 * 4, 1, Sd DIV 2, 1, Sm MOD 2, Sm DIV 2)
		END EmitVNEG;

		(* A7.7.246: emit VSQRT instruction; encoding T1 FPv4-SP *)
		PROCEDURE EmitVSQRT* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Sd, Sm: INTEGER);
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Sm IN {0..31}, 21);
			EmitFPDP(code, pc, 11 + Sd MOD 2 * 4, 1, Sd DIV 2, 3, Sm MOD 2, Sm DIV 2)
		END EmitVSQRT;

		(* A7.7.222: emit VCMP{E} instruction; encoding T1 FPv4-SP *)
		PROCEDURE EmitVCMPER* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; E, Sd, Sm: INTEGER);
		BEGIN
			ASSERT(E IN {0,1}, 20);
			ASSERT(Sd IN {0..31}, 21);
			ASSERT(Sm IN {0..31}, 22);
			EmitFPDP(code, pc, 11 + Sd MOD 2 * 4, 4, Sd DIV 2, E * 2 + 1, Sm MOD 2, Sm DIV 2)
		END EmitVCMPER;

		(* A7.7.222: emit VCMP{E} instruction; encoding T2 FPv4-SP *)
		PROCEDURE EmitVCMPE0* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; E, Sd: INTEGER);
		BEGIN
			ASSERT(E IN {0,1}, 20);
			ASSERT(Sd IN {0..31}, 21);
			EmitFPDP(code, pc, 11 + Sd MOD 2 * 4, 5, Sd DIV 2, E * 2 + 1, 0, 0)
		END EmitVCMPE0;

		(* A7.7.223: emit VCVT, VCVTR (between floating-point and integer) instruction; encoding T1 FPv4-SP *)
		PROCEDURE EmitVCVTRInt* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; toInteger, R, signed: BOOLEAN; Sd, Sm: INTEGER);
			VAR opc2, op: INTEGER;
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Sm IN {0..31}, 21);
			IF toInteger THEN
				IF signed THEN opc2 := 5 ELSE opc2 := 4 END;
				IF R THEN op := 0 ELSE op := 1 END
			ELSE
				ASSERT(~R, 22);
				opc2 := 0;
				IF signed THEN op := 1 ELSE op := 0 END
			END;
			EmitFPDP(code, pc, 11 + Sd MOD 2 * 4, 8 + opc2, Sd DIV 2, op * 2 + 1, Sm MOD 2, Sm DIV 2)
		END EmitVCVTRInt;

	(* A6.5: emit Floating-point extension register load and store instruction *)
	(* 111 0 110 opcode:5 Rn:4	x0:4 101 x1:9 *)
	PROCEDURE EmitFPERLOS (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; opcode, Rn, x0, x1: INTEGER);
	BEGIN
		ASSERT(opcode DIV 32 = 0, 20);
		ASSERT(Rn DIV 16 = 0, 21);
		ASSERT(x0 DIV 16 = 0, 22);
		ASSERT(x1 DIV 200H = 0, 23);
		Emit2(code, pc, 0A00EC00H + Rn + opcode * 10H + x1 * 10000H + x0 * 10000000H)
	END EmitFPERLOS;

		(* A7.7.248: emit VSTR instruction; encoding T2 FPv4-SP *)
		PROCEDURE EmitVSTR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Sd, Rn, U, imm8: INTEGER);
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Rn IN {0..14}, 21);
			ASSERT(U IN {0,1}, 22);
			ASSERT(imm8 DIV 100H = 0, 23);
			EmitFPERLOS(code, pc, 16 + U * 8 + Sd MOD 2 * 4, Rn, Sd DIV 2, imm8)
		END EmitVSTR;

		(* A7.7.230: emit VLDR instruction; encoding T2 FPv4-SP *)
		PROCEDURE EmitVLDR* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER; Sd, Rn, U, imm8: INTEGER);
		BEGIN
			ASSERT(Sd IN {0..31}, 20);
			ASSERT(Rn IN {0..15}, 21);
			ASSERT(U IN {0,1}, 22);
			ASSERT(imm8 DIV 100H = 0, 23);
			EmitFPERLOS(code, pc, 16 + U * 8 + Sd MOD 2 * 4 + 1, Rn, Sd DIV 2, imm8)
		END EmitVLDR;

	(* try to encode to 12-bit modified immediate *)
	PROCEDURE EncodeMI12* (x: INTEGER; (*OUT*)VAR i, imm3, imm8: INTEGER; (*OUT*)VAR ok: BOOLEAN);
		VAR j, y: INTEGER; imm12: INTEGER;
	BEGIN
		IF x DIV 100H = 0 THEN
			imm12 := x;
			ok := TRUE
		ELSIF (x MOD 10000H DIV 100H = 0) & (x DIV 10000H MOD 10000H = x MOD 10000H) THEN
			imm12 := 100H + x MOD 100H;
			ok := TRUE
		ELSIF (x MOD 100H = 0) & (x DIV 10000H MOD 10000H = x MOD 10000H) THEN
			imm12 := 200H + x DIV 100H MOD 100H;
			ok := TRUE
		ELSIF (x MOD 100H = x DIV 100H MOD 100H) & (x MOD 100H = x DIV 10000H MOD 100H) & (x MOD 100H = x DIV 1000000H MOD 100H) THEN
			imm12 := 300H + x MOD 100H;
			ok := TRUE
		ELSE
			j := 0; y := x;
			WHILE (j < 24) & ~((31 IN BITS(y)) & (y MOD 1000000H = 0)) DO
				INC(j); y := SYSTEM.ROT(x, j)
			END;
			IF j < 24 THEN
				imm12 := (j + 8) * 80H + y DIV 1000000H MOD 80H;
				ok := TRUE
			ELSE
				ok := FALSE
			END
		END;
		IF ok THEN
			i := imm12 DIV 800H;
			imm3 := imm12 DIV 100H MOD 8;
			imm8 := imm12 MOD 100H
		END
	END EncodeMI12;

	(* A5.4.2 *)
	PROCEDURE DecodeMI12 (i, imm3, imm8: INTEGER; (*OUT*)VAR im: INTEGER; (*OUT*)VAR ok: BOOLEAN);
		VAR imm12: INTEGER;
	BEGIN
		ASSERT(i IN {0,1}, 20);
		ASSERT(imm3 IN {0..7}, 21);
		ASSERT(imm8 >= 0, 22);
		ASSERT(imm8 < 100H, 23);
		imm12 := i * 800H + imm3 * 100H + imm8;
		IF imm12 DIV 400H = 0 THEN
			CASE imm12 DIV 100H MOD 4 OF 0:
				im := imm8; ok := TRUE
			| 1:
				IF imm8 = 0 THEN ok := FALSE
				ELSE im := imm8 * 10000H + imm8; ok := TRUE
				END
			| 2:
				IF imm8 = 0 THEN ok := FALSE
				ELSE im := imm8 * 1000000H + imm8 * 100H; ok := TRUE
				END
			| 3:
				IF imm8 = 0 THEN ok := FALSE
				ELSE im := imm8 * 1000000H + imm8 * 10000H + imm8 * 100H + imm8; ok := TRUE
				END
			END
		ELSE
			im := 80H + imm8 MOD 80H;
			im := SYSTEM.ROT(im, -(imm12 DIV 80H));
			ok := TRUE
		END
	END DecodeMI12;

	(* A5.3 *)
	PROCEDURE IsLMASM (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {6,9..15} = {11,13..15}
	END IsLMASM;

		(* A7.7.79: PUSH; encoding T2 *)
		PROCEDURE IsPUSHMany (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..15,29,31} = {0,2,3,5,8,11,13..15}
		END IsPUSHMany;

		(* A7.7.98: POP; encoding T2 *)
		PROCEDURE IsPOPMany (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..15,29} = {0,2..5,7,11,13..15}
		END IsPOPMany;

	(* A7.7.79: PUSH; encoding T3 *)
	PROCEDURE IsPUSHOne (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {0..27} = {0,2,3,6,11..15,18,24,26,27}
	END IsPUSHOne;

	(* A7.7.98: POP; encoding T3 *)
	PROCEDURE IsPOPOne (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {0..27} = {0,2..4,6,11..15,18,24,25,27}
	END IsPOPOne;

	(* A5.3 *)
	PROCEDURE IsDPSR (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {9..15} = {9,11,13..15}
	END IsDPSR;

		(* A7.7.85: MVN (register); encoding T2 *)
		PROCEDURE IsMVNR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..3,5..15,31} = {0..3,5,6,9,11,13..15}
		END IsMVNR;

		(* A7.7.76: MOVR (register); encoding T3 *)
		PROCEDURE IsMOVR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..3,5..15,20..23,28..31} = {0..3,6,9,11,13..15}
		END IsMOVR;

		(* A7.7.9: AND (register); encoding T2 *)
		PROCEDURE IsANDR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..15,31} = {9,11,13..15}) & ~((BITS(c) * {24..27} = {24..27}) & (4 IN BITS(c)))
		END IsANDR;

		(* A7.7.16: BIC (register); encoding T2 *)
		PROCEDURE IsBICR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..15,31} = {5,9,11,13..15}
		END IsBICR;

		(* A7.7.91: ORR (register); encoding T2 *)
		PROCEDURE IsORRR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..15,31} = {6,9,11,13..15}) & (BITS(c) * {0..3} # {0..3})
		END IsORRR;

		(* A7.7.25: EOR (register); encoding T2 *)
		PROCEDURE IsEORR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..15,31} = {7,9,11,13..15}) & ~((BITS(c) * {24..27} = {24..27}) & (4 IN BITS(c)))
		END IsEORR;

		(* A7.7.4: ADD (register); encoding T3 *)
		PROCEDURE IsADDR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..15,31} = {8,9,11,13..15}) & ~((BITS(c) * {24..27} = {24..27}) & (4 IN BITS(c))) & (BITS(c) * {0,2,3} # {0,2,3})
		END IsADDR;

		(* A7.7.6: ADD (SP plus register); encoding T3 *)
		PROCEDURE IsADDSPR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..3,5..15,31} = {0,2,3,8,9,11,13..15}
		END IsADDSPR;

		(* A7.7.2: ADC (register); encoding T2 *)
		PROCEDURE IsADCR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..15,31} = {6,8,9,11,13..15}
		END IsADCR;

		(* A7.7.172: SUB (register); encoding T2 *)
		PROCEDURE IsSUBR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..15,31} = {5,7..9,11,13..15}) & ~((BITS(c) * {24..27} = {24..27}) & (4 IN BITS(c))) & (BITS(c) * {0,2,3} # {0,2,3})
		END IsSUBR;

		(* A7.7.174: SUB (SP minus register); encoding T1 *)
		PROCEDURE IsSUBSPR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..3,5..15,31} = {0,2,3,5,7..9,11,13..15}
		END IsSUBSPR;

		(* A7.7.123: SBC (register); encoding T2 *)
		PROCEDURE IsSBCR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..15,31} = {5,6,8,9,11,13..15}
		END IsSBCR;

		(* A7.7.67: LSL (immediate); encoding T2 *)
		PROCEDURE IsLSLIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {0..3,5..15,20,21,31} = {0..3,6,9,11,13..15}) & (BITS(c) * {22,23,28..30} # {})
		END IsLSLIm;

		(* A7.7.10: ASR (immediate); encoding T2 *)
		PROCEDURE IsASRIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..3,5..15,20,21,31} = {0..3,6,9,11,13..15,21}
		END IsASRIm;

		(* A7.7.114: ROR (immediate); encoding T1 *)
		PROCEDURE IsRORIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {0..3,5..15,20,21,31} = {0..3,6,9,11,13..15,20,21}) & (BITS(c) * {22,23,28..30} # {})
		END IsRORIm;

	(* A5.3 *)
	PROCEDURE IsDPMI (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {9,11..15,31} = {12..15}
	END IsDPMI;

		(* A7.7.185: TST (immediate), encoding T1 *)
		PROCEDURE IsTSTIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4..9,11..15,24..27,31} = {4,12..15,24..27}
		END IsTSTIm;

		(* A7.7.75: MOV (immediate), encoding T2 *)
		PROCEDURE IsMOVMI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..3,5..9,11..15,31} = {0..3,6,12..15}
		END IsMOVMI;

		(* A7.7.84: MVN (immediate), encoding T1 *)
		PROCEDURE IsMVNIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..3,5..9,11..15,31} = {0..3,5,6,12..15}
		END IsMVNIm;

		(* A7.7.8: AND (immediate), encoding T1 *)
		PROCEDURE IsANDIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..9,11..15,31} = {12..15}
		END IsANDIm;

		(* A7.7.90: ORR (immediate), encoding T1 *)
		PROCEDURE IsORRIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..9,11..15,31} = {6,12..15}) & (BITS(c) * {0..3} # {0..3})
		END IsORRIm;

		(* A7.7.15: BIC (immediate), encoding T1 *)
		PROCEDURE IsBICIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..9,11..15,31} = {5,12..15}
		END IsBICIm;

		(* A7.7.88: ORN (immediate), encoding T1 *)
		PROCEDURE IsORNIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..9,11..15,31} = {5,6,12..15}) & (BITS(c) * {0..3} # {0..3})
		END IsORNIm;

		(* A7.7.34: EOR (immediate), encoding T1 *)
		PROCEDURE IsEORIm (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..9,11..15,31} = {7,12..15}) & ~((BITS(c) * {24..27} = {24..27}) & (4 IN BITS(c)))
		END IsEORIm;

		(* A7.7.3: ADD (immediate), encoding T3 *)
		PROCEDURE IsADDMI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..9,11..15,31} = {8,12..15}) & ~((BITS(c) * {24..27} = {24..27}) & (4 IN BITS(c))) & (BITS(c) * {0..3} # {0,2,3})
		END IsADDMI;

		(* A7.7.5: ADD (SP plus immediate), encoding T3 *)
		PROCEDURE IsADDSPMI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {0..3,5..9,11..15,31} = {0,2,3,8,12..15}) & ~((BITS(c) * {24..27} = {24..27}) & (4 IN BITS(c)))
		END IsADDSPMI;

		(* A7.7.171: SUB (immediate), encoding T3 *)
		PROCEDURE IsSUBMI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {5..9,11..15,31} = {5,7,8,12..15}) & ~((BITS(c) * {24..27} = {24..27}) & (4 IN BITS(c))) & (BITS(c) * {0..3} # {0,2,3})
		END IsSUBMI;

		(* A7.7.173: SUB (SP minus immediate), encoding T2 *)
		PROCEDURE IsSUBSPMI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {0..3,5..9,11..15,31} = {0,2,3,5,7,8,12..15}) & ~((BITS(c) * {24..27} = {24..27}) & (4 IN BITS(c)))
		END IsSUBSPMI;

		(* A7.7.27: CMP (immediate), encoding T2 *)
		PROCEDURE IsCMPImW* (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4..9,11..15,24..27,31} = {4,5,7,8,12..15,24..27}
		END IsCMPImW;

		(* A7.7.117: RSB (immediate), encoding T2 *)
		PROCEDURE IsRSBImW (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..9,11..15,31} = {6..8,12..15}
		END IsRSBImW;

	(* A5.3 *)
	PROCEDURE IsDPPBI (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {9,11..15,31} = {9,12..15}
	END IsDPPBI;

		(* A7.7.75: MOV (immediate), encoding T3 *)
		PROCEDURE IsMOVPBI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4..9,11..15,31} = {6,9,12..15}
		END IsMOVPBI;

		(* A7.7.75: MOVT, encoding T1 *)
		PROCEDURE IsMOVT (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4..9,11..15,31} = {6,7,9,12..15}
		END IsMOVT;

		(* A7.7.3: ADD (immediate), encoding T4 *)
		PROCEDURE IsADDPBI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..9,11..15,31} = {9,12..15}) & (BITS(c) * {0..3} # {0..3}) & (BITS(c) * {0..3} # {0,2,3})
		END IsADDPBI;

		(* A7.7.5: ADD (SP plus immediate), encoding T4 *)
		PROCEDURE IsADDSPPBI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..9,11..15,31} = {0,2,3,9,12..15}
		END IsADDSPPBI;

		(* A7.7.171: SUB (immediate), encoding T4 *)
		PROCEDURE IsSUBPBI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..9,11..15,31} = {5,7,9,12..15}) & (BITS(c) * {0..3} # {0..3}) & (BITS(c) * {0..3} # {0,2,3})
		END IsSUBPBI;

		(* A7.7.173: SUB (SP minus immediate), encoding T3 *)
		PROCEDURE IsSUBSPPBI (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..9,11..15,31} = {0,2,3,5,7,9,12..15}
		END IsSUBSPPBI;

	(* A5.3 *)
	PROCEDURE IsBAMC (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {11..15,31} = {12..15,31}
	END IsBAMC;

		(* A7.7.12, encoding T3 *)
		PROCEDURE IsBC (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {11..15,28,30,31} = {12..15,31}
		END IsBC;

		(* A7.7.12, encoding T4 *)
		PROCEDURE IsB (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {11..15,28,30,31} = {12..15,28,31}
		END IsB;

		(* A7.7.18: BL, encoding T1 *)
		PROCEDURE IsBL (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {11..15,28,30,31} = {12..15,28,30,31}
		END IsBL;

	(* A5.3 *)
	PROCEDURE IsSSDI (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {4,8..15} = {11..15}
	END IsSSDI;

		(* A7.7.158: STR (immediate), encoding T3 *)
		PROCEDURE IsSWImW (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15} = {6,7,11..15}) & (BITS(c) * {0..3} # {0..3})
		END IsSWImW;

		(* A7.7.159: STR (register), encoding T2 *)
		PROCEDURE IsSWRW (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15,22..27} = {6,11..15}) & (BITS(c) * {0..3} # {0..3})
		END IsSWRW;

		(* A7.7.160: STRB (immediate), encoding T2 *)
		PROCEDURE IsSBImW (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15} = {7,11..15}) & (BITS(c) * {0..3} # {0..3})
		END IsSBImW;

		(* A7.7.161: STRB (register), encoding T2 *)
		PROCEDURE IsSBRW (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15,22..27} = {11..15}) & (BITS(c) * {0..3} # {0..3})
		END IsSBRW;

	(* A5.3 *)
	PROCEDURE IsLBMH (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {4..6,9..15} = {4,11..15}
	END IsLBMH;

		(* A7.7.45: LDRB (immediate), encoding T2 *)
		PROCEDURE IsLBImW (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15} = {4,7,11..15}) & (BITS(c) * {28..31} # {28..31}) & (BITS(c) * {0..3} # {0..3})
		END IsLBImW;

		(* A7.7.47: LDRB (register), encoding T2 *)
		PROCEDURE IsLBRW (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15,22..27} = {4,11..15}) & (BITS(c) * {28..31} # {28..31}) & (BITS(c) * {0..3} # {0..3})
		END IsLBRW;

	(* A5.3 *)
	PROCEDURE IsLW (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {4..6,9..15} = {4,6,11..15}
	END IsLW;

		(* A7.7.42: LDR (immediate), encoding T3 *)
		PROCEDURE IsLWImW (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15} = {4,6,7,11..15}) & (BITS(c) * {0..3} # {0..3})
		END IsLWImW;

		(* A7.7.42: LDR (immediate), encoding T4, P = 1, U = 0, W = 0 *)
		PROCEDURE IsLWImWNeg (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15,24..27} = {4,6,11..15,26,27}) & (BITS(c) * {0..3} # {0..3})
		END IsLWImWNeg;

		(* A7.7.43: LDR (literal); encoding T2 *)
		PROCEDURE IsLWLt (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..6,8..15} = {0..4,6,11..15}
		END IsLWLt;

		(* A7.7.44: LDR (register); encoding T2 *)
		PROCEDURE IsLWRW (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15,22..27} = {4,6,11..15}) & (BITS(c) * {0..3} # {0..3})
		END IsLWRW;

	(* A5.3 *)
	PROCEDURE IsDPR (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {8..15} = {9,11..15}
	END IsDPR;

		(* A7.7.68: LSL (register); encoding T2 *)
		PROCEDURE IsLSLR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..15,20..23,28..31} = {9,11..15,28..31}
		END IsLSLR;

		(* A7.7.11: ASR (register); encoding T2 *)
		PROCEDURE IsASRR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..15,20..23,28..31} = {6,9,11..15,28..31}
		END IsASRR;

		(* A7.7.115: ROR (register); encoding T2 *)
		PROCEDURE IsRORR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..15,20..23,28..31} = {5,6,9,11..15,28..31}
		END IsRORR;

	(* A5.3 *)
	PROCEDURE IsMMAAAD (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {7..15} = {8,9,11..15}
	END IsMMAAAD;

		(* A7.7.73: MLA; encoding T1 *)
		PROCEDURE IsMLA (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN (BITS(c) * {4..15,20..23} = {8,9,11..15}) & (BITS(c) * {28..31} # {28..31})
		END IsMLA;

		(* A7.7.74: MLS; encoding T1 *)
		PROCEDURE IsMLS (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4..15,20..23} = {8,9,11..15,20}
		END IsMLS;

		(* A7.7.83: MUL; encoding T2 *)
		PROCEDURE IsMUL (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4..15,20..23,28..31} = {8,9,11..15,28..31}
		END IsMUL;

	(* A5.3 *)
	PROCEDURE IsLMLMAAD (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {7..15} = {7..9,11..15}
	END IsLMLMAAD;

		(* A7.7.125: SDIV; encoding T1 *)
		PROCEDURE IsSDIV (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4..15,20..23,28..31} = {4,7..9,11..15,20..23,28..31}
		END IsSDIV;

	(* A6.4: Floating-point data-processing instructions *)
	PROCEDURE IsFPDP (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {8..11,13..15,20,25..27} = {9..11,13..15,25,27}
	END IsFPDP;

		(* A7.7.227: VFMA: encoding T1 *)
		PROCEDURE IsVFMA (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,7..15,20,22,24..27}  = {5,7,9..11,13..15,25,27}
		END IsVFMA;

		(* A7.7.227: VFMS: encoding T1 *)
		PROCEDURE IsVFMS (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,7..15,20,22,24..27}  = {5,7,9..11,13..15,22,25,27}
		END IsVFMS;

		(* A7.7.228: VFNMA: encoding T1 *)
		PROCEDURE IsVFNMA (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,7..15,20,22,24..27}  = {4,7,9..11,13..15,25,27}
		END IsVFNMA;

		(* A7.7.228: VFNMS: encoding T1 *)
		PROCEDURE IsVFNMS (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,7..15,20,22,24..27}  = {4,7,9..11,13..15,22,25,27}
		END IsVFNMS;

		(* A7.7.241: VMUL; encoding T1 *)
		PROCEDURE IsVMUL (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,7..15,20,22,24..27} = {5,9..11,13..15,25,27}
		END IsVMUL;

		(* A7.7.243: VNMUL; encoding T2 *)
		PROCEDURE IsVNMUL (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,7..15,20,22,24..27} = {5,9..11,13..15,22,25,27}
		END IsVNMUL;

		(* A7.7.221: VADD; encoding T1 *)
		PROCEDURE IsVADD (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,7..15,20,22,24..27} = {4,5,9..11,13..15,25,27}
		END IsVADD;

		(* A7.7.249: VSUB; encoding T1 *)
		PROCEDURE IsVSUB (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,7..15,20,22,24..27} = {4,5,9..11,13..15,22,25,27}
		END IsVSUB;

		(* A7.7.226: VDIV; encoding T1 *)
		PROCEDURE IsVDIV (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,7..15,20,22,24..27} = {7,9..11,13..15,25,27}
		END IsVDIV;

		(* A7.7.220: VABS; encoding T1 *)
		PROCEDURE IsVABS (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..5,7..15,20,22..27} = {4,5,7,9..11,13..15,22,23,25,27}
		END IsVABS;

		(* A7.7.242: VNEG; encoding T1 *)
		PROCEDURE IsVNEG (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..5,7..15,20,22..27} = {0,4,5,7,9..11,13..15,22,25,27}
		END IsVNEG;

		(* A7.7.246: VSQRT; encoding T1 *)
		PROCEDURE IsVSQRT (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..5,7..15,20,22..27} = {0,4,5,7,9..11,13..15,22,23,25,27}
		END IsVSQRT;

		(* A7.7.222: VCMP{E}; encoding T1 *)
		PROCEDURE IsVCMPER (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..5,7..15,20,22,24..27} = {2,4,5,7,9..11,13..15,22,25,27}
		END IsVCMPER;

		(* A7.7.222: VCMP{E}; encoding T2 *)
		PROCEDURE IsVCMPE0 (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..5,7..15,16..22,24..27} = {0,2,4,5,7,9..11,13..15,22,25,27}
		END IsVCMPE0;

		(* A7.7.223: VCVT, VCVTR (between floating-point and integer); encoding T1 *)
		PROCEDURE IsVCVTRInt (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {1,3..5,7..15,20,22,24..27} = {3..5,7,9..11,13..15,22,25,27}
		END IsVCVTRInt;

	(* A6.5: (Floating-point) Extension register load or store instructions *)
	PROCEDURE IsFPERLOS (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {9..11,13..15,25..27} = {10,11,13..15,25,27}
	END IsFPERLOS;

		(* A7.7.248: VSTR; encoding T2 *)
		PROCEDURE IsVSTR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,8..15,24..27} = {8,10,11,13..15,25,27}
		END IsVSTR;

		(* A7.7.230: VLDR; encoding T2 *)
		PROCEDURE IsVLDR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {4,5,8..15,24..27} = {4,8,10,11,13..15,25,27}
		END IsVLDR;

	(* A6.6: (Floating-point) 32-bit transfer between ARM core and extension registers *)
	PROCEDURE IsFP32TBACAER (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN BITS(c) * {8..11,13..15,20,25..27} = {9..11,13..15,20,25,27}
	END IsFP32TBACAER;

		(* A7.7.236: VMOV (between ARM core register and single-precision register); encoding T1 *)
		PROCEDURE IsVMOVSPR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {5..22,24..27} = {9..11,13..15,20,25,27}
		END IsVMOVSPR;

		(* A7.7.239: VMRS; encoding T1 *)
		PROCEDURE IsVMRS (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..27} = {0,4..7,9..11,13..15,20,25,27}
		END IsVMRS;

		(* A7.7.240: VMSR; encoding T1 *)
		PROCEDURE IsVMSR (c: INTEGER): BOOLEAN;
		BEGIN
			RETURN BITS(c) * {0..27} = {0,5..7,9..11,13..15,20,25,27}
		END IsVMSR;

	PROCEDURE IsWFIW (c: INTEGER): BOOLEAN;
	BEGIN
		RETURN c = 8003F3AFH
	END IsWFIW;

	PROCEDURE EmitWFIW* (VAR code: ARRAY OF INTEGER; VAR pc: INTEGER);
	BEGIN
		Emit2(code, pc, -2147224657 (*8003F3AFH*))
	END EmitWFIW;

	(* A7.7.12, encoding T3 *)
	PROCEDURE DecodeBC (c: INTEGER; (*OUT*)VAR cond, label: INTEGER);
		VAR S, imm6, J1, J2, imm11: INTEGER;
	BEGIN
		ASSERT(IsBC(c), 20);
		imm11 := c DIV 10000H MOD 800H;
		J2 := c DIV 8000000H MOD 2;
		J1 := c DIV 20000000H MOD 2;
		imm6 := c MOD 40H;
		cond := c DIV 40H MOD 10H;
		S := c DIV 400H MOD 2;
		label := DecodeBLabel20(S, imm6, J1, J2, imm11)
	END DecodeBC;

	(* A7.7.12, encoding T4 *)
	PROCEDURE DecodeB (c: INTEGER): INTEGER;
		VAR S, imm10, J1, J2, imm11: INTEGER;
	BEGIN
		ASSERT(IsB(c), 20);
		imm11 := c DIV 10000H MOD 800H;
		J2 := c DIV 8000000H MOD 2;
		J1 := c DIV 20000000H MOD 2;
		imm10 := c MOD 400H;
		S := c DIV 400H MOD 2;
		RETURN ARMv6M.DecodeBLabel24(S, imm10, J1, J2, imm11)
	END DecodeB;

	PROCEDURE OpcodeRepr2 (c: INTEGER; (*OUT*)VAR s: ARRAY OF CHAR);
		VAR w: INTEGER;

		PROCEDURE WStr ((*OUT*)VAR s: ARRAY OF CHAR; VAR w: INTEGER; (*IN*) s0: ARRAY OF CHAR);
			VAR i: INTEGER;
		BEGIN
			i := 0;
			WHILE (i < LEN(s0(*$*))) & (s0[i] # 0X) DO
				s[w] := s0[i]; INC(w);
				INC(i)
			END
		END WStr;

		PROCEDURE WReg ((*OUT*)VAR s: ARRAY OF CHAR; VAR w: INTEGER; r: INTEGER);
			VAR s0: ARRAY 4 OF CHAR;
		BEGIN
			ARMv6M.RegRepr(r, s0);
			WStr(s, w, s0)
		END WReg;

		PROCEDURE WInt ((*OUT*)VAR s: ARRAY OF CHAR; VAR w: INTEGER; x: INTEGER);
			VAR s0: ARRAY 12 OF CHAR;
		BEGIN
			Strings.IntToStr(x, s0);
			WStr(s, w, s0)
		END WInt;

		PROCEDURE WHex32 ((*OUT*)VAR s: ARRAY OF CHAR; VAR w: INTEGER; x: INTEGER);
			VAR i, a: INTEGER;
		BEGIN i := 8;
			REPEAT
				a := x DIV 10000000H MOD 10H; x := x * 10H;
				IF a < 10 THEN s[w] := CHR(ORD('0') + a)
				ELSE s[w] := CHR(ORD('A') - 10 + a)
				END; INC(w);
				DEC(i)
			UNTIL i = 0
		END WHex32;

		PROCEDURE WHex16L ((*OUT*)VAR s: ARRAY OF CHAR; VAR w: INTEGER; x: INTEGER);
			VAR i, a: INTEGER;
		BEGIN i := 4;
			REPEAT
				a := x DIV 1000H MOD 10H; x := x * 10H;
				IF a < 10 THEN s[w] := CHR(ORD('0') + a)
				ELSE s[w] := CHR(ORD('A') - 10 + a)
				END; INC(w);
				DEC(i)
			UNTIL i = 0
		END WHex16L;

		PROCEDURE WHex12L ((*OUT*)VAR s: ARRAY OF CHAR; VAR w: INTEGER; x: INTEGER);
			VAR i, a: INTEGER;
		BEGIN i := 3;
			REPEAT
				a := x DIV 100H MOD 10H; x := x * 10H;
				IF a < 10 THEN s[w] := CHR(ORD('0') + a)
				ELSE s[w] := CHR(ORD('A') - 10 + a)
				END; INC(w);
				DEC(i)
			UNTIL i = 0
		END WHex12L;

		PROCEDURE LMASM;

			PROCEDURE Op0 ((*IN*) op: ARRAY OF CHAR; unpr: BOOLEAN);
				VAR i, j: INTEGER;
			BEGIN
				WStr(s, w, op); WStr(s, w, ".W {");
				i := 0; j := 0;
				WHILE i < 16 DO
					IF (16 + i) IN BITS(c) THEN
						IF j # 0 THEN WStr(s, w, ", ") END;
						WReg(s, w, i);
						INC(j)
					END;
					INC(i)
				END;
				s[w] := '}'; INC(w);
				IF (j < 2) OR unpr THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			END Op0;

		BEGIN
			IF IsPUSHMany(c) THEN
				Op0("PUSH", FALSE)
			ELSIF IsPOPMany(c) THEN
				Op0("POP", c DIV 40000000H = -1)
			END
		END LMASM;

		PROCEDURE PUSHPOPOne;
			VAR Rt: INTEGER;

			PROCEDURE Op1 ((*IN*) op: ARRAY OF CHAR; unpr: BOOLEAN);
			BEGIN
				WStr(s, w, op); WStr(s, w, ".W {"); WReg(s, w, Rt);
				s[w] := '}'; INC(w);
				IF unpr THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			END Op1;

		BEGIN
			IF IsPUSHOne(c) THEN (* SSDI *)
				Rt := c DIV 10000000H MOD 10H;
				Op1("PUSH", Rt IN {SP,PC})
			ELSIF IsPOPOne(c) THEN (* LW *)
				Rt := c DIV 10000000H MOD 10H;
				Op1("POP", Rt = SP)
			END
		END PUSHPOPOne;

		PROCEDURE DPSR;
			VAR S, Rd, Rn, Rm, shift: INTEGER;

			PROCEDURE WDPSR0 ((*IN*) op: ARRAY OF CHAR; W: BOOLEAN; shift: INTEGER; unpr: BOOLEAN);
			BEGIN
				ASSERT(S IN {0,1}, 20);
				WStr(s, w, op);
				IF S = 1 THEN s[w] := 'S'; INC(w) END;
				IF W THEN WStr(s, w, ".W") END;
				s[w] := ' '; INC(w);
				WReg(s, w, Rd); WStr(s, w, ", "); WReg(s, w, Rm);
				IF shift # 0 THEN
					WStr(s, w, ", #");
					WInt(s, w, shift)
				END;
				IF unpr THEN WStr(s, w, " (UNPREDICTABLE)") END
			END WDPSR0;

			PROCEDURE WDPSR1 ((*IN*) op: ARRAY OF CHAR; W: BOOLEAN; shift: INTEGER; unpr: BOOLEAN);
			BEGIN
				ASSERT(S IN {0,1}, 20);
				WStr(s, w, op);
				IF S = 1 THEN s[w] := 'S'; INC(w) END;
				IF W THEN WStr(s, w, ".W") END;
				s[w] := ' '; INC(w);
				WReg(s, w, Rd); WStr(s, w, ", ");
				WReg(s, w, Rn); WStr(s, w, ", "); WReg(s, w, Rm);
				IF shift # 0 THEN
					WStr(s, w, ", #");
					WInt(s, w, shift)
				END;
				IF unpr THEN WStr(s, w, " (UNPREDICTABLE)") END
			END WDPSR1;

		BEGIN
			S := c DIV 10H MOD 2;
			Rd := c DIV 1000000H MOD 10H;
			Rn := c MOD 10H;
			Rm := c DIV 10000H MOD 10H;
			IF IsMVNR(c) THEN
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR0("MVN", TRUE, 0, (Rd IN {SP,PC}) OR (Rm IN {SP,PC}))
				END
			ELSIF IsMOVR(c) THEN
				WDPSR0("MOV", TRUE, 0, ((S = 1) & ((Rd IN {SP,PC}) OR (Rm IN {SP,PC}))) OR ((S = 0) & ((Rd = PC) OR (Rm = PC) OR (Rd = SP) & (Rm = SP))))
			ELSIF IsANDR(c) THEN ASSERT(~((Rd = PC) & (S = 1)), 100);
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("AND", TRUE, 0, (Rd = SP) OR (Rd = PC) & (S = 0) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}))
				END
			ELSIF IsBICR(c) THEN
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("BIC", TRUE, 0, (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}))
				END
			ELSIF IsORRR(c) THEN ASSERT(Rn # PC, 101);
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("ORR", TRUE, 0, (Rd IN {SP,PC}) OR (Rn = SP) OR (Rm IN {SP,PC}))
				END
			ELSIF IsEORR(c) THEN ASSERT(~((Rd = PC) & (S = 1)), 102);
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("EOR", TRUE, 0, (Rd = SP) OR (Rd = PC) & (S = 0) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}))
				END
			ELSIF IsADDR(c) THEN
				ASSERT(~((Rd = PC) & (S = 1)), 103); ASSERT(Rn # SP, 104);
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("ADD", TRUE, 0, (Rd = SP) OR (Rd = PC) & (S = 0) OR (Rn = PC) OR (Rm IN {SP,PC}))
				END
			ELSIF IsADDSPR(c) THEN
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("ADD", TRUE, 0, (Rd = PC) OR (Rm IN {SP,PC})) (* TODO: unpr depend on shift *)
				END
			ELSIF IsADCR(c) THEN
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("ADC", TRUE, 0, (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}))
				END
			ELSIF IsSUBR(c) THEN
				ASSERT(~((Rd = PC) & (S = 1)), 105); ASSERT(Rn # SP, 106);
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("SUB", TRUE, 0, (Rd = SP) OR (Rd = PC) & (S = 0) OR (Rn = PC) OR (Rm IN {SP,PC}))
				END
			ELSIF IsSUBSPR(c) THEN
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("SUB", FALSE, 0, (Rd = PC) OR (Rm IN {SP,PC})) (* TODO: unpr depend on shift *)
				END
			ELSIF IsSBCR(c) THEN
				(* TODO: DecodeImmShift *)
				IF (c DIV 100000H MOD 10H = 0) & (c DIV 10000000H MOD 8 = 0) THEN
					WDPSR1("SBC", TRUE, 0, (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}))
				END
			ELSIF IsLSLIm(c) THEN
				shift := c DIV 10000000H MOD 8 * 4 + c DIV 400000H MOD 4;
				ASSERT(shift # 0, 107);
				WDPSR0("LSL", TRUE, shift, (Rd IN {SP,PC}) OR (Rm IN {SP,PC}))
			ELSIF IsASRIm(c) THEN
				shift := c DIV 10000000H MOD 8 * 4 + c DIV 400000H MOD 4;
				WDPSR0("ASR", TRUE, shift, (Rd IN {SP,PC}) OR (Rm IN {SP,PC}))
			ELSIF IsRORIm(c) THEN
				shift := c DIV 10000000H MOD 8 * 4 + c DIV 400000H MOD 4;
				ASSERT(shift # 0, 108);
				WDPSR0("ROR", FALSE, shift, (Rd IN {SP,PC}) OR (Rm IN {SP,PC}))
			END
		END DPSR;

		PROCEDURE DPMI;
			VAR i, imm3, imm8, im, S, Rn, Rd: INTEGER;
				ok: BOOLEAN;

			PROCEDURE WOp0 ((*IN*) op: ARRAY OF CHAR; unpr: BOOLEAN);
			BEGIN
				WStr(s, w, op);
				s[w] := ' '; INC(w);
				WReg(s, w, Rn); WStr(s, w, ", #");
				IF ok THEN
					IF (im >= -1) & (im <= 255) THEN
						WInt(s, w, im)
					ELSE
						WStr(s, w, "0x"); WHex32(s, w, im)
					END
				ELSE WStr(s, w, "(UNPREDICTABLE)")
				END;
				IF unpr THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			END WOp0;

			PROCEDURE WOp1 ((*IN*) op: ARRAY OF CHAR; W: BOOLEAN; unpr: BOOLEAN);
			BEGIN
				WStr(s, w, op);
				IF S = 1 THEN s[w] := 'S'; INC(w) END;
				IF W THEN WStr(s, w, ".W") END;
				s[w] := ' '; INC(w);
				WReg(s, w, Rd); WStr(s, w, ", #");
				IF ok THEN
					IF (im >= -1) & (im <= 255) THEN
						WInt(s, w, im)
					ELSE
						WStr(s, w, "0x"); WHex32(s, w, im)
					END
				ELSE WStr(s, w, "(UNPREDICTABLE)")
				END;
				IF unpr THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			END WOp1;

			PROCEDURE WOp2 ((*IN*) op: ARRAY OF CHAR; W: BOOLEAN; unpr: BOOLEAN);
			BEGIN
				WStr(s, w, op);
				IF S = 1 THEN s[w] := 'S'; INC(w) END;
				IF W THEN WStr(s, w, ".W") END;
				s[w] := ' '; INC(w);
				WReg(s, w, Rd); WStr(s, w, ", ");
				WReg(s, w, Rn); WStr(s, w, ", #");
				IF ok THEN
					IF (im >= -1) & (im <= 255) THEN
						WInt(s, w, im)
					ELSE
						WStr(s, w, "0x"); WHex32(s, w, im)
					END
				ELSE WStr(s, w, "(UNPREDICTABLE)")
				END;
				IF unpr THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			END WOp2;

		BEGIN
			i := c DIV 400H MOD 2;
			S := c DIV 10H MOD 2;
			Rn := c MOD 10H;
			imm3 := c DIV 10000000H MOD 8;
			Rd := c DIV 1000000H MOD 10H;
			imm8 := c DIV 10000H MOD 100H;
			DecodeMI12(i, imm3, imm8, im, ok);
			IF IsTSTIm(c) THEN
				WOp0("TST", Rn IN {SP,PC})
			ELSIF IsCMPImW(c) THEN
				WOp0("CMP.W", Rn = PC)
			ELSIF IsMOVMI(c) THEN
				WOp1("MOV", TRUE, Rd IN {SP,PC})
			ELSIF IsMVNIm(c) THEN
				WOp1("MVN", FALSE, Rd IN {SP,PC})
			ELSIF IsANDIm(c) THEN
				ASSERT(~((Rd = PC) & (S = 1)), 100);
				WOp2("AND", FALSE, (Rd = SP) OR (Rd = PC) & (S = 0) OR (Rn IN {SP,PC}))
			ELSIF IsORRIm(c) THEN
				ASSERT(Rn # PC, 101);
				WOp2("ORR", FALSE, (Rd IN {SP,PC}) OR (Rn = SP))
			ELSIF IsORNIm(c) THEN
				ASSERT(Rn # PC, 102);
				WOp2("ORN", FALSE, (Rd IN {SP,PC}) OR (Rn = SP))
			ELSIF IsBICIm(c) THEN
				WOp2("BIC", FALSE, (Rd IN {SP,PC}) OR (Rn IN {SP,PC}))
			ELSIF IsEORIm(c) THEN
				ASSERT(~((Rd = PC) & (S = 1)), 103);
				WOp2("EOR", FALSE, (Rd = SP) OR (Rd = PC) & (S = 0) OR (Rn IN {SP,PC}))
			ELSIF IsADDMI(c) THEN
				ASSERT(~((Rd = PC) & (S = 1)), 104);
				ASSERT(Rn # SP, 105);
				WOp2("ADD", TRUE, (Rd = SP) OR (Rd = PC) & (S = 0) OR (Rn = PC))
			ELSIF IsADDSPMI(c) THEN
				ASSERT(~((Rd = PC) & (S = 1)), 106);
				WOp2("ADD", TRUE, (Rd = PC) & (S = 0))
			ELSIF IsSUBMI(c) THEN
				ASSERT(~((Rd = PC) & (S = 1)), 107);
				ASSERT(Rn # SP, 108);
				WOp2("SUB", TRUE, (Rd = SP) OR (Rd = PC) & (S = 0) OR (Rn = PC))
			ELSIF IsSUBSPMI(c) THEN
				ASSERT(~((Rd = PC) & (S = 1)), 109);
				WOp2("SUB", TRUE, (Rd = PC) & (S = 0))
			ELSIF IsRSBImW(c) THEN
				WOp2("RSB", TRUE, (Rd IN {SP,PC}) OR (Rn IN {SP,PC}))
			END
		END DPMI;

		PROCEDURE DPPBI;
			VAR Rd, Rn: INTEGER;

			PROCEDURE OpMovx ((*IN*) op: ARRAY OF CHAR);
				VAR im: INTEGER;
			BEGIN
				im := c MOD 10H * 1000H + c DIV 400H MOD 2 * 800H + c DIV 10000000H MOD 8 * 100H + c DIV 10000H MOD 100H;
				WStr(s, w, op); s[w] := ' '; INC(w);
				WReg(s, w, Rd);
				WStr(s, w, ", #"); WInt(s, w, im);
				WStr(s, w, " ; 0x"); WHex16L(s, w, im);
				IF Rd IN {SP,PC} THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			END OpMovx;

			PROCEDURE Op0 ((*IN*) op: ARRAY OF CHAR; unpr: BOOLEAN);
				VAR im: INTEGER;
			BEGIN
				im := c DIV 400H MOD 2 * 800H + c DIV 10000000H MOD 8 * 100H + c DIV 10000H MOD 100H;
				WStr(s, w, op); s[w] := ' '; INC(w);
				WReg(s, w, Rd); WStr(s, w, ", ");
				WReg(s, w, Rn); WStr(s, w, ", #");
				WInt(s, w, im);
				WStr(s, w, " ; 0x"); WHex12L(s, w, im);
				IF unpr THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			END Op0;

		BEGIN
			Rd := c DIV 1000000H MOD 10H;
			Rn := c MOD 10H;
			IF IsMOVPBI(c) THEN
				OpMovx("MOVW")
			ELSIF IsMOVT(c) THEN
				OpMovx("MOVT")
			ELSIF IsADDPBI(c) THEN
				ASSERT(~(Rn IN {SP,PC}), 100);
				Op0("ADDW", Rd IN {SP,PC})
			ELSIF IsADDSPPBI(c) THEN
				Op0("ADDW", Rd = PC)
			ELSIF IsSUBPBI(c) THEN
				ASSERT(~(Rn IN {SP,PC}), 101);
				Op0("SUBW", Rd IN {SP,PC})
			ELSIF IsSUBSPPBI(c) THEN
				Op0("SUBW", Rd = PC)
			END
		END DPPBI;

		PROCEDURE B (L: BOOLEAN);
			VAR label: INTEGER;
		BEGIN
			IF L THEN label := ARMv6M.DecodeBL(c)
			ELSE label := DecodeB(c)
			END;
			ASSERT(label MOD 2 = 0, 100);
			IF L THEN
				WStr(s, w, "BL ")
			ELSE
				WStr(s, w, "B.W ")
			END;
			WInt(s, w, label);
			IF label # 0 THEN
				WStr(s, w, " ; "); WInt(s, w, label DIV 2)
			END
		END B;

		PROCEDURE BC;
			VAR cond, label: INTEGER;
				s0: ARRAY 3 OF CHAR;
		BEGIN
			DecodeBC(c, cond, label);
			ASSERT(label MOD 2 = 0, 100);
			ARMv6M.CondRepr(cond, s0);
			s[w] := 'B'; INC(w);
			WStr(s, w, s0); WStr(s, w, ".W "); WInt(s, w, label);
			IF label # 0 THEN
				WStr(s, w, " ; "); WInt(s, w, label DIV 2)
			END
		END BC;

		PROCEDURE LSWBImW (S, B: BOOLEAN);
			VAR imm12: INTEGER;
				Rt: INTEGER;
		BEGIN
			IF S THEN
				WStr(s, w, "STR")
			ELSE
				WStr(s, w, "LDR")
			END;
			IF B THEN s[w] := 'B'; INC(w) END;
			WStr(s, w, ".W ");
			Rt := c DIV 10000000H MOD 10H;
			WReg(s, w, Rt);
			WStr(s, w, ", [");
			WReg(s, w, c MOD 10H);
			imm12 := c DIV 10000H MOD 1000H;
			IF imm12 # 0 THEN
				WStr(s, w, ", #");
				WInt(s, w, imm12)
			END;
			s[w] := ']'; INC(w);
			IF (~S & ~B & (Rt = PC))
			OR (~S & B & (Rt = SP))
			OR (S & ~B & (Rt = PC))
			OR (S & B & (Rt IN {SP,PC})) THEN
				WStr(s, w, " (UNPREDICTABLE)")
			END
		END LSWBImW;

		PROCEDURE LSWBImWNeg (S, B: BOOLEAN);
			VAR imm8: INTEGER;
				Rt: INTEGER;
		BEGIN
			IF S THEN
				WStr(s, w, "STR")
			ELSE
				WStr(s, w, "LDR")
			END;
			IF B THEN s[w] := 'B'; INC(w) END;
			WStr(s, w, ".W ");
			Rt := c DIV 10000000H MOD 10H;
			WReg(s, w, Rt);
			WStr(s, w, ", [");
			WReg(s, w, c MOD 10H);
			imm8 := c DIV 10000H MOD 100H;
			IF imm8 # 0 THEN
				WStr(s, w, ", #-");
				WInt(s, w, imm8)
			END;
			s[w] := ']'; INC(w);
(*
			IF (~S & ~B & (Rt = PC))
			OR (~S & B & (Rt = SP))
			OR (S & ~B & (Rt = PC))
			OR (S & B & (Rt IN {SP,PC})) THEN
				WStr(s, w, " (UNPREDICTABLE)")
			END
*)
		END LSWBImWNeg;

		PROCEDURE LSWBRW (S, B: BOOLEAN);
			VAR Rt, Rm, imm2: INTEGER;
		BEGIN
			IF S THEN
				WStr(s, w, "STR")
			ELSE
				WStr(s, w, "LDR")
			END;
			IF B THEN s[w] := 'B'; INC(w) END;
			WStr(s, w, ".W ");
			Rt := c DIV 10000000H MOD 10H;
			WReg(s, w, Rt);
			WStr(s, w, ", [");
			WReg(s, w, c MOD 10H);
			imm2 := c DIV 100000H MOD 4;
			Rm := c DIV 10000H MOD 10H;
			WStr(s, w, ", "); WReg(s, w, Rm);
			IF imm2 # 0 THEN
				WStr(s, w, ", LSL #");
				WInt(s, w, imm2)
			END;
			s[w] := ']'; INC(w);
			IF (Rm IN {SP,PC})
			OR (~S & ~B & (Rt = PC))
			OR (~S & B & (Rt = SP))
			OR (S & ~B & (Rt = PC))
			OR (S & B & (Rt IN {SP,PC})) THEN
				WStr(s, w, " (UNPREDICTABLE)")
			END
		END LSWBRW;

		PROCEDURE LW;
			VAR Rt, U, imm12, label: INTEGER;
		BEGIN
			IF IsLWImW(c) THEN
				LSWBImW(FALSE, FALSE)
			ELSIF IsLWImWNeg(c) THEN
				LSWBImWNeg(FALSE, FALSE)
			ELSIF IsLWRW(c) THEN
				LSWBRW(FALSE, FALSE)
			ELSIF IsLWLt(c) THEN
				Rt := c DIV 10000000H MOD 10H;
				U := c DIV 80H MOD 2;
				imm12 := c DIV 10000H MOD 1000H;
				IF U = 1 THEN label := imm12 ELSE label := -imm12 END;
				WStr(s, w, "LDR.W "); WReg(s, w, Rt); WStr(s, w, ", ");
				(* WInt(s, w, label); *)
					WStr(s, w, "[PC, #"); WInt(s, w, label); s[w] := ']'; INC(w);
				IF label MOD 4 = 0 THEN
					WStr(s, w, " ; "); WInt(s, w, label DIV 4)
				END
			END
		END LW;

		PROCEDURE DPR;
			VAR S, Rd, Rn, Rm: INTEGER;

			PROCEDURE WDPRW ((*IN*) op: ARRAY OF CHAR; unpr: BOOLEAN);
			BEGIN
				WStr(s, w, op);
				IF S = 1 THEN s[w] := 'S'; INC(w) END;
				WStr(s, w, ".W ");
				WReg(s, w, Rd); WStr(s, w, ", ");
				WReg(s, w, Rn); WStr(s, w, ", ");
				WReg(s, w, Rm);
				IF unpr THEN WStr(s, w, " (UNPREDICTABLE)") END
			END WDPRW;

		BEGIN
			S := c DIV 10H MOD 2;
			Rd := c DIV 1000000H MOD 10H;
			Rn := c MOD 10H;
			Rm := c DIV 10000H MOD 10H;
			IF IsLSLR(c) THEN
				WDPRW("LSL", (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}))
			ELSIF IsASRR(c) THEN
				WDPRW("ASR", (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}))
			ELSIF IsRORR(c) THEN
				WDPRW("ROR", (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}))
			END
		END DPR;

		PROCEDURE MMAAAD;
			VAR Rd, Rn, Rm, Ra: INTEGER;
		BEGIN
			Rn := c MOD 10H;
			Ra := c DIV 10000000H MOD 10H;
			Rd := c DIV 1000000H MOD 10H;
			Rm := c DIV 10000H MOD 10H;
			IF IsMUL(c) THEN
				WStr(s, w, "MUL "); WReg(s, w, Rd); WStr(s, w, ", ");
				WReg(s, w, Rn); WStr(s, w, ", ");
				WReg(s, w, Rm);
				IF (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}) THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			ELSIF IsMLS(c) THEN
				WStr(s, w, "MLS "); WReg(s, w, Rd); WStr(s, w, ", ");
				WReg(s, w, Rn); WStr(s, w, ", ");
				WReg(s, w, Rm); WStr(s, w, ", ");
				WReg(s, w, Ra);
				IF (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}) OR (Ra IN {SP,PC}) THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			ELSIF IsMLA(c) THEN
				WStr(s, w, "MLA "); WReg(s, w, Rd); WStr(s, w, ", ");
				WReg(s, w, Rn); WStr(s, w, ", ");
				WReg(s, w, Rm); WStr(s, w, ", ");
				WReg(s, w, Ra);
				IF (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}) OR (Ra = SP) THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			END
		END MMAAAD;

		PROCEDURE LMLMAAD;
			VAR Rd, Rn, Rm: INTEGER;
		BEGIN
			IF IsSDIV(c) THEN
				Rn := c MOD 10H;
				Rd := c DIV 1000000H MOD 10H;
				Rm := c DIV 10000H MOD 10H;
				WStr(s, w, "SDIV "); WReg(s, w, Rd); WStr(s, w, ", ");
				WReg(s, w, Rn); WStr(s, w, ", ");
				WReg(s, w, Rm);
				IF (Rd IN {SP,PC}) OR (Rn IN {SP,PC}) OR (Rm IN {SP,PC}) THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			END
		END LMLMAAD;

		PROCEDURE FPDP;
			VAR d, n, m: INTEGER;
				T, sz: INTEGER;

			PROCEDURE Op0 ((*IN*) op: ARRAY OF CHAR);
			BEGIN
				WStr(s, w, op); WStr(s, w, ".F32 S"); WInt(s, w, d);
				WStr(s, w, ", S"); WInt(s, w, n); WStr(s, w, ", S");
				WInt(s, w, m)
			END Op0;

			PROCEDURE Op1 ((*IN*) op: ARRAY OF CHAR);
			BEGIN
				WStr(s, w, op); WStr(s, w, ".F32 S"); WInt(s, w, d);
				WStr(s, w, ", S"); WInt(s, w, m)
			END Op1;

		BEGIN
			d := c DIV 10000000H MOD 10H * 2 + c DIV 40H MOD 2;
			n := c MOD 10H * 2 + c DIV 800000H MOD 2;
			m := c DIV 10000H MOD 10H * 2 + c DIV 200000H MOD 2;
			IF IsVMUL(c) THEN
				Op0("VMUL")
			ELSIF IsVADD(c) THEN
				Op0("VADD")
			ELSIF IsVSUB(c) THEN
				Op0("VSUB")
			ELSIF IsVDIV(c) THEN
				Op0("VDIV")
			ELSIF IsVFMA(c) THEN
				Op0("VFMA")
			ELSIF IsVFMS(c) THEN
				Op0("VFMS")
			ELSIF IsVFNMA(c) THEN
				Op0("VFNMA")
			ELSIF IsVFNMS(c) THEN
				Op0("VFNMS")
			ELSIF IsVNMUL(c) THEN
				Op0("VNMUL")
			ELSIF IsVABS(c) THEN
				Op1("VABS")
			ELSIF IsVNEG(c) THEN
				Op1("VNEG")
			ELSIF IsVSQRT(c) THEN
				Op1("VSQRT")
			ELSIF IsVCMPER(c) THEN
				WStr(s, w, "VCMP");
				IF 23 IN BITS(c) THEN s[w] := 'E'; INC(w) END;
				WStr(s, w, ".F32 S"); WInt(s, w, d);
				WStr(s, w, ", S"); WInt(s, w, m)
			ELSIF IsVCMPE0(c) THEN
				WStr(s, w, "VCMP");
				IF 23 IN BITS(c) THEN s[w] := 'E'; INC(w) END;
				WStr(s, w, ".F32 S"); WInt(s, w, d); WStr(s, w, ", #0.0")
			ELSIF IsVCVTRInt(c) THEN ASSERT(~ODD(c DIV 2), 100);
				WStr(s, w, "VCVT");
				IF ODD(c DIV 4) THEN (* to integer *)
					IF ~(23 IN BITS(c)) THEN s[w] := 'R'; INC(w) END;
					s[w] := '.'; INC(w);
					IF ODD(c) THEN s[w] := 'S' ELSE s[w] := 'U' END;
					INC(w); WStr(s, w, "32.F32 S")
				ELSE
					WStr(s, w, ".F32.");
					IF 23 IN BITS(c) THEN s[w] := 'S' ELSE s[w] := 'U' END;
					INC(w); WStr(s, w, "32 S")
				END;
				WInt(s, w, d); WStr(s, w, ", S"); WInt(s, w, m);
				IF c MOD 8 = 1 THEN
					WStr(s, w, " ; opc2 = 1")
				END
			ELSE
				T := c DIV 1000H MOD 2;
				sz := c DIV 1000000H MOD 2;
				IF (T = 1) OR (sz = 1) THEN
					WStr(s, w, "FP UNDEFINED")
				END
			END
		END FPDP;

		PROCEDURE FPERLOS;
			VAR T: INTEGER;
				Rn: INTEGER;

			PROCEDURE Op0 ((*IN*) op: ARRAY OF CHAR);
				VAR Sd, imm32: INTEGER;
			BEGIN
				Sd := c DIV 10000000H MOD 10H * 2 + c DIV 40H MOD 2;
				imm32 := c DIV 10000H MOD 100H * 4;
				WStr(s, w, op); WStr(s, w, " S"); WInt(s, w, Sd); WStr(s, w, ", [");
				WReg(s, w, Rn); WStr(s, w, ", #");
				IF 7 IN BITS(c) THEN s[w] := '+' ELSE s[w] := '-' END; INC(w);
				WInt(s, w, imm32); s[w] := ']'; INC(w)
			END Op0;

		BEGIN
			Rn := c MOD 10H;
			IF IsVSTR(c) THEN
				Op0("VSTR")
			ELSIF IsVLDR(c) THEN
				Op0("VLDR")
			ELSE
				T := c DIV 1000H MOD 2;
				IF T = 1 THEN
					WStr(s, w, "FP UNDEFINED")
				END
			END
		END FPERLOS;

		PROCEDURE FP32TBACAER;
			VAR n, Rt, op: INTEGER;
				T: INTEGER;
		BEGIN
			Rt := c DIV 10000000H MOD 10H;
			IF IsVMOVSPR(c) THEN
				n := c MOD 10H * 2 + c DIV 800000H MOD 2;
				op := c DIV 10H MOD 2;
				IF op = 1 THEN (* to ARM register *)
					WStr(s, w, "VMOV "); WReg(s, w, Rt); WStr(s, w, ", S");
					WInt(s, w, n)
				ELSE
					WStr(s, w, "VMOV S"); WInt(s, w, n); WStr(s, w, ", ");
					WReg(s, w, Rt)
				END;
				IF Rt IN {SP,PC} THEN
					WStr(s, w, " (UNPREDICTABLE)")
				END
			ELSIF IsVMRS(c) THEN
				WStr(s, w, "VMRS ");
				IF Rt = 15 THEN WStr(s, w, "APSR_nzcv") ELSE WReg(s, w, Rt) END;
				WStr(s, w, ", FPSCR")
			ELSIF IsVMSR(c) THEN
				WStr(s, w, "VMSR FPSCR, ");
				WReg(s, w, Rt)
			ELSE
				T := c DIV 1000H MOD 2;
				IF T = 1 THEN
					WStr(s, w, "FP UNDEFINED")
				END
			END
		END FP32TBACAER;

	BEGIN
		w := 0;
		PUSHPOPOne;
		IF IsWFIW(c) THEN
			WStr(s, w, "WFI")
		ELSIF IsLMASM(c) THEN
			LMASM
		ELSIF IsDPSR(c) THEN
			DPSR
		ELSIF IsDPMI(c) THEN
			DPMI
		ELSIF IsDPPBI(c) THEN
			DPPBI
		ELSIF IsBAMC(c) THEN
			IF IsB(c) THEN
				B(FALSE)
			ELSIF IsBC(c) THEN
				BC
			ELSIF IsBL(c) THEN
				B(TRUE)
			END
		ELSIF IsSSDI(c) THEN
			IF IsSWImW(c) THEN
				LSWBImW(TRUE, FALSE)
			ELSIF IsSBImW(c) THEN
				LSWBImW(TRUE, TRUE)
			ELSIF IsSWRW(c) THEN
				LSWBRW(TRUE, FALSE)
			ELSIF IsSBRW(c) THEN
				LSWBRW(TRUE, TRUE)
			END
		ELSIF IsLBMH(c) THEN
			IF IsLBImW(c) THEN
				LSWBImW(FALSE, TRUE)
			ELSIF IsLBRW(c) THEN
				LSWBRW(FALSE, TRUE)
			END
		ELSIF IsLW(c) THEN
			LW
		ELSIF IsDPR(c) THEN
			DPR
		ELSIF IsMMAAAD(c) THEN
			MMAAAD
		ELSIF IsLMLMAAD(c) THEN
			LMLMAAD
		ELSIF IsFPDP(c) THEN
			FPDP
		ELSIF IsFPERLOS(c) THEN
			FPERLOS
		ELSIF IsFP32TBACAER(c) THEN
			FP32TBACAER
		END;
		s[w] := 0X
	END OpcodeRepr2;

	(* d: decoder state *)
	PROCEDURE OpcodeRepr* (VAR d: INTEGER; c: INTEGER; (*OUT*)VAR s: ARRAY OF CHAR);
	BEGIN
		ASSERT(c DIV 10000H = 0, 20);
		IF d = 0 THEN
			ARMv6M.OpcodeRepr(d, c, s)
		ELSIF d DIV 10000H = 1 THEN
			c := 10000H * c + d MOD 10000H; d := 0;
			OpcodeRepr2(c, s)
		ELSE HALT(1)
		END
	END OpcodeRepr;

END O7ARMv7M.
