import Simulation from "../Simulation";

export interface CharacterMod {
	Setup(simulation: Simulation): void;
}
