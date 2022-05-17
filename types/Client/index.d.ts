import CharacterModel from "./CharacterModel";
import CharacterRecord from "./CharacterRecord";

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

	/**
	 * Creates connections so that Chickynoid can run on the client. Specifically, it connects to relevant networking and
	 * RunService events.
	 */
	export function Setup(this: typeof ChickynoidClient): void;

	export function GetCharacters(this: typeof ChickynoidClient): CharacterRecord[];

	export function RegisterMod(mod: ModuleScript): void;

	export function RegisterModsInContainer(container: Instance): void;
}
