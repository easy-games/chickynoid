import PlayerRecord from "../Server/PlayerRecord";

export interface WeaponModule<State = {}, Command = {}> {
	clientState: State;
	serverState: State;
	name?: string;
	client?: unknown;
	weaponModule?: unknown;
	preservePredictedStateTimer: number;
	serverStateDirty: boolean;
	playerRecord?: PlayerRecord;
	previousState: State;
	state: State;

	ClientThink(deltaTime: number): void;

	ClientProcessCommand(command: unknown): void;

	ClientSetup(): void;

	ClientEquip(): void;

	ClientDequip(): void;

	ClientOnBulletImpact(client: unknown, event: unknown): void;

	ServerThink(deltaTime: number): void;

	ServerProcessCommand(command: unknown): void;

	ServerEquip(): void;

	ServerDequip(): void;
}
