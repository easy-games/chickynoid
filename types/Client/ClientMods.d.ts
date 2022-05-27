/** @client */
export namespace ClientMods {
	export function RegisterMods(
		this: typeof ClientMods,
		scope: "clientmods" | "characters" | "weapons",
		folder: Instance,
	): void;
}
