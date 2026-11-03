extends GutTest

# Tests the warning shown before getting the latest mods would throw work away:
# it names everything at risk, in plain words.


func test_names_edited_packs() -> void:
	var text := DiscardDialog.describe({"changed": ["alpha", "beta"]})
	assert_string_contains(text, "edits to alpha, beta that haven't been submitted")


func test_names_other_files_and_unsent_commits() -> void:
	var text := DiscardDialog.describe(
		{"changed": ["alpha"], "other_files": ["renames.json"], "unsent_commits": 2}
	)
	assert_string_contains(text, "edits to alpha")
	assert_string_contains(text, "changes to renames.json")
	assert_string_contains(text, "and 2 saved changes that never reached GitHub")


func test_one_unsent_commit_reads_naturally() -> void:
	var text := DiscardDialog.describe({"unsent_commits": 1})
	assert_string_contains(text, "1 saved change that never reached GitHub")
