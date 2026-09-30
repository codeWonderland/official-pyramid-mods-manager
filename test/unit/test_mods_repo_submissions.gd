extends GutTest

# Tests ModsRepo.my_submissions(): the signed-in player's open pull requests to
# the official mods, with their checks and review status.

const PATH: String = "/tmp/not-a-real-mods-copy"


func _repo(runner: FakeCommandRunner) -> ModsRepo:
	return ModsRepo.new(runner, PATH)


func _pr(number: int, login: String, decision: String = "") -> Dictionary:
	return {
		"number": number,
		"title": "PR %d" % number,
		"url": "https://github.com/codeWonderland/pyramid-mods/pull/%d" % number,
		"author": {"login": login},
		"reviewDecision": decision,
		"statusCheckRollup": [{"conclusion": "SUCCESS"}],
	}


func test_submissions_are_the_players_own_open_prs() -> void:
	var json := JSON.stringify([_pr(7, "alice", "CHANGES_REQUESTED"), _pr(8, "someone-else")])
	var runner := FakeCommandRunner.new().on("gh api user --jq", 0, "alice\t42").on(
		"gh pr list", 0, json
	)

	var result := await _repo(runner).my_submissions()

	assert_true(result.ok, "loaded")
	assert_eq(result.submissions.size(), 1, "only the player's own")
	assert_eq(result.submissions[0].number, 7, "number")
	assert_eq(result.submissions[0].checks, "passing", "checks summarised")
	assert_eq(result.submissions[0].review, "changes requested", "review summarised")


func test_submissions_do_not_rely_on_githubs_search_index() -> void:
	# "--author" goes through search, which lags a newly opened PR, so a
	# submission made seconds ago would be missing.
	var runner := FakeCommandRunner.new().on("gh api user --jq", 0, "alice\t42").on(
		"gh pr list", 0, "[]"
	)

	await _repo(runner).my_submissions()

	var listing := runner.first_call("gh pr list")
	assert_false(listing.contains("--author"), "no search-backed author filter")
	assert_false(listing.contains("--search"), "nor any other search")
	assert_string_contains(listing, "author", "author is fetched to filter on instead")


func test_submissions_need_a_signed_in_account() -> void:
	var runner := FakeCommandRunner.new().on("gh api user --jq", 1, "")

	var result := await _repo(runner).my_submissions()

	assert_false(result.ok, "can't tell whose submissions to show")
	assert_false(runner.called("gh pr list"), "without asking GitHub for PRs")


func test_unreadable_submissions_are_an_error_not_a_crash() -> void:
	var runner := FakeCommandRunner.new().on("gh api user --jq", 0, "alice\t42").on(
		"gh pr list", 0, "not json"
	)

	var result := await _repo(runner).my_submissions()

	assert_false(result.ok, "reported as a failure")
