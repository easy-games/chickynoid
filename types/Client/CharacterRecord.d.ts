import CharacterModel from "./CharacterModel";

interface CharacterRecord {
	userId: number;
	characterModel: CharacterModel;
	position: Vector3;
}

export = CharacterRecord;
