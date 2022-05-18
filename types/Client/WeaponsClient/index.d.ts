import Signal from "@rbxts/signal";
import { ChickynoidClient } from "..";
import { WeaponModule } from "../../Shared/WeaponModule";

/** @client */
export namespace WeaponsClient {
	export let OnBulletImpact: Signal<(client: typeof ChickynoidClient, event: unknown) => void>;

	export function GetWeaponModuleByWeaponId(self: typeof WeaponsClient, weaponId: number): WeaponModule;
}
