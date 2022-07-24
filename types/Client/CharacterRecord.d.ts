import CharacterModel from "./CharacterModel";

interface CharacterRecord {
	userId: number;
	characterModel: CharacterModel;
	position: Vector3;
	frame: number;
	characterData: CharacterData;
}

interface CharacterData {
	pos: Vector3;
	angle: number;
	stepUp: number;
	flatSpeed: number;
}

export = CharacterRecord;
