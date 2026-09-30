class_name ModsRepo extends RefCounted

## The app's own copy of the official mods repository, and everything a
## contributor does with it: keep it current with GitHub, and send edits back as
## a pull request. Nobody using the app needs to know git.

const UPSTREAM: String = "codeWonderland/pyramid-mods"
const FORK_REMOTE: String = "fork"
const BRANCH_PREFIX: String = "mods/"

## Where the copy lives on disk.
var path: String
## Where it is cloned from. Always GitHub in the app; tests point it elsewhere.
var upstream_url: String = "https://github.com/%s.git" % UPSTREAM
var runner: CommandRunner


func _init(command_runner: CommandRunner, repo_path: String = "") -> void:
	runner = command_runner
	path = (
		repo_path
		if not repo_path.is_empty()
		else ProjectSettings.globalize_path("user://pyramid-mods")
	)


func packs_path() -> String:
	return path.path_join("PACKS")


func is_cloned() -> bool:
	return DirAccess.dir_exists_absolute(path.path_join(".git"))


## Downloads the official mods for the first time.
func clone() -> Dictionary:
	if is_cloned():
		return _ok()

	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var result := await runner.run("git", ["clone", "--quiet", upstream_url, path])
	if result.code != 0:
		return _fail("Couldn't download the official mods.", result)
	return _ok()


## Packs with edits that haven't been submitted yet, by folder name.
func changed_packs() -> Array[String]:
	var result := await _git(
		[
			"-c",
			"core.quotePath=false",
			"status",
			"--porcelain",
			"--untracked-files=all",
			"--",
			"PACKS",
		]
	)
	if result.code != 0:
		return [] as Array[String]
	return packs_from_status(result.output)


## Pack folder names from `git status --porcelain` output. Not the NUL-separated
## -z form: output reaches us as a String, and it would be cut off at the first
## NUL, silently losing every entry after it. Instead, paths that git has quoted
## (anything with a space or quote in it) are unquoted here.
static func packs_from_status(output: String) -> Array[String]:
	var packs: Array[String] = []
	for line in output.split("\n", false):
		if line.length() < 4:
			continue
		var file_path := line.substr(3)
		# A rename or copy reads "old -> new"; the new path is the one that counts.
		if line[0] == "R" or line[0] == "C":
			var arrow := file_path.find(" -> ")
			if arrow != -1:
				file_path = file_path.substr(arrow + 4)
		var parts := _unquote(file_path).split("/")
		if parts.size() >= 2 and parts[0] == "PACKS" and not packs.has(parts[1]):
			packs.append(parts[1])

	packs.sort()
	return packs


## Reverses git's C-style quoting of a path: surrounding quotes, and backslash
## escapes including octal byte escapes.
static func _unquote(quoted: String) -> String:
	if not (quoted.length() >= 2 and quoted.begins_with('"') and quoted.ends_with('"')):
		return quoted

	var inner := quoted.substr(1, quoted.length() - 2)
	var simple := {"n": 10, "t": 9, "r": 13, '"': 34, "\\": 92, "a": 7, "b": 8, "f": 12, "v": 11}
	var bytes := PackedByteArray()
	var index := 0
	while index < inner.length():
		var character := inner[index]
		if character != "\\" or index + 1 >= inner.length():
			bytes.append_array(character.to_utf8_buffer())
			index += 1
			continue

		var escaped := inner[index + 1]
		if escaped >= "0" and escaped <= "7" and index + 3 < inner.length():
			bytes.append(_octal(inner.substr(index + 1, 3)))
			index += 4
		elif simple.has(escaped):
			bytes.append(simple[escaped])
			index += 2
		else:
			bytes.append_array(escaped.to_utf8_buffer())
			index += 2

	return bytes.get_string_from_utf8()


static func _octal(digits: String) -> int:
	var value := 0
	for digit in digits:
		value = value * 8 + (digit.unicode_at(0) - "0".unicode_at(0))
	return value


func has_changes() -> bool:
	return not (await changed_packs()).is_empty()


## Brings the copy up to date with GitHub. Unsubmitted edits are never thrown
## away quietly: with any present, this stops and reports them unless the
## player has confirmed with `discard_changes`.
func refresh(discard_changes: bool = false) -> Dictionary:
	if not is_cloned():
		return await clone()

	var changed := await changed_packs()
	if not changed.is_empty() and not discard_changes:
		return {
			"ok": false,
			"needs_confirmation": true,
			"changed": changed,
			"message": "You have edits that haven't been submitted yet.",
		}

	var fetch := await _git(["fetch", "--quiet", "origin", "main"])
	if fetch.code != 0:
		return _fail("Couldn't reach GitHub to check for updates.", fetch)

	for step in [
		["checkout", "--quiet", "--force", "main"],
		["reset", "--quiet", "--hard", "origin/main"],
		["clean", "--quiet", "-fd", "--", "PACKS"],
	]:
		var result := await _git(step)
		if result.code != 0:
			return _fail("Couldn't update the official mods.", result)

	return _ok()


## Sends the edited packs to GitHub as a pull request. On success the copy goes
## back to the official packs, as the edits now live in the pull request; if
## anything fails partway, it is rewound to exactly where it started, edits and
## all.
func submit(title: String, body: String) -> Dictionary:
	title = title.strip_edges()
	var prepared := await _prepare_submission(title)
	if not prepared.ok:
		return prepared

	var published := await _publish(branch_name(title), title, body, prepared)
	if published.ok:
		await _git(["checkout", "--quiet", "main"])
	return published


## Your open pull requests to the official mods, newest first, each as
## { number, title, url, checks, review }.
func my_submissions() -> Dictionary:
	var result := await (
		runner
		. run(
			"gh",
			[
				"pr",
				"list",
				"--repo",
				UPSTREAM,
				"--author",
				"@me",
				"--state",
				"open",
				"--json",
				"number,title,url,reviewDecision,statusCheckRollup",
			]
		)
	)
	if result.code != 0:
		return _fail("Couldn't load your submissions.", result)

	var json := JSON.new()
	if json.parse(result.output) != OK or not (json.data is Array):
		return {"ok": false, "message": "GitHub sent back something unexpected."}

	var submissions: Array = []
	for pr in json.data:
		if not (pr is Dictionary):
			continue
		(
			submissions
			. append(
				{
					"number": int(pr.get("number", 0)),
					"title": str(pr.get("title", "")),
					"url": str(pr.get("url", "")),
					"checks": summarize_checks(pr.get("statusCheckRollup", [])),
					"review": summarize_review(pr.get("reviewDecision", "")),
				}
			)
		)
	return {"ok": true, "submissions": submissions}


## A branch name from a submission title: lowercase words joined by dashes,
## plus a timestamp so two submissions with the same title never collide.
static func branch_name(title: String, now: int = -1) -> String:
	var slug := ""
	for character in title.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			slug += character
		elif not slug.ends_with("-") and not slug.is_empty():
			slug += "-"
	slug = slug.trim_suffix("-").left(40).trim_suffix("-")
	if slug.is_empty():
		slug = "update"
	var stamp := now if now >= 0 else int(Time.get_unix_time_from_system())
	return "%s%s-%d" % [BRANCH_PREFIX, slug, stamp]


## "passing", "failing", "running", or "none", from gh's statusCheckRollup.
static func summarize_checks(rollup) -> String:
	if not (rollup is Array) or rollup.is_empty():
		return "none"

	var running := false
	for check in rollup:
		if not (check is Dictionary):
			continue
		var outcome := str(check.get("conclusion", check.get("state", ""))).to_upper()
		if outcome in ["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED"]:
			return "failing"
		if outcome in ["", "PENDING", "QUEUED", "IN_PROGRESS", "EXPECTED"]:
			running = true
	return "running" if running else "passing"


## "approved", "changes requested", or "awaiting review".
static func summarize_review(decision) -> String:
	match str(decision):
		"APPROVED":
			return "approved"
		"CHANGES_REQUESTED":
			return "changes requested"
	return "awaiting review"


# --- Submission steps ---


## Everything that can be checked before anything is touched: a title, some
## edits, a GitHub account, a commit identity, and somewhere to push.
func _prepare_submission(title: String) -> Dictionary:
	if title.is_empty():
		return {"ok": false, "message": "Give your submission a title."}

	var changed := await changed_packs()
	if changed.is_empty():
		return {"ok": false, "message": "There are no edited packs to submit."}

	var user := await _github_user()
	if user.is_empty():
		return {"ok": false, "message": "Couldn't find your GitHub account. Are you signed in?"}

	var identity := await _ensure_identity(user)
	if not identity.ok:
		return identity

	var remote := await _push_remote(user.login)
	if not remote.ok:
		return remote

	return {"ok": true, "changed": changed, "remote": remote}


## Branch, commit, push and open the pull request, rewinding if any step fails.
func _publish(branch: String, title: String, body: String, prepared: Dictionary) -> Dictionary:
	var remote: Dictionary = prepared.remote
	var start := await _git(["checkout", "--quiet", "-b", branch])
	if start.code != 0:
		return _fail("Couldn't prepare your submission.", start)

	var commit := await _commit(title, body)
	if not commit.ok:
		await _rewind(branch, false)
		return commit

	var push := await _git(["push", "--quiet", "-u", remote.name, branch])
	if push.code != 0:
		await _rewind(branch, true)
		return _fail("Couldn't upload your submission to GitHub.", push)

	var pr := await (
		runner
		. run(
			"gh",
			[
				"pr",
				"create",
				"--repo",
				UPSTREAM,
				"--base",
				"main",
				"--head",
				"%s:%s" % [remote.owner, branch],
				"--title",
				title,
				"--body",
				_pr_body(body, prepared.changed),
			]
		)
	)
	if pr.code != 0:
		await _rewind(branch, true)
		return _fail("Couldn't open the pull request.", pr)

	# gh prints the new pull request's address as its last line.
	var lines: PackedStringArray = str(pr.output).strip_edges().split("\n")
	return {"ok": true, "url": lines[lines.size() - 1]}


func _github_user() -> Dictionary:
	var result := await runner.run("gh", ["api", "user", "--jq", "[.login, .id] | @tsv"])
	if result.code != 0:
		return {}
	var fields: PackedStringArray = str(result.output).strip_edges().split("\t")
	if fields.size() < 2 or fields[0].is_empty():
		return {}
	return {"login": fields[0], "id": fields[1]}


## Commits need a name and email. For anyone who has never set them up, borrow
## their GitHub login and GitHub's private "noreply" address for this copy only.
func _ensure_identity(user: Dictionary) -> Dictionary:
	var email := await _git(["config", "user.email"])
	if email.code == 0 and not email.output.is_empty():
		return _ok()

	var noreply := "%s+%s@users.noreply.github.com" % [user.id, user.login]
	for setting in [["user.name", user.login], ["user.email", noreply]]:
		var result := await _git(["config", setting[0], setting[1]])
		if result.code != 0:
			return _fail("Couldn't set up your name for the submission.", result)
	return _ok()


## Lets git push with the player's GitHub sign-in from gh. Set in this copy only
## (gh's own "auth setup-git" would change the player's global git config).
## The empty helper first clears any others inherited from global config, so a
## stale saved password can't be tried instead.
func _use_github_sign_in() -> Dictionary:
	var key := "credential.https://github.com.helper"
	await _git(["config", "--local", "--unset-all", key])
	for helper in ["", "!gh auth git-credential"]:
		var result := await _git(["config", "--local", "--add", key, helper])
		if result.code != 0:
			return _fail("Couldn't connect your GitHub sign-in to git.", result)
	return _ok()


## Where and how to push: the official repo for anyone allowed to, otherwise a fork on
## the player's own account, created the first time it's needed.
func _push_remote(login: String) -> Dictionary:
	var credentials := await _use_github_sign_in()
	if not credentials.ok:
		return credentials

	var access := await runner.run("gh", ["api", "repos/" + UPSTREAM, "--jq", ".permissions.push"])
	if access.code == 0 and access.output == "true":
		return {"ok": true, "name": "origin", "owner": UPSTREAM.get_slice("/", 0)}

	var fork := await runner.run(
		"gh", ["repo", "fork", UPSTREAM, "--clone=false", "--remote=false"]
	)
	if fork.code != 0:
		return _fail("Couldn't make your copy of the mods on GitHub.", fork)

	var fork_url := "https://github.com/%s/pyramid-mods.git" % login
	var existing := await _git(["remote", "get-url", FORK_REMOTE])
	var set_remote: Dictionary
	if existing.code == 0:
		set_remote = await _git(["remote", "set-url", FORK_REMOTE, fork_url])
	else:
		set_remote = await _git(["remote", "add", FORK_REMOTE, fork_url])
	if set_remote.code != 0:
		return _fail("Couldn't connect to your copy of the mods.", set_remote)

	return {"ok": true, "name": FORK_REMOTE, "owner": login}


func _commit(title: String, body: String) -> Dictionary:
	var add := await _git(["add", "--all", "--", "PACKS"])
	if add.code != 0:
		return _fail("Couldn't gather your edits.", add)

	var args := PackedStringArray(["commit", "--quiet", "-m", title])
	if not body.strip_edges().is_empty():
		args.append_array(["-m", body.strip_edges()])
	var commit := await _git(args)
	if commit.code != 0:
		return _fail("Couldn't save your edits for submission.", commit)
	return _ok()


## Puts the copy back exactly as it was before a submission started: back on
## main, with the edits still in place and not committed.
func _rewind(branch: String, committed: bool) -> void:
	if committed:
		await _git(["reset", "--quiet", "--mixed", "HEAD~1"])
	await _git(["checkout", "--quiet", "main"])
	await _git(["branch", "--quiet", "-D", branch])


static func _pr_body(body: String, changed: Array[String]) -> String:
	var lines := PackedStringArray()
	if not body.strip_edges().is_empty():
		lines.append(body.strip_edges())
		lines.append("")
	lines.append("Packs changed:")
	for pack in changed:
		lines.append("- %s" % pack)
	lines.append("")
	lines.append("Submitted with the Official Pyramid Mod Manager.")
	return "\n".join(lines)


func _git(args: PackedStringArray) -> Dictionary:
	var full := PackedStringArray(["-C", path])
	full.append_array(args)
	return await runner.run("git", full)


static func _ok() -> Dictionary:
	return {"ok": true}


static func _fail(message: String, result: Dictionary) -> Dictionary:
	var detail := str(result.get("output", "")).strip_edges()
	if int(result.get("code", 0)) == CommandRunner.NOT_FOUND:
		detail = "The program couldn't be started - is it installed?"
	return {"ok": false, "message": message, "detail": detail}
