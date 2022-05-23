import Signal from "@rbxts/signal";

interface CharacterModel {
	model: Model;
	modelReady: boolean;
	modelOffset: Vector3;
	userId: number;
	animator: Animator;
	onModelCreated: Signal<(model: Model) => void>;
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
