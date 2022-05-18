import Signal from "@rbxts/signal";
import CharacterModel from "./CharacterModel";
import CharacterRecord from "./CharacterRecord";
import ClientChickynoid from "./ClientChickynoid";

/** @client */
export namespace ChickynoidClient {
	export interface ClientConfig {
		/** If you're slower than this, your step will be broken up. */
		fpsMin: number;
		/** Think carefully about changing this! Every extra frame clients make, puts load on the server. */
		fpsMax: number;

		useSubFrameInterpolation: boolean;
		/** Show movement debug in FPS graph. */
		showDebugMovement: boolean;
	}

	export let config: ClientConfig;
	export let characterModel: CharacterModel | undefined;
	export let estimatedServerTime: number;
	export let estimatedServerTimeOffset: number;
	export let startTime: number;

	export let OnNetworkEvent: Signal<(event: unknown) => void>;

	/**
	 * Creates connections so that Chickynoid can run on the client. Specifically, it connects to relevant networking and
	 * RunService events.
	 */
	export function Setup(this: typeof ChickynoidClient): void;

	export function GetCharacters(this: typeof ChickynoidClient): CharacterRecord[];

	export function RegisterMod(this: typeof ChickynoidClient, mod: ModuleScript): void;

	export function RegisterModsInContainer(this: typeof ChickynoidClient, container: Instance): void;

	export function GetClientChickynoid(this: typeof ChickynoidClient): ClientChickynoid;

	export function DebugMarkAllPlayers(this: typeof ChickynoidClient, text: string): void;
}

/** @client */
export * from "./WeaponsClient";
