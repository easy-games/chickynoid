Chickynoid Documentation Overview

Note: For clarity, when talking about a module or file inside of chickynoid, it will be what the file is called inside the roblox workspace, not the git/rojo file location.

* Setting up
  * "GameArea" Folder
  * "Examples"

* Major Systems

  * "Mods"
      
  * Server
    * Player management
    * Character Types
    * Bots
    * Per player replication
    
    
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

You can also always reach out on twitter or discord, I do take the occasional comission :)
