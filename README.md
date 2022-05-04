# Chickynoid

A server-authoritative networking character controller for Roblox.

Maintained and written by MrChickenRocket and Brooke.

A demo place of Chickynoid can be found here, or under the `example/` directory:

https://www.roblox.com/games/8289135181/Chickynoid

### ___Massive Work In Progress___

Fair warning, this is not ready for production in it's current form.
Feel free to have a look at it and see how it does what it does, though!

<!--moonwave-hide-before-this-line-->

### Thankyous!

Special thanks to https://easy.gg/ who are currently sponsoring Chickynoid's development! 

## 

## What is it?

Chickynoid is intended to be a hard replacement for roblox "humanoid" based characters.
It consists of the chickynoid character controller simulation, a character 'renderer', and a replication framework on the client and server for managing player connections and network replication. 

Because of how invasive it is and how it works, it's never going to be a drag-and-drop replacement for characters in your existing game. If you're not comfortable doing some serious engineering, this project is probably not for you.



## What does it do?

Chickynoid heavily borrows from the same principles that games like quake, cod, overwatch, and other first person shooters use to prevent fly hacking, teleporting, and other "typical" character hacks that roblox is typically vulnerable to.

It implements a full character controller, character physics, replication, and world collision using it's own math and systems (Spherecast when pls roblox?), and trusts nothing from the client except input directions and buttons (and to a limited degree dt).

It implements "rollback" style networking on the client, so if the server disagrees about the results of your input, the client corrects to where it should be based on the remaining unconfirmed input.


## What are the benefits

Players can't move cheat with this. At all*
The version of the chickynoid on the server is ground-truth, so its perfect for doing server-side checks for touching triggers and other gameplay uses that humanoid isn't good at.
The chickynoid player controller code is fairly straightforward, and is more akin to a typical first person shooter player controller so slides along walls and up stairs in a generally pleasing way.

Turn speed, braking, max speed, "step up size" and acceleration are much easier to tune than in default roblox.
 * That's the hope anyway. We'll see what happens...


## What are the drawbacks?

The collision module is limited to parts right now and totally custom. It's designed for making rapid short-distance traces for player movement in a world made out of parts, and not much else.

This doesn't replace even a significant subset of what humanoids currently do. It's a platforming character and not much else.

Your character is a box, not a nice physically accurate mess like roblox uses.

## Whats *todo*?

- ~~Buffer underrun detection "Antiwarp" (so technically freezing your character is still possible right now)~~
- ~~Delta time validation (so technically speed cheating is still possible right now)~~
- ~~More tweaks to character rendering (hip height)~~
- ~~Handling player death, resetting, teleporting.~~


## How does it do it?

Rollback networking is just a new name for a really old technique I think was invented first by John Carmack in the quake series?

The idea is that the real ground-truth version of your player only exists on the server, and the client sends inputs to the server to move it around.

The rest of it is just smoke and mirrors to make this still feel good and not laggy for the player, which is sometimes called player prediction.

A main concept is the "command". Every frame the client generates a command, applies it to their local copy of the character (causing the player to simulate for 1 frame), and sends the same input to the server, which then also simulates for 1 frame.

The server, because it owns the authoritative version of the characters and has done all of the same moves, tells the player what really happened. 

If the client disagrees, this is called a mispredict, and forces a resimulation (or rollback!). What this means is the client resets to the last known good state from the server, and then **instantly** re-applies all of the remaining unconfirmed commands to put the player back exactly where they were. If it all goes well, visually, the player should see little to no difference, and the game continues. If it doesn't go well, the player will feel a "tug" to correct them.


## What cheating does this prevent?

We completely eliminate clipping/geometry hacks, teleport hacks, and fly hacks.

This _almost entirely_ eliminates lag hacks (freeze your window) and speed hacks.

We make a good effort to detect speed and lag hacks by watching the stream of incoming commands and looking for problems. A speed hack tries to tell the server to simulate more time than has actually passed, which we can detect and prevent. 

A lag hack is generally you are not sending enough commands, or asking for enough simulation time to pass. We can detect that too. Unfortunately these have to tested with some tolerances because peoples network connections are wobbly. The worst that happens is you'll mispredect and feel a lag spike.

If a player "underruns" or "lags", we also generate fake commands to catch them back up. This stops their avatar from freezing in the world.

You can see what is going on inside ServerChickynoid.lua


## Is this compatible with FPS unlocking?

Yes, although every extra frame you generate makes extra work for the server. It would be reasonable for the server to throttle you if you go over say, 200fps. Right now you'll start deliberately lagging if you go to 500fps, but that's just some test code right now.

Also, the physics simulation produces ever so slightly different results at different framerates, so there is some debates about the correct way to go about this.
