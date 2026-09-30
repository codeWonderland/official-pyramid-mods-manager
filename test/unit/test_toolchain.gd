extends GutTest

# Tests the contributor toolchain check: git, the GitHub CLI, and a GitHub
# sign-in, each with guidance when it's missing.


func _check(runner: FakeCommandRunner) -> Dictionary:
	return await Toolchain.new(runner).check()


func test_everything_in_place_is_ready() -> void:
	var runner := (
		FakeCommandRunner
		. new()
		. on("git --version", 0, "git version 2.43.0")
		. on("gh --version", 0, "gh version 2.45.0 (2024-03-04)\nhttps://github.com/cli/cli")
		. on("gh api user", 0, "alice")
	)

	var report := await _check(runner)

	assert_true(report.ready, "ready to contribute")
	assert_eq(report.git_version, "git version 2.43.0", "git version read")
	assert_eq(report.gh_version, "gh version 2.45.0 (2024-03-04)", "first line of gh's version")
	assert_eq(report.user, "alice", "signed-in account")
	assert_eq(report.problems, [], "nothing to fix")


func test_the_check_never_changes_global_git_settings() -> void:
	# gh's "auth setup-git" rewrites the player's global git config; the check
	# must only look, never touch.
	var runner := FakeCommandRunner.new().on("gh api user", 0, "alice")

	await _check(runner)

	assert_false(runner.called("setup-git"), "nothing configured globally")
	for line in runner.calls:
		assert_false(line.contains("config --global"), "no global config written: %s" % line)


func test_missing_git_says_where_to_get_it() -> void:
	var runner := FakeCommandRunner.new().on("git --version", CommandRunner.NOT_FOUND)

	var report := await _check(runner)

	assert_false(report.ready, "not ready")
	assert_false(report.git_ok, "git missing")
	assert_eq(report.problems[0].link, Toolchain.GIT_DOWNLOAD, "points at the git download")


func test_missing_gh_says_where_to_get_it_and_skips_sign_in() -> void:
	var runner := FakeCommandRunner.new().on("gh --version", CommandRunner.NOT_FOUND)

	var report := await _check(runner)

	assert_false(report.gh_ok, "gh missing")
	assert_eq(report.problems.size(), 1, "one problem, not a second about signing in")
	assert_eq(report.problems[0].link, Toolchain.GH_DOWNLOAD, "points at the gh download")
	assert_false(runner.called("gh auth status"), "no point asking an absent gh")


func test_signed_out_gives_the_command_to_run() -> void:
	var runner := FakeCommandRunner.new().on(
		"gh auth status", 1, "You are not logged into any GitHub hosts."
	)

	var report := await _check(runner)

	assert_false(report.signed_in, "signed out")
	assert_false(report.ready, "not ready")
	assert_eq(report.problems[0].command, Toolchain.SIGN_IN_COMMAND, "the command to sign in")


func test_everything_missing_is_reported_together() -> void:
	var runner := FakeCommandRunner.new().on("git --version", CommandRunner.NOT_FOUND).on(
		"gh --version", CommandRunner.NOT_FOUND
	)

	var report := await _check(runner)

	assert_eq(report.problems.size(), 2, "git and gh both listed, so one visit fixes both")
