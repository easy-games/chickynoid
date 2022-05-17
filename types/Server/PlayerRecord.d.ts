import Signal from "@rbxts/signal";
import ServerChickynoid from "./ServerChickynoid";

interface PlayerRecord {
	userId: number;
	player?: Player;
	allowedToSpawn: boolean;
	respawnDelay: number;
	respawnTime: number;
	slot: number;

	/** True if the player is a bot. */
	dummy: boolean;

	chickynoid: ServerChickynoid;

	OnBeforePlayerSpawn: Signal<() => void>;

	SendEventToClient(event: unknown): void;
	SendEventToClients(event: unknown): void;

	Despawn(): void;
	Spawn(): ServerChickynoid;
}

interface PlayerRecordConstructor {
	/**
	 * Constructed internally. Do not use directly.
	 * @private
	 */
	new (): PlayerRecord;
}

declare const PlayerRecord: PlayerRecordConstructor;
export = PlayerRecord;
