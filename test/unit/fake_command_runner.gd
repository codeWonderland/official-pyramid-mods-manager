class_name FakeCommandRunner extends CommandRunner

## A stand-in for CommandRunner in tests. Records every command, answers from
## scripted rules, and can hand some programs (usually git) to the real runner so
## local git behaviour is tested for real while GitHub is faked.

var calls: Array[String] = []
var real_programs: Array[String] = []
var _rules: Array[Dictionary] = []


## The first rule whose `contains` text appears in "program arg arg ..." answers.
func on(contains: String, code: int = 0, output: String = "") -> FakeCommandRunner:
	_rules.append({"contains": contains, "code": code, "output": output})
	return self


func run(program: String, args: PackedStringArray) -> Dictionary:
	var line := program + " " + " ".join(args)
	calls.append(line)

	for rule in _rules:
		if line.contains(rule.contains):
			return {"code": rule.code, "output": rule.output}

	if real_programs.has(program):
		return await super.run(program, args)

	return {"code": 0, "output": ""}


func called(contains: String) -> bool:
	for line in calls:
		if line.contains(contains):
			return true
	return false


func first_call(contains: String) -> String:
	for line in calls:
		if line.contains(contains):
			return line
	return ""
