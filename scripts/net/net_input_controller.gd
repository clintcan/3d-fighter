class_name NetInputController
extends FighterController
## Feeds a fighter the screen-relative input that RollbackSession chose for the tick being
## simulated (confirmed, local, or predicted), converted to facing-relative at read time.

var raw := InputBuffer.pack(InputBuffer.NEUTRAL, 0)


func read(fighter: Fighter) -> int:
	return PlayerController.to_facing(raw, fighter)
