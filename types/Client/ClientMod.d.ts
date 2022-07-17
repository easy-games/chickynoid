export interface ClientMod {
	/** Determines the order in which this client mod will be called. Valid values are 0 - 5. 0 is first, 5 is last*/
	PRIORITY?: number;

	Step(deltaTime: number): void;

	Setup(): void;

	GenerateCommand(command: unknown, serverTime: number, deltaTime: number): unknown;
}
