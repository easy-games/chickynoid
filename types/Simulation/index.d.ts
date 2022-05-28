import { SimulationConstants } from "./simulation-constants";
import { SimulationState } from "./simulation-state";

type ThinkFunc = (simulation: typeof Simulation, command: unknown) => void;

interface Simulation {
	userId: number | undefined;
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

	ProjectVelocity(
		startPos: Vector3,
		startVel: Vector3,
		deltaTime: number,
	): LuaTuple<[movePos: Vector3, moveVel: Vector3, hitSomething: boolean]>;

	DoGroundCheck(pos: Vector3): unknown | undefined;
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
