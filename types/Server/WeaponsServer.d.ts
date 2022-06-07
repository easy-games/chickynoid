import { ChickynoidServer } from ".";
import PlayerRecord from "./PlayerRecord";

interface WeaponsServer {
	QueryBullet(
		playerRecord: PlayerRecord,
		server: typeof ChickynoidServer,
		origin: Vector3,
		dir: Vector3,
		serverTime: number,
		debugText: string,
		raycastParams: RaycastParams,
	): LuaTuple<
		[pos: Vector3, normal: Vector3, otherPlayerRecord: PlayerRecord | undefined, hitInstance: BasePart | Terrain]
	>;

	QueryShotgun(
		playerRecord: PlayerRecord,
		server: typeof ChickynoidServer,
		origins: Vector3[],
		directions: Vector3[],
		serverTime: number,
		debugText: string,
		raycastParams: RaycastParams,
	): Array<{
		pos: Vector3;
		normal: Vector3;
		hitInstance: BasePart | Terrain;
		otherPlayerRecord: PlayerRecord | undefined;
		origin: Vector3;
		dir: Vector3;
	}>;
}

interface WeaponsServerConstructor {
	/**
	 * Constructed internally. Do not use directly.
	 * @private
	 */
	new (): WeaponsServer;
}

declare const WeaponsServer: WeaponsServerConstructor;
export = WeaponsServer;
