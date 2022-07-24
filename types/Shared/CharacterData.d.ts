interface CharacterData {
	serialized: {
		pos: Vector3;
		angle: number;
		stepUp: number;
		flatSpeed: number;
	};

	SetTargetPosition(position: Vector3, teleport: boolean): void;
	GetPosition(): Vector3;
	SetAngle(angle: number): void;
	GetAngle(): number;
	SmoothPosition(deltaTime: number, smoothFactor: number): void;
}

export = CharacterData;
