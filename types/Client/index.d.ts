import Signal from "@rbxts/signal";
import CharacterModel from "./CharacterModel";
import CharacterRecord from "./CharacterRecord";
import ClientChickynoid from "./ClientChickynoid";
import { WeaponsClient } from "./WeaponsClient";

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

	export let fpsMax: number;
	export let fpsMin: number;
	export let fpsIsCapped: boolean;
	export let interpolationBuffer: number;

	export let characterModel: CharacterModel | undefined;
	export let estimatedServerTime: number;
	export let estimatedServerTimeOffset: number;
	export let startTime: number;
	export let weaponsClient: typeof WeaponsClient;

	export let OnNetworkEvent: Signal<(event: unknown) => void>;
	export let OnCharacterModelCreated: Signal<(characterModel: CharacterModel) => void>;
	export let OnCharacterModelDestroyed: Signal<(characterModel: CharacterModel) => void>;

	export const flags: {
		HANDLE_CAMERA: boolean;
	};
	/**
	 * Creates connections so that Chickynoid can run on the client. Specifically, it connects to relevant networking and
	 * RunService events.
	 */
	export function Setup(this: typeof ChickynoidClient): void;

	/**
	 * Map of userId to CharacterRecord.
	 */
	export function GetCharacters(this: typeof ChickynoidClient): Map<number, CharacterRecord>;

	export function RegisterMod(this: typeof ChickynoidClient, mod: ModuleScript): void;

	export function GetClientChickynoid(this: typeof ChickynoidClient): ClientChickynoid;

	export function DebugMarkAllPlayers(this: typeof ChickynoidClient, text: string): void;

	/** Set a callback for custom models. */
	export function SetCharacterModel(
		this: typeof ChickynoidClient,
		callback: (userId: number) => Model | undefined,
	): void;
}
export * from "./CharacterMod";
export { ClientMods } from "./ClientMods";

