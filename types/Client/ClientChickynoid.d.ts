import Simulation from "../Simulation";

interface ClientChickynoid {
	simulation: Simulation;
	ping: number;
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
