extends GutTest

# Tests ModsRepo's GitHub side with a fake runner: what it asks git and gh to do
# when submitting, where it pushes, and how it reads pull requests back.

const PATH: String = "/tmp/not-a-real-mods-copy"
const CHANGED: String = ' M PACKS/alpha/p2.png\n?? "PACKS/beta pack/b1.png"\n'


func _repo(runner: FakeCommandRunner) -> ModsRepo:
	return ModsRepo.new(runner, PATH)


func _submitting(push_access: bool) -> FakeCommandRunner:
	return (
		FakeCommandRunner
		. new()
		. on("status --porcelain", 0, CHANGED)
		. on("gh api user --jq", 0, "alice\t42")
		. on("config user.email", 0, "alice@example.com")
		. on(".permissions.push", 0, "true" if push_access else "false")
		. on("remote get-url fork", 2, "error: No such remote 'fork'")
		. on("gh pr create", 0, "https://github.com/codeWonderland/pyramid-mods/pull/99")
	)


# --- Reading state ---


func test_changed_packs_reads_porcelain_including_spaces() -> void:
	var repo := _repo(FakeCommandRunner.new().on("status --porcelain", 0, CHANGED))

	assert_eq(await repo.changed_packs(), ["alpha", "beta pack"], "one entry per pack, spaces kept")


func test_changed_packs_skips_the_original_path_of_a_rename() -> void:
	var rename := "R  PACKS/old/b1.png -> PACKS/new/b1.png\n"
	var repo := _repo(FakeCommandRunner.new().on("status --porcelain", 0, rename))

	assert_eq(await repo.changed_packs(), ["new"], "the old path isn't mistaken for an edit")


func test_quoted_paths_are_unquoted() -> void:
	var status := '?? "PACKS/we\\"ird/b1.png"\n?? "PACKS/caf\\303\\251/b1.png"\n'

	assert_eq(
		ModsRepo.packs_from_status(status),
		["café", 'we"ird'],
		"escaped quotes and octal UTF-8 bytes both come back as written"
	)


func test_no_edits_means_no_changed_packs() -> void:
	var repo := _repo(FakeCommandRunner.new().on("status --porcelain", 0, ""))

	assert_false(await repo.has_changes(), "clean")


# --- Submitting ---


func test_submitting_with_push_access_goes_to_the_official_repo() -> void:
	var runner := _submitting(true)

	var result := await _repo(runner).submit("New Celeste pack", "Adds Celeste.")

	assert_true(result.ok, "submitted")
	assert_eq(result.url, "https://github.com/codeWonderland/pyramid-mods/pull/99", "PR address")
	assert_false(runner.called("gh repo fork"), "no fork needed")
	assert_string_contains(
		runner.first_call("push --quiet"), "-u origin mods/new-celeste-pack-", "pushed"
	)
	assert_string_contains(runner.first_call("gh pr create"), "--head codeWonderland:mods/", "head")


func test_submitting_without_push_access_forks_first() -> void:
	var runner := _submitting(false)

	var result := await _repo(runner).submit("New Celeste pack", "")

	assert_true(result.ok, "submitted")
	assert_true(runner.called("gh repo fork codeWonderland/pyramid-mods"), "forked")
	assert_string_contains(
		runner.first_call("remote add fork"), "https://github.com/alice/pyramid-mods.git", "fork"
	)
	assert_string_contains(runner.first_call("push --quiet"), "-u fork mods/", "pushed to the fork")
	assert_string_contains(runner.first_call("gh pr create"), "--head alice:mods/", "from the fork")


func test_an_existing_fork_remote_is_reused() -> void:
	# Rules answer first-match, so this runner is built fresh rather than from
	# _submitting(), whose "no such remote" rule would win.
	var runner := (
		FakeCommandRunner
		. new()
		. on("remote get-url fork", 0, "https://github.com/alice/pyramid-mods.git")
		. on("status --porcelain", 0, CHANGED)
		. on("gh api user --jq", 0, "alice\t42")
		. on("config user.email", 0, "alice@example.com")
		. on(".permissions.push", 0, "false")
	)

	await _repo(runner).submit("Update", "")

	assert_true(runner.called("remote set-url fork"), "updated in place")
	assert_false(runner.called("remote add fork"), "not added twice")


func test_submitting_uses_the_github_sign_in_for_this_copy_only() -> void:
	var runner := _submitting(true)

	await _repo(runner).submit("Update", "")

	assert_true(
		runner.called(
			"config --local --add credential.https://github.com.helper !gh auth git-credential"
		),
		"gh signs pushes in, set on this copy"
	)
	for line in runner.calls:
		assert_false(line.contains("--global"), "never the player's global config: %s" % line)


func test_the_pr_lists_the_changed_packs() -> void:
	var runner := _submitting(true)

	await _repo(runner).submit("Two packs", "Some notes.")

	var pr := runner.first_call("gh pr create")
	assert_string_contains(pr, "Some notes.", "the player's description")
	assert_string_contains(pr, "- alpha", "each changed pack")
	assert_string_contains(pr, "- beta pack", "including ones with spaces")


func test_success_returns_to_the_official_packs() -> void:
	var runner := _submitting(true)

	await _repo(runner).submit("Update", "")

	assert_eq(
		runner.calls[runner.calls.size() - 1], "git -C %s checkout --quiet main" % PATH, "main"
	)


func test_missing_identity_borrows_the_github_noreply_address() -> void:
	var runner := (
		FakeCommandRunner
		. new()
		. on("config user.email", 1, "")
		. on("status --porcelain", 0, CHANGED)
		. on("gh api user --jq", 0, "alice\t42")
		. on(".permissions.push", 0, "true")
	)

	await _repo(runner).submit("Update", "")

	assert_true(runner.called("config user.name alice"), "name from GitHub")
	assert_true(
		runner.called("config user.email 42+alice@users.noreply.github.com"), "private email"
	)


func test_an_existing_identity_is_left_alone() -> void:
	var runner := _submitting(true)

	await _repo(runner).submit("Update", "")

	assert_false(runner.called("config user.name"), "not overwritten")


func test_a_failed_push_rewinds_to_where_it_started() -> void:
	var runner := (
		FakeCommandRunner
		. new()
		. on("push --quiet", 1, "fatal: unable to access")
		. on("status --porcelain", 0, CHANGED)
		. on("gh api user --jq", 0, "alice\t42")
		. on("config user.email", 0, "a@example.com")
		. on(".permissions.push", 0, "true")
	)

	var result := await _repo(runner).submit("Update", "")

	assert_false(result.ok, "failed")
	assert_eq(result.message, "Couldn't upload your submission to GitHub.", "says what failed")
	assert_string_contains(result.detail, "unable to access", "with git's reason")
	assert_true(runner.called("reset --quiet --mixed HEAD~1"), "commit undone, edits kept")
	assert_true(runner.called("branch --quiet -D mods/update-"), "branch removed")
	assert_false(runner.called("gh pr create"), "no pull request attempted")


func test_nothing_to_submit_is_refused_up_front() -> void:
	var runner := FakeCommandRunner.new().on("status --porcelain", 0, "")

	var result := await _repo(runner).submit("Update", "")

	assert_false(result.ok, "refused")
	assert_false(runner.called("checkout"), "nothing was touched")


func test_a_title_is_required() -> void:
	var runner := FakeCommandRunner.new()

	var result := await _repo(runner).submit("   ", "")

	assert_eq(result.message, "Give your submission a title.", "asked for a title")
	assert_eq(runner.calls, [] as Array[String], "before running anything")


# --- Reading submissions back ---

# --- Pure helpers ---


func test_branch_names_are_readable_and_unique() -> void:
	assert_eq(ModsRepo.branch_name("New Celeste pack!", 1700), "mods/new-celeste-pack-1700", "slug")
	assert_eq(ModsRepo.branch_name("???", 5), "mods/update-5", "falls back when nothing's left")
	assert_eq(
		ModsRepo.branch_name("a".repeat(80), 1).length(), "mods/".length() + 40 + 2, "length capped"
	)


func test_check_summaries() -> void:
	assert_eq(ModsRepo.summarize_checks([]), "none", "no checks")
	assert_eq(
		ModsRepo.summarize_checks([{"conclusion": "SUCCESS"}, {"conclusion": "SUCCESS"}]),
		"passing",
		"all passed"
	)
	assert_eq(
		ModsRepo.summarize_checks([{"conclusion": "SUCCESS"}, {"conclusion": "FAILURE"}]),
		"failing",
		"any failure fails"
	)
	assert_eq(ModsRepo.summarize_checks([{"state": "PENDING"}]), "running", "still going")


func test_review_summaries() -> void:
	assert_eq(ModsRepo.summarize_review("APPROVED"), "approved", "approved")
	assert_eq(ModsRepo.summarize_review("CHANGES_REQUESTED"), "changes requested", "changes")
	assert_eq(ModsRepo.summarize_review(""), "awaiting review", "nothing yet")
