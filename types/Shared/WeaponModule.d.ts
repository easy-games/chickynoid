import PlayerRecord from "../Server/PlayerRecord";
import WeaponsServer from "../Server/WeaponsServer";

export interface WeaponModule<State = {}, Command = {}> {
	clientState: State;
	serverState: State;
	name?: string;
	client?: unknown;
	/** Only available on server. */
	weaponModule: WeaponsServer;
	preservePredictedStateTimer: number;
	serverStateDirty: boolean;
	playerRecord?: PlayerRecord;
	previousState: State;
	state: State;
	weaponId: number;
	totalTime: number;

	ClientThink(deltaTime: number): void;

	ClientProcessCommand(command: unknown): void;

	ClientSetup(): void;

	ClientEquip(): void;

	ClientDequip(): void;

	ClientOnBulletImpact(client: unknown, event: unknown): void;

	ServerThink(deltaTime: number): void;

	ServerProcessCommand(command: unknown): void;

	ServerSetup(): void;

	ServerEquip(): void;

	ServerDequip(): void;

	SetPredictedState(): void;
}
