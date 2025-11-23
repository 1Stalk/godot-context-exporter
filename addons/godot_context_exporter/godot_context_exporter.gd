@tool
extends EditorPlugin

## Exports selected GDScript files, Scene trees, and Project Settings into a single text file or clipboard.
## useful for sharing context with LLMs or documentation.

#region Constants & Configuration
#-----------------------------------------------------------------------------

# Colors for UI feedback
const COLOR_SAVE_BTN = Color("#2e6b2e")
const COLOR_SAVE_TEXT = Color("#46a946")
const COLOR_COPY_BTN = Color("#2e6b69")
const COLOR_COPY_TEXT = Color("#4ab4b1")
const COLOR_ERROR = Color("#b83b3b")
const COLOR_WARNING = Color("#d4a53a")
const COLOR_ACCENT = Color("#7ca6e2")

# Default styles
const THEME_BG_COLOR = Color("#232323")
const THEME_LIST_BG = Color("#2c3036")

#endregion


#region UI Variables
#-----------------------------------------------------------------------------
var window: Window
var status_label: Label

# Scripts Tab
var script_list: ItemList
var select_all_scripts_checkbox: CheckBox
var group_by_folder_checkbox: CheckBox
var wrap_in_markdown_checkbox: CheckBox

# Scenes Tab
var scene_list: ItemList
var select_all_scenes_checkbox: CheckBox
var include_inspector_checkbox: CheckBox
var collapse_scenes_checkbox: CheckBox
var wrap_scenes_in_markdown_checkbox: CheckBox

# Format Manager (Popup)
var format_manager_dialog: Window
var formats_list_vbox: VBoxContainer

#endregion


#region State Variables
#-----------------------------------------------------------------------------

# Script State
var group_by_folder: bool = false
var wrap_in_markdown: bool = false
var all_script_paths: Array[String] = []
var folder_data: Dictionary = {}
var is_script_model_built: bool = false

# Scene State
var all_scene_paths: Array[String] = []
var checked_scene_paths: Array[String] = []
var include_inspector_changes: bool = false
var wrap_scene_in_markdown: bool = false
var collapse_instanced_scenes: bool = false
var collapsible_formats: Array[String] = [".blend", ".gltf", ".glb", ".obj", ".fbx"]

# Project Settings State
var include_project_godot: bool = false
var wrap_project_godot_in_markdown: bool = false

# Autoloads State
var include_autoloads: bool = true
var wrap_autoloads_in_markdown: bool = true

#endregion


#region Plugin Lifecycle
#-----------------------------------------------------------------------------

func _enter_tree() -> void:
	add_tool_menu_item("Text Snapshot...", Callable(self, "open_window"))
	_setup_ui()

func _exit_tree() -> void:
	remove_tool_menu_item("Text Snapshot...")
	if is_instance_valid(window):
		window.queue_free()
	if is_instance_valid(format_manager_dialog):
		format_manager_dialog.queue_free()

#endregion


#region UI Construction
#-----------------------------------------------------------------------------

func _setup_ui() -> void:
	window = Window.new()
	window.title = "Godot Text Snapshot"
	window.min_size = Vector2i(600, 750)
	window.size = Vector2i(700, 850)
	window.visible = false
	window.wrap_controls = true
	window.close_requested.connect(window.hide)

	var root_panel = PanelContainer.new()
	var main_style = StyleBoxFlat.new()
	main_style.bg_color = THEME_BG_COLOR
	root_panel.add_theme_stylebox_override("panel", main_style)
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(root_panel)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	root_panel.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_vbox)

	# Tabs
	var tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tab_container)

	tab_container.add_child(_create_scripts_tab())
	tab_container.set_tab_title(0, "Scripts")
	
	tab_container.add_child(_create_scenes_tab())
	tab_container.set_tab_title(1, "Scenes")
	
	_create_footer_controls(main_vbox)
	
	# Add window to the editor
	get_editor_interface().get_base_control().add_child(window)

func _create_scripts_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.name = "ScriptsTab"
	vbox.add_theme_constant_override("separation", 10)

	var scripts_label = RichTextLabel.new()
	scripts_label.bbcode_enabled = true
	scripts_label.text = "[b][color=#d5eaf2]Select Scripts to Export:[/color][/b]"
	scripts_label.fit_content = true
	vbox.add_child(scripts_label)
	
	var options_hbox = HBoxContainer.new()
	vbox.add_child(options_hbox)

	select_all_scripts_checkbox = CheckBox.new()
	select_all_scripts_checkbox.text = "Select All"
	select_all_scripts_checkbox.add_theme_color_override("font_color", COLOR_ACCENT)
	select_all_scripts_checkbox.pressed.connect(_on_select_all_scripts_toggled)
	options_hbox.add_child(select_all_scripts_checkbox)
	
	group_by_folder_checkbox = CheckBox.new()
	group_by_folder_checkbox.text = "Group by Folder"
	group_by_folder_checkbox.toggled.connect(_on_group_by_folder_toggled)
	options_hbox.add_child(group_by_folder_checkbox)
	
	var list_panel = _create_list_panel()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(list_panel)
	
	script_list = ItemList.new()
	script_list.select_mode = ItemList.SELECT_SINGLE
	script_list.allow_reselect = true
	script_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	script_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	script_list.item_clicked.connect(_on_script_item_clicked)
	list_panel.add_child(script_list)

	wrap_in_markdown_checkbox = CheckBox.new()
	wrap_in_markdown_checkbox.text = "Wrap code in Markdown (```gdscript```)"
	wrap_in_markdown_checkbox.toggled.connect(func(p): wrap_in_markdown = p)
	vbox.add_child(wrap_in_markdown_checkbox)
	
	return vbox
	
func _create_scenes_tab() -> Control:
	var vbox = VBoxContainer.new()
	vbox.name = "ScenesTab"
	vbox.add_theme_constant_override("separation", 10)

	var scenes_label = RichTextLabel.new()
	scenes_label.bbcode_enabled = true
	scenes_label.text = "[b][color=#d5eaf2]Select Scenes to Export:[/color][/b]"
	scenes_label.fit_content = true
	vbox.add_child(scenes_label)

	select_all_scenes_checkbox = CheckBox.new()
	select_all_scenes_checkbox.text = "Select All"
	select_all_scenes_checkbox.add_theme_color_override("font_color", COLOR_ACCENT)
	select_all_scenes_checkbox.pressed.connect(_on_select_all_scenes_toggled)
	vbox.add_child(select_all_scenes_checkbox)
	
	var list_panel = _create_list_panel()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(list_panel)

	scene_list = ItemList.new()
	scene_list.select_mode = ItemList.SELECT_MULTI
	scene_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_list.item_clicked.connect(_on_scene_item_clicked)
	list_panel.add_child(scene_list)

	include_inspector_checkbox = CheckBox.new()
	include_inspector_checkbox.text = "Include non-default Inspector properties"
	include_inspector_checkbox.toggled.connect(func(p): include_inspector_changes = p)
	vbox.add_child(include_inspector_checkbox)
	
	var collapse_hbox = HBoxContainer.new()
	vbox.add_child(collapse_hbox)
	
	collapse_scenes_checkbox = CheckBox.new()
	collapse_scenes_checkbox.text = "Collapse Instanced Scenes by Format"
	collapse_scenes_checkbox.toggled.connect(func(p): collapse_instanced_scenes = p)
	collapse_hbox.add_child(collapse_scenes_checkbox)
	
	var manage_formats_button = Button.new()
	manage_formats_button.text = "Manage Formats..."
	manage_formats_button.pressed.connect(_on_manage_formats_pressed)
	collapse_hbox.add_child(manage_formats_button)

	wrap_scenes_in_markdown_checkbox = CheckBox.new()
	wrap_scenes_in_markdown_checkbox.text = "Wrap scene trees in Markdown (```text```)"
	wrap_scenes_in_markdown_checkbox.toggled.connect(func(p): wrap_scene_in_markdown = p)
	vbox.add_child(wrap_scenes_in_markdown_checkbox)

	return vbox

func _create_format_manager_dialog() -> void:
	format_manager_dialog = Window.new()
	format_manager_dialog.title = "Manage Collapsible Formats"
	format_manager_dialog.min_size = Vector2i(350, 400)
	format_manager_dialog.size = Vector2i(350, 500)
	format_manager_dialog.close_requested.connect(format_manager_dialog.hide)
	window.add_child(format_manager_dialog)
	
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	format_manager_dialog.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	margin.add_child(main_vbox)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	formats_list_vbox = VBoxContainer.new()
	scroll.add_child(formats_list_vbox)
	
	var add_button = Button.new()
	add_button.text = "Add New Format"
	add_button.pressed.connect(_add_format_row.bind(""))
	main_vbox.add_child(add_button)
	
	main_vbox.add_child(HSeparator.new())
	
	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(buttons_hbox)
	
	var ok_button = Button.new()
	ok_button.text = "OK"
	ok_button.pressed.connect(_on_format_dialog_ok)
	buttons_hbox.add_child(ok_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(format_manager_dialog.hide)
	buttons_hbox.add_child(cancel_button)

func _add_format_row(format_text: String) -> void:
	var hbox = HBoxContainer.new()
	
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = ".ext"
	line_edit.text = format_text
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(line_edit)
	
	var remove_button = Button.new()
	remove_button.text = "Remove"
	remove_button.pressed.connect(hbox.queue_free)
	hbox.add_child(remove_button)
	
	formats_list_vbox.add_child(hbox)

func _create_list_panel() -> PanelContainer:
	var list_style = StyleBoxFlat.new()
	list_style.bg_color = THEME_LIST_BG
	list_style.set_corner_radius_all(3)
	var list_panel = PanelContainer.new()
	list_panel.add_theme_stylebox_override("panel", list_style)
	return list_panel

func _create_footer_controls(parent: VBoxContainer) -> void:
	var project_options_vbox = VBoxContainer.new()
	parent.add_child(project_options_vbox)
	
	# --- Autoloads Section ---
	var autoloads_checkbox = CheckBox.new()
	autoloads_checkbox.text = "Include Globals (Autoloads/Singletons)"
	autoloads_checkbox.button_pressed = true
	project_options_vbox.add_child(autoloads_checkbox)
	
	var wrap_autoloads_checkbox = CheckBox.new()
	var al_margin = MarginContainer.new()
	al_margin.add_theme_constant_override("margin_left", 20)
	al_margin.add_child(wrap_autoloads_checkbox)
	
	wrap_autoloads_checkbox.text = "Wrap in Markdown"
	wrap_autoloads_checkbox.button_pressed = true
	wrap_autoloads_checkbox.toggled.connect(func(p): wrap_autoloads_in_markdown = p)
	project_options_vbox.add_child(al_margin)
	
	autoloads_checkbox.toggled.connect(func(p): 
		include_autoloads = p
		wrap_autoloads_checkbox.disabled = not p
		if not p: wrap_autoloads_checkbox.button_pressed = false
		else: wrap_autoloads_checkbox.button_pressed = wrap_autoloads_in_markdown
	)
	
	# --- Project.godot Section ---
	var project_godot_checkbox = CheckBox.new()
	project_godot_checkbox.text = "Include `project.godot` file content"
	project_options_vbox.add_child(project_godot_checkbox)

	var wrap_project_godot_checkbox = CheckBox.new()
	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 20)
	margin_container.add_child(wrap_project_godot_checkbox)
	
	wrap_project_godot_checkbox.text = "Wrap in Markdown (```ini```)"
	wrap_project_godot_checkbox.disabled = true
	wrap_project_godot_checkbox.toggled.connect(func(p): wrap_project_godot_in_markdown = p)
	project_options_vbox.add_child(margin_container)

	project_godot_checkbox.toggled.connect(func(p):
		include_project_godot = p
		wrap_project_godot_checkbox.disabled = not p
		if not p:
			wrap_project_godot_checkbox.button_pressed = false
	)

	# --- Action Buttons ---
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)
	
	var copy_button = Button.new()
	copy_button.text = "Copy to Clipboard"
	copy_button.custom_minimum_size = Vector2(150, 35)
	var copy_style = StyleBoxFlat.new(); copy_style.bg_color = COLOR_COPY_BTN
	copy_button.add_theme_stylebox_override("normal", copy_style)
	copy_button.pressed.connect(_export_selected.bind(true))
	hbox.add_child(copy_button)
	
	var save_button = Button.new()
	save_button.text = "Save to File"
	save_button.custom_minimum_size = Vector2(150, 35)
	var save_style = StyleBoxFlat.new(); save_style.bg_color = COLOR_SAVE_BTN
	save_button.add_theme_stylebox_override("normal", save_style)
	save_button.pressed.connect(_export_selected.bind(false))
	hbox.add_child(save_button)
	
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(status_label)

#endregion


#region Data Management & Rendering
#-----------------------------------------------------------------------------

func open_window() -> void:
	all_script_paths = _find_files_recursive("res://", ".gd")
	all_script_paths.sort()
	all_scene_paths = _find_files_recursive("res://", ".tscn")
	all_scene_paths.sort()
	
	# Check flag before rebuilding to preserve selection state if window was closed but not freed
	if not is_script_model_built:
		_build_script_data_model()
		is_script_model_built = true
	
	_render_script_list()
	_render_scene_list()
	
	status_label.remove_theme_color_override("font_color")
	status_label.text = "Select scripts and/or scenes to export."
	window.popup_centered()

func _build_script_data_model() -> void:
	folder_data.clear()
	var folders = {}
	for path in all_script_paths:
		var dir = path.get_base_dir()
		if not folders.has(dir): folders[dir] = []
		folders[dir].append(path)

	for dir in folders.keys():
		folder_data[dir] = { "is_expanded": true, "is_checked": false, "scripts": {} }
		for script_path in folders[dir]:
			folder_data[dir]["scripts"][script_path] = {"is_checked": false}

func _render_script_list() -> void:
	script_list.clear()
	if group_by_folder:
		_render_grouped_script_list()
	else:
		_render_flat_script_list()

func _render_flat_script_list() -> void:
	for path in all_script_paths:
		var is_checked = false
		var dir = path.get_base_dir()
		if folder_data.has(dir) and folder_data[dir]["scripts"].has(path):
			is_checked = folder_data[dir]["scripts"][path]["is_checked"]
		var checkbox = "☑ " if is_checked else "☐ "
		script_list.add_item(checkbox + path.replace("res://", ""))
		var idx = script_list.get_item_count() - 1
		script_list.set_item_metadata(idx, {"type": "script", "path": path})

func _render_grouped_script_list() -> void:
	var sorted_folders = folder_data.keys(); sorted_folders.sort()
	for dir in sorted_folders:
		var folder_info = folder_data[dir]
		var display_dir = dir.replace("res://", "")
		if display_dir == "": display_dir = "res://"
		var checkbox = "☑ " if folder_info.is_checked else "☐ "
		var expand_symbol = "▾ " if folder_info.is_expanded else "▸ "
		script_list.add_item(expand_symbol + checkbox + display_dir)
		var folder_idx = script_list.get_item_count() - 1
		script_list.set_item_metadata(folder_idx, {"type": "folder", "dir": dir})

		if folder_info.is_expanded:
			var sorted_scripts = folder_info.scripts.keys(); sorted_scripts.sort()
			for script_path in sorted_scripts:
				var script_info = folder_info.scripts[script_path]
				var script_checkbox = "☑ " if script_info.is_checked else "☐ "
				script_list.add_item("    " + script_checkbox + script_path.get_file())
				var script_idx = script_list.get_item_count() - 1
				script_list.set_item_metadata(script_idx, {"type": "script", "path": script_path})
				
func _render_scene_list() -> void:
	scene_list.clear()
	for path in all_scene_paths:
		var is_checked = checked_scene_paths.has(path)
		var checkbox = "☑ " if is_checked else "☐ "
		scene_list.add_item(checkbox + path.replace("res://", ""))
		var idx = scene_list.get_item_count() - 1
		scene_list.set_item_metadata(idx, path)

#endregion


#region Signals & Event Handlers
#-----------------------------------------------------------------------------

func _on_manage_formats_pressed() -> void:
	if not is_instance_valid(format_manager_dialog):
		_create_format_manager_dialog()
	
	for child in formats_list_vbox.get_children():
		child.queue_free()
		
	for format_ext in collapsible_formats:
		_add_format_row(format_ext)
		
	format_manager_dialog.popup_centered()

func _on_format_dialog_ok() -> void:
	collapsible_formats.clear()
	for child in formats_list_vbox.get_children():
		var line_edit: LineEdit = child.get_child(0)
		var text = line_edit.text.strip_edges()
		if not text.is_empty():
			if not text.begins_with("."):
				text = "." + text
			collapsible_formats.append(text)
	format_manager_dialog.hide()

func _on_script_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT: return
	var meta = script_list.get_item_metadata(index)
	if meta.is_empty(): return

	if meta["type"] == "folder":
		var dir = meta["dir"]
		# Click left side (arrow) to toggle expand, right side (checkbox) to select all
		if at_position.x < 20: 
			folder_data[dir].is_expanded = not folder_data[dir].is_expanded
		else:
			folder_data[dir].is_checked = not folder_data[dir].is_checked
			for script_path in folder_data[dir].scripts:
				folder_data[dir].scripts[script_path].is_checked = folder_data[dir].is_checked
	
	elif meta["type"] == "script":
		var path = meta["path"]
		var dir = path.get_base_dir()
		folder_data[dir].scripts[path].is_checked = not folder_data[dir].scripts[path].is_checked
		
		# Update folder checkbox state if all children match
		if group_by_folder:
			var all_checked = true
			for s_path in folder_data[dir].scripts:
				if not folder_data[dir].scripts[s_path].is_checked:
					all_checked = false; break
			folder_data[dir].is_checked = all_checked
			
	_render_script_list()

func _on_group_by_folder_toggled(pressed: bool) -> void:
	group_by_folder = pressed
	_render_script_list()

func _on_select_all_scripts_toggled() -> void:
	var is_checked = select_all_scripts_checkbox.button_pressed
	for dir in folder_data:
		folder_data[dir].is_checked = is_checked
		for script_path in folder_data[dir].scripts:
			folder_data[dir].scripts[script_path].is_checked = is_checked
	_render_script_list()

func _on_scene_item_clicked(index: int, _at_pos: Vector2, _mouse_btn: int) -> void:
	var path = scene_list.get_item_metadata(index)
	if checked_scene_paths.has(path): 
		checked_scene_paths.erase(path)
	else: 
		checked_scene_paths.append(path)
	_render_scene_list()

func _on_select_all_scenes_toggled() -> void:
	var is_checked = select_all_scenes_checkbox.button_pressed
	checked_scene_paths.clear()
	if is_checked: 
		checked_scene_paths = all_scene_paths.duplicate()
	_render_scene_list()

#endregion


#region Export Logic
#-----------------------------------------------------------------------------

func _export_selected(to_clipboard: bool) -> void:
	var selected_scripts = _get_selected_script_paths()
	var selected_scenes = checked_scene_paths.duplicate()
	selected_scenes.sort()

	# Validate selection
	if not include_project_godot and not include_autoloads and selected_scripts.is_empty() and selected_scenes.is_empty():
		_set_status_message("Nothing selected to export.", COLOR_WARNING)
		return
		
	var content_text = ""
	
	# 1. Project.godot
	if include_project_godot:
		content_text += _build_project_godot_content()

	# 2. Autoloads / Globals
	if include_autoloads:
		var autoloads = _get_project_autoloads()
		if not autoloads["scripts"].is_empty() or not autoloads["scenes"].is_empty():
			if not content_text.is_empty(): content_text += "\n\n"
			content_text += "--- AUTOLOADS / GLOBALS ---\n\n"
			
			if not autoloads["scripts"].is_empty():
				content_text += _build_scripts_content(autoloads["scripts"], wrap_autoloads_in_markdown)
			
			if not autoloads["scenes"].is_empty():
				if not autoloads["scripts"].is_empty(): content_text += "\n\n"
				content_text += _build_scenes_content(autoloads["scenes"], wrap_autoloads_in_markdown)

	# 3. Selected Scripts
	if not selected_scripts.is_empty():
		if not content_text.is_empty(): content_text += "\n\n"
		content_text += "--- SCRIPTS ---\n\n"
		content_text += _build_scripts_content(selected_scripts) # Use default UI flag
	
	# 4. Selected Scenes
	if not selected_scenes.is_empty():
		if not content_text.is_empty(): content_text += "\n\n"
		content_text += "--- SCENES ---\n\n"
		content_text += _build_scenes_content(selected_scenes) # Use default UI flag
	
	# Finalize
	var total_lines = content_text.split("\n").size()
	var stats_line = "\nTotal: %d lines, %d characters" % [total_lines, content_text.length()]
	
	var items_str = "%d script(s), %d scene(s)" % [selected_scripts.size(), selected_scenes.size()]
	if include_project_godot: items_str += ", project.godot"
	if include_autoloads: items_str += " + Globals"

	if to_clipboard:
		DisplayServer.clipboard_set(content_text)
		_set_status_message("Success! Copied " + items_str + "." + stats_line, COLOR_COPY_TEXT)
	else:
		var output_path = "res://text_snapshot.txt"
		var file = FileAccess.open(output_path, FileAccess.WRITE)
		if file:
			file.store_string(content_text)
			_set_status_message("Success! Exported " + items_str + " to " + output_path + "." + stats_line, COLOR_SAVE_TEXT)
		else:
			_set_status_message("Error writing to file!", COLOR_ERROR)

func _set_status_message(text: String, color: Color) -> void:
	status_label.add_theme_color_override("font_color", color)
	status_label.text = text

func _get_project_autoloads() -> Dictionary:
	var result = {"scripts": [], "scenes": []}
	
	# Autoloads are stored as properties named "autoload/Name"
	for prop in ProjectSettings.get_property_list():
		var name = prop.name
		if name.begins_with("autoload/"):
			var path = ProjectSettings.get_setting(name)
			
			# Godot may prepend "*" to singletons
			if path.begins_with("*"):
				path = path.substr(1)
				
			if path.ends_with(".gd"):
				result["scripts"].append(path)
			elif path.ends_with(".tscn"):
				result["scenes"].append(path)
				
	return result

func _get_selected_script_paths() -> Array[String]:
	var selected: Array[String] = []
	for dir in folder_data:
		for script_path in folder_data[dir].scripts:
			if folder_data[dir].scripts[script_path].is_checked:
				selected.append(script_path)
	selected.sort()
	return selected

#endregion


#region Content Formatters
#-----------------------------------------------------------------------------

func _build_project_godot_content() -> String:
	var content = ""
	
	# --- [application] ---
	content += "[application]\n"
	
	var app_name = ProjectSettings.get_setting("application/config/name", "")
	if not app_name.is_empty():
		content += 'config/name="%s"\n' % app_name
	
	# Main Scene (convert UID -> res://)
	var main_scene = ProjectSettings.get_setting("application/run/main_scene", "")
	if not main_scene.is_empty():
		if main_scene.begins_with("uid://"):
			var uid_id = ResourceUID.text_to_id(main_scene)
			if ResourceUID.has_id(uid_id):
				main_scene = ResourceUID.get_id_path(uid_id)
		content += 'run/main_scene="%s"\n' % main_scene
	content += "\n"

	# --- [autoload] ---
	var autoloads = _get_project_settings_section("autoload")
	if not autoloads.is_empty():
		content += "[autoload]\n"
		for key in autoloads:
			content += '%s="%s"\n' % [key, autoloads[key]]
		content += "\n"

	# --- [global_group] ---
	var groups = _get_project_settings_section("global_group")
	if not groups.is_empty():
		content += "[global_group]\n"
		for key in groups:
			content += '%s="%s"\n' % [key, groups[key]]
		content += "\n"
		
	# --- [layer_names] ---
	var layers = _get_project_settings_section("layer_names")
	var active_layers = {}
	
	# Filter empty layers
	for key in layers:
		if not layers[key].is_empty():
			active_layers[key] = layers[key]
	
	if not active_layers.is_empty():
		content += "[layer_names]\n"
		var sorted_keys = active_layers.keys()
		sorted_keys.sort() 
		for key in sorted_keys:
			content += '%s="%s"\n' % [key, active_layers[key]]
		content += "\n"

	# --- [input] ---
	var input_section = _generate_clean_input_section()
	if input_section.strip_edges() != "[input]":
		content += input_section + "\n"

	var header = "--- PROJECT.GODOT ---\n\n"
	if wrap_project_godot_in_markdown:
		return header + "```ini\n" + content.strip_edges() + "\n```"
	else:
		return header + content.strip_edges()

func _get_project_settings_section(prefix: String) -> Dictionary:
	var section_data = {}
	for prop in ProjectSettings.get_property_list():
		var prop_name = prop.name
		if prop_name.begins_with(prefix + "/"):
			var key = prop_name.trim_prefix(prefix + "/")
			var value = ProjectSettings.get_setting(prop_name)
			section_data[key] = str(value)
	return section_data

func _build_scripts_content(paths: Array, use_markdown_override = null) -> String:
	var content = ""
	
	var do_wrap = wrap_in_markdown
	if use_markdown_override != null:
		do_wrap = use_markdown_override

	for file_path in paths:
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var file_content = file.get_as_text()
			content += "--- SCRIPT: " + file_path + " ---\n\n"
			if do_wrap:
				content += "```gdscript\n" + file_content + "\n```\n\n"
			else:
				content += file_content + "\n\n"
	return content.rstrip("\n")

func _build_scenes_content(paths: Array, use_markdown_override = null) -> String:
	var do_wrap = wrap_scene_in_markdown
	if use_markdown_override != null:
		do_wrap = use_markdown_override

	var scene_outputs: Array[String] = []
	for file_path in paths:
		var scene_text = file_path.get_file() + ":\n"
		var packed_scene = ResourceLoader.load(file_path)
		if packed_scene is PackedScene:
			var instance = packed_scene.instantiate()
			scene_text += _build_tree_string_for_scene(instance)
			instance.queue_free()
		else:
			scene_text += "Failed to load scene."
		scene_outputs.append(scene_text)
	
	var final_content = "\n\n".join(scene_outputs)
	
	if do_wrap:
		return "```text\n" + final_content + "\n```"
	else:
		return final_content

func _build_tree_string_for_scene(root_node: Node) -> String:
	if not is_instance_valid(root_node): return ""
	
	var root_line = _get_node_info_string(root_node)
	var scene_path = root_node.get_scene_file_path()
	
	# Stop recursion if scene format matches collapsible types
	if collapse_instanced_scenes and _path_ends_with_collapsible_format(scene_path):
		return root_line
	
	var children_lines: Array[String] = []
	
	# 1. Root Signals
	var signal_strings = _get_node_signals(root_node)
	var real_children = root_node.get_children()
	var has_signals = not signal_strings.is_empty()
	var has_children = not real_children.is_empty()
	
	if has_signals:
		var is_last_item = not has_children
		children_lines.append(_format_signals_block(signal_strings, "", is_last_item))

	# 2. Root Children
	for i in range(real_children.size()):
		var child = real_children[i]
		var is_last = (i == real_children.size() - 1)
		children_lines.append(_build_tree_recursive_helper(child, "", is_last))

	return root_line + ("\n" if not children_lines.is_empty() else "") + "\n".join(children_lines)

func _build_tree_recursive_helper(node: Node, prefix: String, is_last: bool) -> String:
	var line_prefix = prefix + ("└── " if is_last else "├── ")
	var node_info = _get_node_info_string(node)
	var current_line = line_prefix + node_info
	
	var scene_path = node.get_scene_file_path()
	if collapse_instanced_scenes and _path_ends_with_collapsible_format(scene_path):
		return current_line
	
	var child_prefix = prefix + ("    " if is_last else "│   ")
	var children_lines: Array[String] = []
	
	var signal_strings = _get_node_signals(node)
	var real_children = node.get_children()
	
	var has_signals = not signal_strings.is_empty()
	var has_children = not real_children.is_empty()
	
	# Signals as pseudo-child
	if has_signals:
		var signals_is_last = not has_children 
		children_lines.append(_format_signals_block(signal_strings, child_prefix, signals_is_last))
	
	# Recursive Children
	for i in range(real_children.size()):
		var child = real_children[i]
		var is_last_child = (i == real_children.size() - 1)
		children_lines.append(_build_tree_recursive_helper(child, child_prefix, is_last_child))
		
	return current_line + ("\n" if not children_lines.is_empty() else "") + "\n".join(children_lines)

func _format_signals_block(signals: Array, prefix: String, is_last: bool) -> String:
	var connector = "└── " if is_last else "├── "
	var deep_indent = "    " if is_last else "│   "
	
	var result = prefix + connector + "signals: [\n"
	
	for i in range(signals.size()):
		var sig = signals[i]
		var comma = "," if i < signals.size() - 1 else ""
		result += prefix + deep_indent + '  "%s"%s\n' % [sig, comma]
		
	result += prefix + deep_indent + "]"
	return result

func _generate_clean_input_section() -> String:
	var output = "[input]\n\n"
	var input_props = []
	
	for prop in ProjectSettings.get_property_list():
		if prop.name.begins_with("input/"):
			input_props.append(prop.name)
	
	input_props.sort()
	
	for prop_name in input_props:
		var action_name = prop_name.trim_prefix("input/")
		
		# Exclude default Godot UI actions
		if action_name.begins_with("ui_"):
			continue
			
		var setting = ProjectSettings.get_setting(prop_name)
		
		if typeof(setting) == TYPE_DICTIONARY and setting.has("events"):
			var events = setting["events"]
			var events_str_list = []
			
			for event in events:
				var formatted = _format_input_event(event)
				if not formatted.is_empty():
					events_str_list.append(formatted)
			
			if not events_str_list.is_empty():
				output += "%s: %s\n" % [action_name, ", ".join(events_str_list)]
				
	return output.strip_edges()

func _format_input_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var k_code = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return "Key(%s)" % OS.get_keycode_string(k_code)
		
	elif event is InputEventMouseButton:
		var btn_name = ""
		match event.button_index:
			MOUSE_BUTTON_LEFT: btn_name = "Left"
			MOUSE_BUTTON_RIGHT: btn_name = "Right"
			MOUSE_BUTTON_MIDDLE: btn_name = "Middle"
			MOUSE_BUTTON_WHEEL_UP: btn_name = "WheelUp"
			MOUSE_BUTTON_WHEEL_DOWN: btn_name = "WheelDown"
			MOUSE_BUTTON_WHEEL_LEFT: btn_name = "WheelLeft"
			MOUSE_BUTTON_WHEEL_RIGHT: btn_name = "WheelRight"
			MOUSE_BUTTON_XBUTTON1: btn_name = "XBtn1"
			MOUSE_BUTTON_XBUTTON2: btn_name = "XBtn2"
			_: btn_name = str(event.button_index)
		return "MouseBtn(%s)" % btn_name
		
	elif event is InputEventJoypadButton:
		# Mapping generic names to common controller buttons
		var btn_name = str(event.button_index)
		match event.button_index:
			JOY_BUTTON_A: btn_name = "A"
			JOY_BUTTON_B: btn_name = "B"
			JOY_BUTTON_X: btn_name = "X"
			JOY_BUTTON_Y: btn_name = "Y"
			JOY_BUTTON_BACK: btn_name = "Back"
			JOY_BUTTON_GUIDE: btn_name = "Guide"
			JOY_BUTTON_START: btn_name = "Start"
			JOY_BUTTON_LEFT_STICK: btn_name = "LStick"
			JOY_BUTTON_RIGHT_STICK: btn_name = "RStick"
			JOY_BUTTON_LEFT_SHOULDER: btn_name = "LB"
			JOY_BUTTON_RIGHT_SHOULDER: btn_name = "RB"
			JOY_BUTTON_DPAD_UP: btn_name = "DpadUp"
			JOY_BUTTON_DPAD_DOWN: btn_name = "DpadDown"
			JOY_BUTTON_DPAD_LEFT: btn_name = "DpadLeft"
			JOY_BUTTON_DPAD_RIGHT: btn_name = "DpadRight"
			JOY_BUTTON_MISC1: btn_name = "Misc1"
		return "JoyBtn(%s)" % btn_name
		
	elif event is InputEventJoypadMotion:
		var axis_name = str(event.axis)
		match event.axis:
			JOY_AXIS_LEFT_X: axis_name = "LeftX"
			JOY_AXIS_LEFT_Y: axis_name = "LeftY"
			JOY_AXIS_RIGHT_X: axis_name = "RightX"
			JOY_AXIS_RIGHT_Y: axis_name = "RightY"
			JOY_AXIS_TRIGGER_LEFT: axis_name = "LT"
			JOY_AXIS_TRIGGER_RIGHT: axis_name = "RT"
			
		var dir = "+" if event.axis_value > 0 else "-"
		return "JoyAxis(%s%s)" % [axis_name, dir]
		
	return ""

func _get_node_signals(node: Node) -> Array:
	var result = []
	var signals_info = node.get_signal_list()
	
	for sig in signals_info:
		var sig_name = sig["name"]
		var connections = node.get_signal_connection_list(sig_name)
		
		for conn in connections:
			var target_obj = conn["callable"].get_object()
			var method_name = conn["callable"].get_method()
			
			if is_instance_valid(target_obj) and target_obj is Node:
				var target_name = target_obj.name
				result.append("%s -> %s :: %s" % [sig_name, target_name, method_name])
				
	result.sort()
	return result

func _get_node_info_string(node: Node) -> String:
	if not is_instance_valid(node): return "<invalid node>"
	
	var node_type = node.get_class()
	var attributes: Array[String] = []
	
	if str(node.name) != node_type: 
		attributes.append('name: "%s"' % node.name)
	
	var scene_path = node.get_scene_file_path()
	if not scene_path.is_empty(): 
		attributes.append('scene: "%s"' % scene_path)
	
	var script = node.get_script()
	if is_instance_valid(script) and not script.resource_path.is_empty():
		attributes.append('script: "%s"' % script.resource_path)
	
	# Groups
	var groups = node.get_groups()
	var user_groups = []
	for g in groups:
		if not str(g).begins_with("_"):
			user_groups.append(str(g))
	
	if not user_groups.is_empty():
		attributes.append("groups: %s" % JSON.stringify(user_groups))
	
	# Inspector Changes
	if include_inspector_changes:
		var changed_props = _get_changed_properties(node)
		if not changed_props.is_empty():
			attributes.append("changes: %s" % JSON.stringify(changed_props))
	
	var attr_str = " (" + ", ".join(attributes) + ")" if not attributes.is_empty() else ""
	return node_type + attr_str

func _get_changed_properties(node: Node) -> Dictionary:
	var changed_props = {}
	var default_node = ClassDB.instantiate(node.get_class())
	if not is_instance_valid(default_node): return {}

	for prop in node.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE:
			var prop_name = prop.name
			if prop_name in ["unique_name_in_owner", "script"]: continue

			var current_value = node.get(prop_name)
			var default_value = default_node.get(prop_name)
			
			if typeof(current_value) != typeof(default_value) or current_value != default_value:
				var formatted_value = _format_property_value(current_value)
				if formatted_value != null:
					changed_props[prop_name] = formatted_value
				
	default_node.free()
	return changed_props

func _format_property_value(value: Variant) -> Variant:
	if value == null: return null

	if typeof(value) == TYPE_OBJECT:
		if not is_instance_valid(value): return null
		if value is Resource and not value.resource_path.is_empty():
			return value.resource_path 
		return null

	if typeof(value) == TYPE_TRANSFORM3D:
		var pos = value.origin
		var rot_deg = value.basis.get_euler() * (180.0 / PI)
		var scale = value.basis.get_scale()
		var f = func(v): return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
		var parts = []
		if not pos.is_zero_approx(): parts.append("pos: " + f.call(pos))
		if not rot_deg.is_zero_approx(): parts.append("rot: " + f.call(rot_deg))
		if not scale.is_equal_approx(Vector3.ONE): parts.append("scale: " + f.call(scale))
		return ", ".join(parts) if not parts.is_empty() else "Identity"

	if typeof(value) == TYPE_TRANSFORM2D:
		var pos = value.origin
		var rot_deg = value.get_rotation() * (180.0 / PI)
		var scale = value.get_scale()
		var parts = []
		if not pos.is_zero_approx(): parts.append("pos: (%.2f, %.2f)" % [pos.x, pos.y])
		if not is_zero_approx(rot_deg): parts.append("rot: %.2f" % rot_deg)
		if not scale.is_equal_approx(Vector2.ONE): parts.append("scale: (%.2f, %.2f)" % [scale.x, scale.y])
		return ", ".join(parts) if not parts.is_empty() else "Identity"

	if typeof(value) == TYPE_ARRAY:
		var clean_array = []
		for item in value:
			var f_item = _format_property_value(item)
			if f_item != null: clean_array.append(f_item)
		if clean_array.is_empty(): return null
		return clean_array

	if typeof(value) == TYPE_BOOL: return value
	if typeof(value) == TYPE_INT: return value
	if typeof(value) == TYPE_FLOAT: return snappedf(value, 0.001)

	return str(value)

#endregion


#region File System Utilities
#-----------------------------------------------------------------------------

func _path_ends_with_collapsible_format(path: String) -> bool:
	if path.is_empty():
		return false
	for ext in collapsible_formats:
		if path.ends_with(ext):
			return true
	return false

func _find_files_recursive(path: String, extension: String) -> Array[String]:
	var files: Array[String] = []
	if path.begins_with("res://addons"): return files
	
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var item = dir.get_next()
		while item != "":
			if item == "." or item == "..":
				item = dir.get_next()
				continue
			
			var full_path = path.path_join(item)
			if dir.current_is_dir():
				files.append_array(_find_files_recursive(full_path, extension))
			elif item.ends_with(extension):
				files.append(full_path)
			
			item = dir.get_next()
	return files

#endregion
