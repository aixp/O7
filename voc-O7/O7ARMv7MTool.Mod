MODULE O7ARMv7MTool;	(*NW 18.2.2013*)

	(*
		Alexander Shiryaev:
			2014.09:
				Modified for ARMv6-M and ARMv7-M
				DecBin and DecHex added
	*)

	IMPORT SYSTEM, Files (*:= O7Files*), Texts (*:= O7Texts*), Oberon (*:= O7Oberon*), ORB := O7B, ARMv7M := O7ARMv7M;

	TYPE
		LONGINT = INTEGER;
		(* REAL = SHORTREAL; *)
		LONGREAL = REAL;
		(* BYTE = SHORTCHAR; *)
		BYTE = CHAR;

	VAR W: Texts.Writer;
		Form: INTEGER;	(*result of ReadType*)

	PROCEDURE Read (VAR R: Files.Rider; VAR n: INTEGER);
		VAR b: BYTE;
	BEGIN Files.Read(*Byte*)(R, b);
		IF ORD(b) < 80H THEN n := ORD(b) ELSE n := ORD(b) - 100H END
	END Read;

	PROCEDURE ReadInt (VAR R: Files.Rider; VAR x: INTEGER);
		VAR y: SYSTEM.INT64;
	BEGIN
		Files.ReadLInt(R, y);
		IF R.eof THEN x := -1
		ELSE x := SHORT(y)
		END
	END ReadInt;

	PROCEDURE ReadType (VAR R: Files.Rider);
		VAR key, len, lev, size, off: INTEGER;
			ref, mno, class, form, readonly: INTEGER;
			name, modname: ARRAY 32 OF CHAR;
	BEGIN Read(R, ref); Texts.Write(W, " "); Texts.Write(W, "[");
		IF ref < 0 THEN Texts.Write(W, "^"); Texts.WriteInt(W, -ref, 1)
		ELSE Texts.WriteInt(W, ref, 1);
			Read(R, form); Texts.WriteString(W, " form = "); Texts.WriteInt(W, form, 1);
			IF form = ORB.Pointer THEN ReadType(R)
			ELSIF form = ORB.Array THEN
				ReadType(R); Files.ReadNum(R, len); Files.ReadNum(R, size);
				Texts.WriteString(W, " len = "); Texts.WriteInt(W, len, 1);
				Texts.WriteString(W, " size = "); Texts.WriteInt(W, size, 1)
			ELSIF form = ORB.Record THEN
				ReadType(R);	(*base type*)
				Files.ReadNum(R, off); Texts.WriteString(W, " exno = "); Texts.WriteInt(W, off, 1);
				Files.ReadNum(R, off); Texts.WriteString(W, " extlev = "); Texts.WriteInt(W, off, 1);
				Files.ReadNum(R, size); Texts.WriteString(W, " size = "); Texts.WriteInt(W, size, 1);
				Texts.Write(W, " "); Texts.Write(W, "{"); Read(R, class);
				WHILE class # 0 DO (*fields*)
					Files.ReadString(R, name);
					IF name[0] # 0X THEN Texts.Write(W, " "); Texts.WriteString(W, name); ReadType(R)
					ELSE Texts.WriteString(W, " --")
					END ;
					Files.ReadNum(R, off); Texts.WriteInt(W, off, 4); Read(R, class)
				END ;
				Texts.Write(W, "}")
			ELSIF form = ORB.Proc THEN
				ReadType(R); Texts.Write(W, "("); Read(R, class);
				WHILE class # 0 DO
					Texts.WriteString(W, " class = "); Texts.WriteInt(W, class, 1); Read(R, readonly);
					IF readonly = 1 THEN Texts.Write(W, "#") END ;
					ReadType(R); Read(R, class)
				END ;
				Texts.Write(W, ")")
			END ;
			Files.ReadString(R, modname);
			IF modname[0] # 0X THEN
				ReadInt(R, key); Files.ReadString(R, name);
				Texts.Write(W, " "); Texts.WriteString(W, modname); Texts.Write(W, "."); Texts.WriteString(W, name);
				Texts.WriteHex(W, key)
			END
		END ;
		Form := form; Texts.Write(W, "]")
	END ReadType;

	PROCEDURE DecSym*; (*decode symbol file*)
		VAR class, typno, k: INTEGER;
			name: ARRAY 32 OF CHAR;
			F: Files.File; R: Files.Rider;
			S: Texts.Scanner;
	BEGIN (*Oberon.GetPar;*) Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN
			Texts.WriteString(W, "OR-decode "); Texts.WriteString(W, S.s);
			Texts.WriteLn(W); Texts.Append(Oberon.Log(**), W.buf);
			F := Files.Old(S.s);
			IF F # NIL THEN
				Files.Set(R, F, 0); ReadInt(R, k); ReadInt(R, k);
				Files.ReadString(R, name); Texts.WriteString(W, name); Texts.WriteHex(W, k);
				Read(R, class); Texts.WriteInt(W, class, 3); (*sym file version*)
				IF class = ORB.versionkey THEN
					Texts.WriteLn(W); Read(R, class);
					WHILE class # 0 DO
						Texts.WriteInt(W, class, 4); Files.ReadString(R, name); Texts.Write(W, " "); Texts.WriteString(W, name);
						ReadType(R);
						IF class = ORB.Typ THEN
							Texts.Write(W, "("); Read(R, class);
							WHILE class # 0 DO	(*pointer base fixup*)
								Texts.WriteString(W, " ->"); Texts.WriteInt(W, class, 4); Read(R, class)
							END ;
							Texts.Write(W, ")")
						ELSIF (class = ORB.Const) OR (class = ORB.Var) THEN
							Files.ReadNum(R, k); Texts.WriteInt(W, k, 5);	(*Reals, Strings!*)
						END ;
						Texts.WriteLn(W); Texts.Append(Oberon.Log(**), W.buf);
						Read(R, class)
					END
				ELSE Texts.WriteString(W, " bad symfile version")
				END
			ELSE Texts.WriteString(W, " not found")
			END ;
			Texts.WriteLn(W); Texts.Append(Oberon.Log(**), W.buf)
		END;
		(*Oberon.Collect(0)*)
	END DecSym;

(* ---------------------------------------------------*)

	PROCEDURE opcode (VAR d: INTEGER; w: LONGINT);
		VAR s: ARRAY 64 OF CHAR;
	BEGIN
		IF w DIV 10000H = 0 THEN
			ARMv7M.OpcodeRepr(d, w, s);
			IF s # "" THEN Texts.WriteString(W, s) END
		END
	END opcode;

	PROCEDURE Sync (VAR R: Files.Rider);
		VAR ch: CHAR;
	BEGIN Files.Read(R, ch); Texts.WriteString(W, "Sync "); Texts.Write(W, ch); Texts.WriteLn(W)
	END Sync;

	PROCEDURE Write (VAR R: Files.Rider; x: INTEGER);
	BEGIN Files.Write(*Byte*)(R, CHR(x))	(* -128 <= x < 128 *)
	END Write;

	PROCEDURE DecObj*;	 (*decode object file*)
		VAR class, i, n, key, size, fix, adr, data, len: INTEGER;
			ch: CHAR;
			name: ARRAY 32 OF CHAR;
			F: Files.File; R: Files.Rider;
			S: Texts.Scanner;
			d: INTEGER; (* ARMv7-M decoder state *)
	BEGIN (*Oberon.GetPar;*) Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN
			Texts.WriteString(W, "decode "); Texts.WriteString(W, S.s); F := Files.Old(S.s);
			IF F # NIL THEN
				Files.Set(R, F, 0); Files.ReadString(R, name); Texts.WriteLn(W); Texts.WriteString(W, name);
				ReadInt(R, key); Texts.WriteHex(W, key); Read(R, class); Texts.WriteInt(W, class, 4); (*version*)
				ReadInt(R, size); Texts.WriteInt(W, size, 6); Texts.WriteLn(W);
				Texts.WriteString(W, "imports:"); Texts.WriteLn(W); Files.ReadString(R, name);
				WHILE name[0] # 0X DO
					Texts.Write(W, 9X); Texts.WriteString(W, name);
					ReadInt(R, key); Texts.WriteHex(W, key); Texts.WriteLn(W);
					Files.ReadString(R, name)
				END ;
			(* Sync(R); *)
				Texts.WriteString(W, "type descriptors"); Texts.WriteLn(W);
				ReadInt(R, n); n := n DIV 4; i := 0;
				WHILE i < n DO ReadInt(R, data); Texts.WriteHex(W, data); INC(i) END ;
				Texts.WriteLn(W);
				Texts.WriteString(W, "data"); ReadInt(R, data); Texts.WriteInt(W, data, 6); Texts.WriteLn(W);
				Texts.WriteString(W, "strings"); Texts.WriteLn(W);
				ReadInt(R, n); i := 0;
				WHILE i < n DO Files.Read(R, ch); Texts.Write(W, ch); INC(i) END ;
				Texts.WriteLn(W);
				Texts.WriteString(W, "code"); Texts.WriteLn(W);
				ReadInt(R, n); i := 0; d := 0;
				WHILE i < n DO
					ReadInt(R, data); Texts.WriteInt(W, i, 4); Texts.Write(W, 9X); Texts.WriteHex(W, data);
					Texts.Write(W, 9X); opcode(d, data); Texts.WriteLn(W); INC(i)
				END;
				ASSERT(d = 0, 100);
			(* Sync(R); *)
				Texts.WriteString(W, "commands:"); Texts.WriteLn(W);
				Files.ReadString(R, name);
				WHILE name[0] # 0X DO
					Texts.Write(W, 9X); Texts.WriteString(W, name);
					ReadInt(R, adr); Texts.WriteInt(W, adr, 5); Texts.WriteLn(W);
					Files.ReadString(R, name)
				END ;
			(* Sync(R); *)
				Texts.WriteString(W, "entries"); Texts.WriteLn(W);
				ReadInt(R, n); i := 0;
				WHILE i < n DO
					ReadInt(R, adr); Texts.WriteInt(W, adr, 6); INC(i)
				END ;
				Texts.WriteLn(W);
			(* Sync(R); *)
				Texts.WriteString(W, "pointer refs"); Texts.WriteLn(W); ReadInt(R, adr);
				WHILE adr # -1 DO Texts.WriteInt(W, adr, 6); ReadInt(R, adr) END ;
				Texts.WriteLn(W);
			(* Sync(R); *)
				ReadInt(R, data); Texts.WriteString(W, "fixP = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
				ReadInt(R, data); Texts.WriteString(W, "fixD = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
				ReadInt(R, data); Texts.WriteString(W, "fixT = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
				ReadInt(R, data); Texts.WriteString(W, "entry = "); Texts.WriteInt(W, data, 8); Texts.WriteLn(W);
				Files.Read(R, ch);
				IF ch # "O" THEN Texts.WriteString(W, "format eror"); Texts.WriteLn(W) END
			(* Sync(R); *)
			ELSE Texts.WriteString(W, " not found"); Texts.WriteLn(W)
			END ;
			Texts.Append(Oberon.Log(**), W.buf)
		END;
		(*Oberon.Collect(0)*)
	END DecObj;

	PROCEDURE DecBin*;	(* decode binary image file *)
		VAR i, data: INTEGER;
			F: Files.File; R: Files.Rider;
			S: Texts.Scanner;
			d: INTEGER; (* ARMv7-M decoder state *)

		PROCEDURE Read (VAR x: INTEGER);
			VAR c0, c1: CHAR;
		BEGIN
			Files.Read(R, c0); Files.Read(R, c1);
			x := ORD(c0) + 100H * ORD(c1);
			ASSERT(x DIV 10000H = 0, 100)
		END Read;

	BEGIN
		(*Oberon.GetPar;*) Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN
			Texts.WriteString(W, "decode "); Texts.WriteString(W, S.s); Texts.WriteLn(W); F := Files.Old(S.s);
			IF F # NIL THEN
				Files.Set(R, F, 0); Read(data); i := 0; d := 0;
				WHILE ~R.eof DO
					Texts.WriteInt(W, i, 4); Texts.Write(W, 9X); Texts.WriteHex(W, data); Texts.Write(W, 9X); opcode(d, data); Texts.WriteLn(W); INC(i);
					Read(data)
				END;
				IF d # 0 THEN Texts.WriteString(W, "invalid decoder state");
					Texts.WriteLn(W) END
			ELSE Texts.WriteString(W, " not found"); Texts.WriteLn(W)
			END;
			Texts.Append(Oberon.Log(**), W.buf)
		END;
		(*Oberon.Collect(0)*)
	END DecBin;

	PROCEDURE DecHex*;	(* decode Intel HEX file *)
		VAR ch: CHAR; err, eof: BOOLEAN;
			pos, cs, offH: INTEGER;
			F: Files.File; R: Files.Rider;
			S: Texts.Scanner;
			d: INTEGER; (* ARMv7-M decoder state *)

		PROCEDURE Get;
		BEGIN Files.Read(R, ch); IF R.eof THEN ch := 0X ELSE INC(pos) END
		END Get;

		PROCEDURE Err ((*IN*) msg: ARRAY OF CHAR);
		BEGIN
			IF ~err THEN Texts.WriteString(W, "pos = ");
				Texts.WriteInt(W, pos, 0); Texts.WriteString(W, ": ");
				Texts.WriteString(W, msg); Texts.WriteLn(W)
			END; err := TRUE
		END Err;

		PROCEDURE CheckD;
		BEGIN IF d # 0 THEN Err("invalid decoder state") END; d := 0
		END CheckD;

		PROCEDURE B ((*OUT*) VAR x: INTEGER);
			PROCEDURE H;
			BEGIN
				IF (ch >= '0') & (ch <= '9') THEN x := x * 10H + ORD(ch) - ORD('0')
				ELSIF (ch >= 'A') & (ch <= 'F') THEN x := x * 10H + ORD(ch) - ORD('A') + 10
				ELSE Err("invalid HEX")
				END; Get
			END H;
		BEGIN x := 0; H; H; cs := cs + x
		END B;

		PROCEDURE Line;
			VAR len, offL, type, cs, i, x: INTEGER;
				a: ARRAY 255 OF INTEGER;
		BEGIN
			IF eof THEN Err("EOF already reached") END;
			IF ch # ':' THEN Err("':' expected") END; Get; cs := 0;
			B(len); B(i); B(offL); offL := i * 100H + offL; B(type);
			i := 0; WHILE i < len DO B(a[i]); INC(i) END;
			B(i); IF cs MOD 100H # 0 THEN Err("checksum error") END;
			WHILE (ch = 0AX) OR (ch = 0DX) DO Get END;
			IF ~err THEN
				CASE type OF 0: (* data *)
					IF len # 0 THEN
						IF (offL MOD 2 = 0) & (len MOD 2 = 0) THEN
							i := 0;
							WHILE i < len DIV 2 DO
								Texts.WriteInt(W, offL DIV 2 + i, 4); Texts.Write(W, 9X);
								x := a[i * 2] + 100H * a[i * 2 + 1];
								Texts.WriteHex(W, x); Texts.Write(W, 9X); opcode(d, x); Texts.WriteLn(W); INC(i)
							END
						ELSE Err("unaligned data support not implemented")
						END
					ELSE Err("data length is zero")
					END
				| 1: (* EOF *)
					IF (len = 0) & (offL = 0) THEN eof := TRUE
					ELSE Err("invalid EOF")
					END
				| 2: (* extended segment address *)
					IF (len = 2) & (offL = 0) THEN
						Err("I16HEX support not implemented")
					ELSE Err("invalid extended segment address")
					END
				| 3: (* start segment address *)
					IF (len = 4) & (offL = 0) THEN
						Err("I16HEX support not implemented")
					ELSE Err("invalid start segment address")
					END
				| 4: (* extended linear address *)
					IF (len = 2) & (offL = 0) THEN CheckD;
						offH := (a[0] * 100H + a[1]) * 10000H;
						Texts.WriteHex(W, offH); Texts.WriteString(W, "H:");
						Texts.WriteLn(W)
					ELSE Err("invalid extended linear address")
					END
				| 5: (* start linear address *)
					IF (len = 4) & (offL = 0) THEN
						Texts.WriteString(W, "start linear address: ");
						x := a[0] * 1000000H + a[1] * 10000H + a[2] * 100H + a[3];
						Texts.WriteHex(W, x); Texts.Write(W, 'H'); Texts.WriteLn(W)
					ELSE Err("invalid start linear address")
					END
				ELSE Err("unexpected record type")
				END
			END
		END Line;

	BEGIN
		(*Oberon.GetPar;*) Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.class = Texts.Name THEN
			Texts.WriteString(W, "decode "); Texts.WriteString(W, S.s); Texts.WriteLn(W); F := Files.Old(S.s);
			IF F # NIL THEN
				Files.Set(R, F, 0); err := FALSE; eof := FALSE; pos := 0; Get;
				offH := 0; d := 0; REPEAT Line UNTIL err OR (ch = 0X);
				IF ~eof THEN Err("EOF expected") END; CheckD
			ELSE Texts.WriteString(W, " not found"); Texts.WriteLn(W)
			END;
			Texts.Append(Oberon.Log(**), W.buf)
		END;
		(*Oberon.Collect(0)*)
	END DecHex;

BEGIN Texts.OpenWriter(W); Texts.WriteString(W, "O7ARMv7MTool 19.9.2014");
	Texts.WriteLn(W); Texts.Append(Oberon.Log(**), W.buf)
END O7ARMv7MTool.
