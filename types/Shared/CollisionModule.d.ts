import Signal from "@rbxts/signal";

export namespace CollisionModule {
	export let loadProgress: number;
	export const OnLoadProgressChanged: Signal<(progress: number) => void>;
}
