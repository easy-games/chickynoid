import Signal from "@rbxts/signal";
import { ChickynoidServer } from ".";
import Simulation from "../Simulation";
import PlayerRecord from "./PlayerRecord";

interface ServerChickynoid {
	playerRecord: PlayerRecord;
	hitBox: Part;
	simulation: Simulation;
	bufferedCommandTime: number;

	hitBoxCreated: Signal<(hitBox: Part) => void>;

	SetPosition(position: Vector3, teleport: boolean): void;
	GetPosition(): Vector3;

	HandleEvent(server: typeof ChickynoidServer, event: unknown): void;

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
