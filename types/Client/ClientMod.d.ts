export interface ClientMod {
	Step(deltaTime: number): void;

	Setup(): void;

	GenerateCommand(command: unknown, serverTime: number, deltaTime: number): unknown;
}
