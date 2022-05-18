interface SimulationState {
	pos: Vector3;
	vel: Vector3;
	pushDir: Vector2;
	jump: number;
	angle: number;
	targetAngle: number;
	stepUp: number;
	inAir: number;
	jumpThrust: number;
	pushing: number;
	characterData: unknown;
}

interface SimulationConstants {
	maxSpeed: number;
	airSpeed: number;
	accel: number;
	airAccel: number;
	jumpPunch: number;
	turnSpeedFrac: number;
	runFriction: number;
	brakeFriction: number;
	maxGroundSlope: number;
	jumpThrustPower: number;
	jumpThrustDecay: number;
	pushSpeed: number;
	stepSize: number;
}

interface Simulation {
	state: SimulationState;
	constants: SimulationConstants;
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
