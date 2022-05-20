import PlayerRecord from "./PlayerRecord";

/** @server */
export namespace Antilag {
	export const history: Array<{
		serverTime: number;
		players: Map<
			number,
			{
				record: {
					position: Vector3;
				};
			}
		>;
	}>;
	export const temporaryPositions: Map<number, Vector3>;

	export function WritePlayerPositions(this: typeof Antilag, serverTime: number): void;
	export function PushPlayerPositionsToTime(
		this: typeof Antilag,
		playerRecord: PlayerRecord,
		serverTime: number,
		debugText: string,
	): void;
	export function Pop(this: typeof Antilag): void;
}
