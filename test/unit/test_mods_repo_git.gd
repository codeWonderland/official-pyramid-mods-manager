extends GutTest

# Tests ModsRepo against real git. A bare repository on disk stands in for GitHub
# (only the gh calls are faked), so cloning, refreshing without losing edits,
# and submitting are exercised the way they really run.

var _root: String
var _upstream: String
var _seed: String
var _runner: FakeCommandRunner
var _repo: ModsRepo


func before_each() -> void:
	_root = ProjectSettings.globalize_path("user://test_modsrepo_%d" % randi())
	_upstream = _root.path_join("upstream.git")
	_seed = _root.path_join("seed")
	DirAccess.make_dir_recursive_absolute(_root)

	_git_raw(["init", "--quiet", "--bare", "--initial-branch=main", _upstream])
	_git_raw(["clone", "--quiet", _upstream, _seed])
	_write(_seed, "PACKS/alpha/b1.png", "back")
	_write(_seed, "PACKS/alpha/p1.png", "primary")
	_commit_seed("Initial packs")

	_runner = FakeCommandRunner.new()
	_runner.real_programs = ["git"] as Array[String]
	_repo = ModsRepo.new(_runner, _root.path_join("copy"))
	_repo.upstream_url = _upstream


func after_each() -> void:
	OS.execute("rm", ["-rf", _root])


func _git_raw(args: Array) -> String:
	var output: Array = []
	OS.execute("git", PackedStringArray(args), output, true)
	return "".join(output).strip_edges()


func _write(repo: String, file: String, contents: String) -> void:
	var full := repo.path_join(file)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var handle := FileAccess.open(full, FileAccess.WRITE)
	handle.store_string(contents)
	handle.close()


func _commit_seed(message: String) -> void:
	_git_raw(["-C", _seed, "add", "--all"])
	_git_raw(
		[
			"-C",
			_seed,
			"-c",
			"user.name=Seed",
			"-c",
			"user.email=seed@example.com",
			"commit",
			"--quiet",
			"-m",
			message
		]
	)
	_git_raw(["-C", _seed, "push", "--quiet", "origin", "HEAD:main"])


func _copy_file(file: String) -> String:
	return _repo.path.path_join(file)


func _fake_github(push_access: bool = true) -> void:
	_runner.on("gh api user --jq", 0, "tester\t42")
	_runner.on(".permissions.push", 0, "true" if push_access else "false")
	_runner.on("gh pr create", 0, "https://github.com/codeWonderland/pyramid-mods/pull/1")


# --- Getting the mods ---


func test_clone_downloads_the_packs() -> void:
	var result := await _repo.clone()

	assert_true(result.ok, "cloned")
	assert_true(_repo.is_cloned(), "the copy is a repository")
	assert_true(FileAccess.file_exists(_copy_file("PACKS/alpha/p1.png")), "packs are on disk")
	assert_eq(_repo.packs_path(), _repo.path.path_join("PACKS"), "the editor points here")


func test_a_fresh_copy_has_no_changes() -> void:
	await _repo.clone()
	assert_false(await _repo.has_changes(), "clean after cloning")


func test_edits_and_new_packs_are_detected_by_pack() -> void:
	await _repo.clone()
	_write(_repo.path, "PACKS/alpha/p2.png", "another primary")
	_write(_repo.path, "PACKS/beta pack/b1.png", "a new pack")

	assert_eq(await _repo.changed_packs(), ["alpha", "beta pack"], "each edited pack, once")


# --- Refreshing ---


func test_refresh_picks_up_new_official_packs() -> void:
	await _repo.clone()
	_write(_seed, "PACKS/gamma/b1.png", "published later")
	_commit_seed("Add gamma")

	var result := await _repo.refresh()

	assert_true(result.ok, "refreshed")
	assert_true(FileAccess.file_exists(_copy_file("PACKS/gamma/b1.png")), "the new pack arrived")


func test_refresh_refuses_to_throw_away_edits() -> void:
	await _repo.clone()
	_write(_repo.path, "PACKS/alpha/p2.png", "unsubmitted work")

	var result := await _repo.refresh()

	assert_false(result.ok, "stopped")
	assert_true(result.needs_confirmation, "asks first")
	assert_eq(result.changed, ["alpha"], "says which packs")
	assert_true(FileAccess.file_exists(_copy_file("PACKS/alpha/p2.png")), "the edit survives")


func test_refresh_can_discard_edits_when_told_to() -> void:
	await _repo.clone()
	_write(_repo.path, "PACKS/alpha/p2.png", "unwanted")
	_write(_repo.path, "PACKS/stray/b1.png", "unwanted too")

	var result := await _repo.refresh(true)

	assert_true(result.ok, "refreshed")
	assert_false(FileAccess.file_exists(_copy_file("PACKS/alpha/p2.png")), "edit discarded")
	assert_false(FileAccess.file_exists(_copy_file("PACKS/stray/b1.png")), "new pack discarded")
	assert_false(await _repo.has_changes(), "matches GitHub exactly")


# --- Submitting ---


func test_submitting_pushes_a_branch_and_returns_to_the_official_packs() -> void:
	await _repo.clone()
	_fake_github()
	_write(_repo.path, "PACKS/alpha/p2.png", "my new primary")

	var result := await _repo.submit("Add a primary", "One more challenge.")

	assert_true(result.ok, "submitted: %s" % result.get("detail", ""))
	var branches := _git_raw(["--git-dir", _upstream, "branch", "--list", "mods/*"])
	assert_string_contains(branches, "mods/add-a-primary-", "the branch reached the upstream")

	var branch := branches.strip_edges().trim_prefix("* ").strip_edges()
	var shipped := _git_raw(["--git-dir", _upstream, "show", "--name-only", "--format=%s", branch])
	assert_string_contains(shipped, "Add a primary", "committed with the submission title")
	assert_string_contains(shipped, "PACKS/alpha/p2.png", "carrying the edit")

	assert_eq(_git_raw(["-C", _repo.path, "branch", "--show-current"]), "main", "back on main")
	assert_false(await _repo.has_changes(), "the editor shows the official packs again")


func test_a_failed_submission_leaves_the_edits_exactly_where_they_were() -> void:
	await _repo.clone()
	_runner.on("gh pr create", 1, "GraphQL: something went wrong")
	_fake_github()
	_write(_repo.path, "PACKS/alpha/p2.png", "my new primary")

	var result := await _repo.submit("Add a primary", "")

	assert_false(result.ok, "failed")
	assert_eq(_git_raw(["-C", _repo.path, "branch", "--show-current"]), "main", "back on main")
	assert_eq(await _repo.changed_packs(), ["alpha"], "the edit is still there, uncommitted")
	assert_eq(
		_git_raw(["-C", _repo.path, "branch", "--list", "mods/*"]), "", "no half-made branch left"
	)
	assert_eq(
		_git_raw(["-C", _repo.path, "log", "--format=%s", "-1"]), "Initial packs", "no stray commit"
	)
