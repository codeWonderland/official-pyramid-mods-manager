extends GutTest

# Tests the real CommandRunner: it runs a program off the main thread and
# reports one that can't be started.


func test_runs_a_program_and_returns_its_output() -> void:
	var result := await CommandRunner.new().run("git", ["--version"])

	assert_eq(result.code, 0, "exit code")
	assert_string_starts_with(result.output, "git version", "its output")


func test_a_missing_program_is_reported_not_crashed() -> void:
	var result := await CommandRunner.new().run("definitely-not-a-real-program-xyz", [])

	assert_eq(result.code, CommandRunner.NOT_FOUND, "reported as not found")


func test_a_failing_command_carries_its_message() -> void:
	var result := await CommandRunner.new().run("git", ["not-a-git-command"])

	assert_ne(result.code, 0, "non-zero exit")
	assert_string_contains(result.output, "not a git command", "with git's explanation")


func test_empty_arguments_survive_on_windows() -> void:
	# Windows builds one command line from the arguments, and an empty one
	# vanished: git config then saw a missing value ("should be 2").
	var args := PackedStringArray(["config", "--local", "--add", "credential.helper", ""])

	var windows := CommandRunner.platform_args(args, true)
	assert_eq(windows[4], '""', "the empty helper goes as a pair of quotes")
	assert_eq(windows.size(), args.size(), "nothing dropped or added")
	assert_eq(windows[3], "credential.helper", "other arguments untouched")

	assert_eq(CommandRunner.platform_args(args, false), args, "elsewhere, passed as they are")
