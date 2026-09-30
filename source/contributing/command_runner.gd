class_name CommandRunner extends RefCounted

## Runs an external program - git or gh - on a background thread, so a clone or
## push never freezes the window. Everything that talks to git or GitHub goes
## through here, which is what lets tests swap in a fake.

## Exit code reported when the program could not be started at all, usually
## because it isn't installed or isn't on the PATH.
const NOT_FOUND: int = -1


## Runs `program` with `args` and returns { "code": int, "output": String } once it
## exits. Output combines stdout and stderr, which is what the error messages
## shown to the player need.
func run(program: String, args: PackedStringArray) -> Dictionary:
	var thread := Thread.new()
	thread.start(_execute.bind(program, args))

	var tree := Engine.get_main_loop() as SceneTree
	while thread.is_alive():
		await tree.process_frame

	return thread.wait_to_finish()


func _execute(program: String, args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var code := OS.execute(program, args, output, true)
	var text := "".join(output).strip_edges()

	# Windows reports a program that can't be started as -1; Linux and macOS
	# start it through the shell, which exits 127 with "not found". Treat both
	# the same so "is it installed?" guidance shows up everywhere.
	if code == 127 and text.contains("not found"):
		code = NOT_FOUND

	return {"code": code, "output": text}
