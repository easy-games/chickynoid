export namespace MathUtils {
	export function GroundAccelerate(
		this: typeof MathUtils,
		wishDir: Vector3,
		wishSpeed: number,
		accel: number,
		velocity: Vector3,
		dt: number,
	): Vector3;

	export function VelocityFriction(this: typeof MathUtils, vel: Vector3, fric: number, dt: number): Vector3;

	export function PlayerVecToAngle(this: typeof MathUtils, vec: Vector3): number;

	export function LerpAngle(this: typeof MathUtils, a0: number, a1: number, frac: number): number;

	export function SmoothLerp<T>(this: typeof MathUtils, a0: T, a1: T, fraction: number, deltaTime: number): T;
}
