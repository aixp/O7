MODULE O7ARMv6MPCompile;

	(* Alexander Shiryaev, 2023.10 *)

	IMPORT O7ARMv6MP, O7S, Platform;

BEGIN O7ARMv6MP.Compile;
	IF O7S.errcnt # 0 THEN Platform.Exit(1) END
END O7ARMv6MPCompile.
