import Signal from "@rbxts/signal";

export namespace CollisionModule {
	export let loadProgress: number;
	export const OnLoadProgressChanged: Signal<(progress: number) => void>;

	export function ProcessCollisionOnInstance(this: typeof CollisionModule, instance: Instance): void;
	export function ClearCache(this: typeof CollisionModule): void;
}
