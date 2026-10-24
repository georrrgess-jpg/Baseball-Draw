extends MenuScreen
## Full-screen settings page reached from the main menu.


func _ready() -> void:
	setup_screen("SETTINGS", "Display, graphics, audio, gameplay, accessibility and controls")
	var panel := SettingsPanel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(panel)


func go_back() -> void:
	Settings.save_settings()
	super.go_back()
