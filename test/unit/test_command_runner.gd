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
