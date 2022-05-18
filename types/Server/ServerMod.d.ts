import { ChickynoidServer } from ".";

export interface ServerMod {
	Step(client: typeof ChickynoidServer, deltaTime: number): void;

	Setup(client: typeof ChickynoidServer): void;
}
