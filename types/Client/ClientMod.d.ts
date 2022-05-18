import { ChickynoidClient } from ".";

export interface ClientMod {
	Step(client: typeof ChickynoidClient, deltaTime: number): void;

	Setup(client: typeof ChickynoidClient): void;

	GenerateCommand(client: typeof ChickynoidClient, command: unknown, serverTime: number, deltaTime: number): unknown;
}
