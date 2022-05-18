import { ChickynoidServer } from ".";

export interface ServerMod {
	Step(server: typeof ChickynoidServer, deltaTime: number): void;

	Setup(server: typeof ChickynoidServer): void;
}
