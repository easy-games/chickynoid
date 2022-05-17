interface WeaponModule {
	ClientThink(deltaTime: number): void;

	ClientProcessCommand(command: unknown): void;

	ClientSetup(): void;

	ClientEquip(): void;

	ClientDequip(): void;

	ClientOnBulletImpact(client: unknown, event: unknown): void;

	ServerThink(deltaTime: number): void;

	ServerProcessCommand(command: unknown): void;

	ServerEquip(): void;

	ServerDequip(): void;
}

interface WeaponModuleConstructor {
	/**
	 * Constructed internally. Do not use directly.
	 * @private
	 */
	new (): WeaponModule;
}

declare const WeaponModule: WeaponModuleConstructor;
export = WeaponModule;
