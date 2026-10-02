class_name FighterController
extends RefCounted
## Produces one packed input (see InputBuffer) per tick. The player and the AI share
## this interface, so the AI plays by exactly the same rules as a human.


func read(_fighter: Fighter) -> int:
	return InputBuffer.pack(InputBuffer.NEUTRAL, 0)


## x: -1 back, 0, 1 forward. y: -1 down, 0, 1 up. Returns numpad direction 1-9.
static func to_numpad(x: int, y: int) -> int:
	return 5 + x + 3 * y
