import { SimulationConstants } from "./simulation-constants";
import { SimulationState } from "./simulation-state";

type ThinkFunc = (simulation: typeof Simulation, command: unknown) => void;

interface Simulation {
	state: SimulationState;
	constants: SimulationConstants;

	RegisterMoveState(
		name: string,
		/** Runs while active */
		activeThink: unknown,
		/** Runs every frame. */
		alwaysThink: unknown,
		startState: unknown,
		/** Cleanup */
		lastThink: unknown | undefined,
	): void;

	GetMoveState(): string;
	SetMoveState(moveState: string): void;
}

interface SimulationConstructor {
	/**
	 * Constructed internally. Do not use directly.
	 * @private
	 */
	new (): Simulation;
}

declare const Simulation: SimulationConstructor;
export = Simulation;
