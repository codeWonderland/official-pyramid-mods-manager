extends Node

## Shared state for contributing to the official mods: the toolchain check, the
## copy of pyramid-mods being edited, and whether an operation is running. The
## main menu and the editor both read from here, so they always agree on where
## the mods are.

signal state_changed
signal busy_changed(busy: bool, message: String)

var runner: CommandRunner = CommandRunner.new()
var toolchain: Toolchain
var repo: ModsRepo
var report: Dictionary = {}
var busy: bool = false


func _ready() -> void:
	_migrate_old_mods_location()
	_rebuild()


## Swaps how commands run - tests hand in a fake - and optionally where the copy
## lives.
func use_runner(command_runner: CommandRunner, repo_path: String = "") -> void:
	runner = command_runner
	_rebuild(repo_path)


## Points at a copy of pyramid-mods the player already has, or back at the app's
## own with "".
func use_repo_location(location: String) -> void:
	UserSettingsManager.set_repo_location(location)
	_rebuild()
	self.state_changed.emit()


## Whether a folder is a copy of the mods repo: a git repository with PACKS in it.
static func is_mods_repo(folder: String) -> bool:
	return (
		DirAccess.dir_exists_absolute(folder.path_join(".git"))
		and DirAccess.dir_exists_absolute(folder.path_join("PACKS"))
	)


func check() -> Dictionary:
	_set_busy(true, "Checking your setup...")
	report = await toolchain.check()
	_set_busy(false)
	self.state_changed.emit()
	return report


func can_download() -> bool:
	return report.get("git_ok", false) and not repo.is_cloned()


func can_edit() -> bool:
	return repo.is_cloned()


func can_refresh() -> bool:
	return report.get("git_ok", false) and repo.is_cloned()


func can_submit() -> bool:
	return report.get("ready", false) and repo.is_cloned()


func download() -> Dictionary:
	return await _run("Downloading the official mods...", repo.clone)


func refresh(discard_changes: bool = false) -> Dictionary:
	return await _run("Getting the latest mods from GitHub...", repo.refresh.bind(discard_changes))


func submit(title: String, body: String) -> Dictionary:
	return await _run("Submitting your changes...", repo.submit.bind(title, body))


func submissions() -> Dictionary:
	return await _run("Loading your submissions...", repo.my_submissions)


func _run(message: String, operation: Callable) -> Dictionary:
	_set_busy(true, message)
	var result: Dictionary = await operation.call()
	_set_busy(false)
	self.state_changed.emit()
	return result


func _set_busy(value: bool, message: String = "") -> void:
	busy = value
	self.busy_changed.emit(busy, message)


func _rebuild(repo_path: String = "") -> void:
	var path := repo_path if not repo_path.is_empty() else UserSettingsManager.repo_location
	toolchain = Toolchain.new(runner)
	repo = ModsRepo.new(runner, path)


## Earlier versions stored the PACKS folder of a copy the player cloned by hand.
## When that is still a real copy of the repo, keep using it.
func _migrate_old_mods_location() -> void:
	var old := UserSettingsManager.mods_location
	if old.is_empty() or not UserSettingsManager.repo_location.is_empty():
		return

	var candidate := old.trim_suffix("/").get_base_dir()
	if old.trim_suffix("/").get_file() == "PACKS" and is_mods_repo(candidate):
		UserSettingsManager.set_repo_location(candidate)
