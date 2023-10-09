MODULE O7ARMv6MLinkerLink;

	(* Alexander Shiryaev, 2023.10 *)

	IMPORT O7ARMv6MLinker, Platform;

BEGIN O7ARMv6MLinker.Link;
	IF O7ARMv6MLinker.res # 0 THEN Platform.Exit(1) END
END O7ARMv6MLinkerLink.
