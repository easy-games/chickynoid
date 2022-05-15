interface CharacterModel {
	model: Model;
	modelReady: boolean;
	modelOffset: Vector3;
	userId: number;
	animator: Animator;
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
