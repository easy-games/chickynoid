import PlayerRecord from "./PlayerRecord";

interface ServerChickynoid {
	playerRecord: PlayerRecord;
	hitBox: Part;

	SetPosition(position: Vector3): void;
	GetPosition(): Vector3;

	Destroy(): void;
}

interface ServerChickynoidConstructor {
	/**
	 * Constructed internally. Do not use directly.
	 * @private
	 */
	new (): ServerChickynoid;
}

declare const ServerChickynoid: ServerChickynoidConstructor;
export = ServerChickynoid;
