class_name Toolchain extends RefCounted

## Checks that everything contributing needs is in place: git, the GitHub CLI,
## and a signed-in GitHub account. Each missing piece comes with what to do
## about it, so the app can say more than "something went wrong".

const GIT_DOWNLOAD: String = "https://git-scm.com/downloads"
const GH_DOWNLOAD: String = "https://cli.github.com"
## gh's own browser sign-in needs a terminal: it asks for a key press and shows
## a one-time code, which the app can't drive for it.
const SIGN_IN_COMMAND: String = "gh auth login --web --git-protocol https"

var runner: CommandRunner


func _init(command_runner: CommandRunner) -> void:
	runner = command_runner


## Returns a report:
##   git_ok, gh_ok, signed_in: bool
##   git_version, gh_version, user: String
##   problems: Array of { "text": String, "link": String, "command": String }
##   ready: bool - true only when nothing is missing
func check() -> Dictionary:
	var report := {
		"git_ok": false,
		"gh_ok": false,
		"signed_in": false,
		"git_version": "",
		"gh_version": "",
		"user": "",
		"problems": [],
		"ready": false,
	}

	var git := await runner.run("git", ["--version"])
	report.git_ok = git.code == 0
	if report.git_ok:
		report.git_version = git.output.get_slice("\n", 0)
	else:
		(
			report
			. problems
			. append(
				{
					"text": "Git isn't installed, or can't be found.",
					"link": GIT_DOWNLOAD,
					"command": "",
				}
			)
		)

	var gh := await runner.run("gh", ["--version"])
	report.gh_ok = gh.code == 0
	if report.gh_ok:
		report.gh_version = gh.output.get_slice("\n", 0)
	else:
		(
			report
			. problems
			. append(
				{
					"text": "The GitHub CLI (gh) isn't installed, or can't be found.",
					"link": GH_DOWNLOAD,
					"command": "",
				}
			)
		)

	# Signing in only makes sense to check once gh itself is there.
	if report.gh_ok:
		var status := await runner.run("gh", ["auth", "status", "--hostname", "github.com"])
		report.signed_in = status.code == 0
		if report.signed_in:
			var user := await runner.run("gh", ["api", "user", "--jq", ".login"])
			if user.code == 0:
				report.user = user.output
		else:
			(
				report
				. problems
				. append(
					{
						"text":
						"You're not signed in to GitHub. Run this in a terminal, then check again:",
						"link": "",
						"command": SIGN_IN_COMMAND,
					}
				)
			)

	report.ready = report.problems.is_empty()
	return report
