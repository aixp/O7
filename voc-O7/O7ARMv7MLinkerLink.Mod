MODULE O7ARMv7MLinkerLink;

	(* Alexander Shiryaev, 2023.10 *)

	IMPORT O7ARMv7MLinker, Platform;

BEGIN O7ARMv7MLinker.Link;
	IF O7ARMv7MLinker.res # 0 THEN Platform.Exit(1) END
END O7ARMv7MLinkerLink.
