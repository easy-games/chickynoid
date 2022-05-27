import Simulation from "../Simulation";

export interface CharacterModel {
	Setup(simulation: Simulation): void;
}
