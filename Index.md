Chickynoid User Guide


# Getting Started

Be sure to read the readme.md for a project overview!

Note: For clarity, when talking about a module or file inside of chickynoid, it will be what the file is called inside the roblox workspace, not the git/rojo file location.

#### Make sure you include the contents of:

- ServerScriptService/chickynoid **(entrypoint for all server code)**
- StarterPlayer/StarterPlayerScripts/chickynoid  **(entrypoint for all client code)**
- ServerScriptService/Bots **(bot support)**
- Workspace/GameArea **(for your collision geometry)**
- ReplicatedFirst/Packages   **(everything else)**
		
Chickynoid also comes with a lot of **OPTIONAL** example modifications on how to do various things like implement hitpoints and kill bricks.  Everything inside of the /examples/ folders are optional, but provide great insight in how to do various things.

#### The examples are located here:
- ReplicatedFirst/Examples
- ServerScriptService/Examples


# Major Systems

## Mods
### About Mods

Mods are dynamically loaded modules that get hooked into the existing systems of chickynoid, so that you don't have to change the core code to extend the functionality.  

Mods do stuff like implement weapons, hitpoints, custom character movement, etc etc.

If you find you need to extend the core systems to do something that the mod system can't do, consider making it compatible with the mod system and opening a PR :)


### Configuration:

You can easily create your own mod systems, or change the location of the existing systems by editing the following files and changing where the systems register to:

**StarterPlayer/StarterPlayerScript/chickynoid** for client startup 
**ServerScriptService/chickynoid** for server startup 

### Adding a new Mod

Adding a new mod is just adding a module file to the right folder location. Mods don't require you to do anything special, but if you name certain methods they'll be called at the right time with the right parameters.
eg: 
#### *function module:Setup(_client | _server)* 
will be invoked by all modules when they are loaded

### Currently available mod systems:

**Client:**
- clientmods

**Server:**
- servermods

**Shared:**
- characters
- weapons


### Client mods implement:
#### *Setup(_client)*
Perform any setup code you require. 
_client is the table of the ChickynoidClient module

#### *{model} GetCharacterModel(userId)*
*returns: a model instance*
Return a custom character model. 

#### *Step(_client, deltaTime)*
Runs every frame (heartbeat)

#### *GenerateCommand(command, serverTime, deltaTime)*
*returns: a new command table*
Gives a mod a chance to append extra command data to the command stream, to be seen by the simulation code on client and server. Commands are the only intended way to pass input data into the player simulation state.

eg: extra button presses, item activations, etc.




# WIP
      
  * Server
    * Player management
    * Character Types
    * Bots
    * Per player replication
    * WorldData
    
    
  * Client
    * Character Rendering
    * The command system
    * The netgraph
    * Framerate caps and timing
  
  * Simulation
    * Chickynoid movement
      strafe jumping, ground accel, stepup, stepdown, crashland
    * MovementTypes
    * CharacterData
    * MathUtils

  * Weapon Systems
    * Weapon system overview
    * Rayscan weapons (Machinegun)
    * Projectile weapons (ProjectileSniper)
    * Antilag
      
  * Custom Collision Detection
    * Shapecasting
    * TerrainCollision
    * MinkowskiSums
     
* "Vendor"
  * BitBuffer
  * DeltaTable
  * FastSignal
  * QuickHull2
  * TrianglePart  
  
* The examples
  * Flying
  * JumpPads
  * NicerHumanoid
  * Basic Culling
  * Basic Weapons
  * Hitpoints
  * Killbrick
  * NetgraphHotkeys

* How To
  * How to access all the player models on the client
  * How to spawn in a bot as a different character
  * How to Add a new Movetype eg: doublejump
  
* The security features
  * Speed cheat detection
  * Command stream underrun detection
  * Mispredicts
 
 
* Limitations
Cant interact with physics objects due to being apart from the simulation
Collision with terrain is imperfect

 
* Whats next
When Roblox provide shapecasts, the collision library will be replaced by native roblox collision code
When roblox provides unreliable remotes, the client upstream remote for commands will be replaced, which will prevent logjams
When roblox provides more tools for serializing/sharing context data for parallel luau, a parallel version will be released

You can also always reach out on twitter or discord, I do take the occasional commission
