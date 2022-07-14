import Signal from "@rbxts/signal";

interface CharacterModel {
	model?: Model;
	primaryPart?: BasePart;
	tracks: Map<string, AnimationTrack>,
	modelReady: boolean;
	modelOffset: Vector3;
	userId: number;
	animator: Animator;
	onModelCreated: Signal<(model: Model) => void>;
	onModelDestroyed: Signal<() => void>;
	template: Model;
}

interface CharacterModelConstructor {
	/**
	 * Constructed internally. Do not use directly.
	 * @private
	 */
	new (): CharacterModel;
}

declare const CharacterModel: CharacterModelConstructor;
export = CharacterModel;
