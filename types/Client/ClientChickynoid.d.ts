import CharacterData from "../Shared/CharacterData";
import Simulation from "../Simulation";

interface ClientChickynoid {
	simulation: Simulation;
	ping: number;

	GetPlayerDataByUserId(userId: number): CharacterData;
}

interface ClientChickynoidConstructor {
	/**
	 * Constructed internally. Do not use directly.
	 * @private
	 */
	new (): ClientChickynoid;
}

declare const ClientChickynoid: ClientChickynoidConstructor;
export = ClientChickynoid;
