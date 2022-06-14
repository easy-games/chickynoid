import { SimulationConstants } from "./simulation-constants";
import { SimulationState } from "./simulation-state";

type ThinkFunc = (simulation: typeof Simulation, command: unknown) => void;

interface Simulation {
	state: SimulationState;
	constants: SimulationConstants;
	userId: number;
	lastGround: unknown | undefined;

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

	GetMoveState(): {
		name: string;
	};
	SetMoveState(moveState: string): void;

	SetPosition(position: Vector3, teleport: boolean): void;
	SetAngle(angle: number, teleport: boolean): void;

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
