/** @client */
export namespace ServerMods {
	export function RegisterMods(
		this: typeof ServerMods,
		scope: "servermods" | "characters" | "weapons",
		folder: Instance,
	): void;
}
