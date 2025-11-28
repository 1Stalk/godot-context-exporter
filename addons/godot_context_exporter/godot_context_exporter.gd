@tool
extends EditorPlugin

## Exports selected GDScript/C# files, Scene trees, and Project Settings into a single text file or clipboard.
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

# Scripts Tab UI
var script_list: ItemList
var select_all_scripts_checkbox: CheckBox
var group_by_folder_checkbox: CheckBox
var wrap_in_markdown_checkbox: CheckBox
var group_depth_spinbox: SpinBox
var expand_all_scripts_button: Button
var collapse_all_scripts_button: Button

# Scenes Tab UI
var scene_list: ItemList
var select_all_scenes_checkbox: CheckBox
var include_inspector_checkbox: CheckBox
var collapse_scenes_checkbox: CheckBox
var wrap_scenes_in_markdown_checkbox: CheckBox
var scene_group_by_folder_checkbox: CheckBox
var scene_group_depth_spinbox: SpinBox
var scene_expand_all_button: Button
var scene_collapse_all_button: Button

# Format Manager (Popup)
var format_manager_dialog: Window
var formats_list_vbox: VBoxContainer

# Advanced Settings (Popup)
var advanced_settings_dialog: Window

#endregion


#region State Variables
#-----------------------------------------------------------------------------

# Script State
var group_by_folder: bool = true
var group_depth: int = 0 # 0 = Auto/Tree, 1+ = Flat depth
var wrap_in_markdown: bool = false
var all_script_paths: Array[String] = []
var folder_data: Dictionary = {} # For flat grouping
var tree_nodes: Dictionary = {}  # For recursive tree (depth 0)

# Scene State
var scene_group_by_folder: bool = true
var scene_group_depth: int = 0 # 0 = Auto/Tree, 1+ = Flat depth
var all_scene_paths: Array[String] = []
# var checked_scene_paths: Array[String] = [] # Not used anymore
var scene_folder_data: Dictionary = {} # For flat grouping
var scene_tree_nodes: Dictionary = {}  # For recursive tree (depth 0)

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

# Advanced Settings State
var include_addons: bool = false

#endregion


#region Plugin Lifecycle
#-----------------------------------------------------------------------------

func _enter_tree() -> void:
	add_tool_menu_item("Context Exporter...", Callable(self, "open_window"))
	_setup_ui()

func _exit_tree() -> void:
	remove_tool_menu_item("Context Exporter...")
	if is_instance_valid(window):
		window.queue_free()
	if is_instance_valid(format_manager_dialog):
		format_manager_dialog.queue_free()
	if is_instance_valid(advanced_settings_dialog):
		advanced_settings_dialog.queue_free()

#endregion


#region UI Construction
#-----------------------------------------------------------------------------

func _setup_ui() -> void:
	window = Window.new()
	window.title = "Godot Context Exporter"
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
	
	options_hbox.add_child(VSeparator.new())
	
	group_by_folder_checkbox = CheckBox.new()
	group_by_folder_checkbox.text = "Group by Folder"
	group_by_folder_checkbox.button_pressed = true 
	group_by_folder_checkbox.toggled.connect(_on_group_by_folder_toggled)
	options_hbox.add_child(group_by_folder_checkbox)
	
	# Settings Depth
	var depth_hbox = HBoxContainer.new()
	options_hbox.add_child(depth_hbox)
	
	var depth_label = Label.new()
	depth_label.text = "Depth:"
	depth_label.tooltip_text = "0 = Recursive Tree (Auto)\n1 = Root level\n2 = Subfolder level"
	depth_hbox.add_child(depth_label)
	
	group_depth_spinbox = SpinBox.new()
	group_depth_spinbox.min_value = 0
	group_depth_spinbox.max_value = 10
	group_depth_spinbox.value = group_depth
	group_depth_spinbox.tooltip_text = depth_label.tooltip_text
	group_depth_spinbox.editable = true
	group_depth_spinbox.modulate.a = 1.0
	
	group_depth_spinbox.value_changed.connect(func(val): 
		group_depth = int(val)
		_build_script_data_model()
		_render_script_list()
	)
	depth_hbox.add_child(group_depth_spinbox)
	
	# Buttons
	options_hbox.add_child(VSeparator.new())
	
	expand_all_scripts_button = Button.new()
	expand_all_scripts_button.text = "Expand All"
	expand_all_scripts_button.pressed.connect(_on_expand_collapse_scripts.bind(true))
	options_hbox.add_child(expand_all_scripts_button)
	
	collapse_all_scripts_button = Button.new()
	collapse_all_scripts_button.text = "Collapse All"
	collapse_all_scripts_button.pressed.connect(_on_expand_collapse_scripts.bind(false))
	options_hbox.add_child(collapse_all_scripts_button)
	
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
	wrap_in_markdown_checkbox.text = "Wrap code in Markdown (```gdscript``` / ```csharp```)"
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

	var options_hbox = HBoxContainer.new()
	vbox.add_child(options_hbox)

	select_all_scenes_checkbox = CheckBox.new()
	select_all_scenes_checkbox.text = "Select All"
	select_all_scenes_checkbox.add_theme_color_override("font_color", COLOR_ACCENT)
	select_all_scenes_checkbox.pressed.connect(_on_select_all_scenes_toggled)
	options_hbox.add_child(select_all_scenes_checkbox)
	
	options_hbox.add_child(VSeparator.new())
	
	scene_group_by_folder_checkbox = CheckBox.new()
	scene_group_by_folder_checkbox.text = "Group by Folder"
	scene_group_by_folder_checkbox.button_pressed = true
	scene_group_by_folder_checkbox.toggled.connect(_on_scene_group_by_folder_toggled)
	options_hbox.add_child(scene_group_by_folder_checkbox)

	# Scene Depth Settings
	var depth_hbox = HBoxContainer.new()
	options_hbox.add_child(depth_hbox)
	
	var depth_label = Label.new()
	depth_label.text = "Depth:"
	depth_label.tooltip_text = "0 = Recursive Tree (Auto)\n1 = Root level\n2 = Subfolder level"
	depth_hbox.add_child(depth_label)
	
	scene_group_depth_spinbox = SpinBox.new()
	scene_group_depth_spinbox.min_value = 0
	scene_group_depth_spinbox.max_value = 10
	scene_group_depth_spinbox.value = scene_group_depth
	scene_group_depth_spinbox.tooltip_text = depth_label.tooltip_text
	scene_group_depth_spinbox.editable = true
	scene_group_depth_spinbox.modulate.a = 1.0
	
	scene_group_depth_spinbox.value_changed.connect(func(val): 
		scene_group_depth = int(val)
		_build_scene_data_model()
		_render_scene_list()
	)
	depth_hbox.add_child(scene_group_depth_spinbox)

	# Buttons
	options_hbox.add_child(VSeparator.new())
	
	scene_expand_all_button = Button.new()
	scene_expand_all_button.text = "Expand All"
	scene_expand_all_button.pressed.connect(_on_expand_collapse_scenes.bind(true))
	options_hbox.add_child(scene_expand_all_button)
	
	scene_collapse_all_button = Button.new()
	scene_collapse_all_button.text = "Collapse All"
	scene_collapse_all_button.pressed.connect(_on_expand_collapse_scenes.bind(false))
	options_hbox.add_child(scene_collapse_all_button)
	
	# List
	var list_panel = _create_list_panel()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(list_panel)

	scene_list = ItemList.new()
	scene_list.select_mode = ItemList.SELECT_SINGLE # Use SINGLE, logic multi choose have its own
	scene_list.allow_reselect = true
	scene_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene_list.item_clicked.connect(_on_scene_item_clicked)
	list_panel.add_child(scene_list)

	# Extra Options
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

func _create_advanced_settings_dialog() -> void:
	advanced_settings_dialog = Window.new()
	advanced_settings_dialog.title = "Advanced Settings"
	advanced_settings_dialog.min_size = Vector2i(300, 200)
	advanced_settings_dialog.size = Vector2i(400, 250)
	advanced_settings_dialog.close_requested.connect(advanced_settings_dialog.hide)
	window.add_child(advanced_settings_dialog)
	
	var bg_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = THEME_BG_COLOR
	bg_panel.add_theme_stylebox_override("panel", style)
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	advanced_settings_dialog.add_child(bg_panel)
	
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	bg_panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)
	
	var label = Label.new()
	label.text = "Scanning Options"
	label.add_theme_color_override("font_color", COLOR_ACCENT)
	vbox.add_child(label)
	
	vbox.add_child(HSeparator.new())
	
	var addons_checkbox = CheckBox.new()
	addons_checkbox.text = "Include 'addons/' folder content"
	addons_checkbox.button_pressed = include_addons
	addons_checkbox.toggled.connect(_on_include_addons_toggled)
	vbox.add_child(addons_checkbox)
	
	var info_label = Label.new()
	info_label.text = "Note: Including addons can significantly increase the list size."
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(info_label)
	
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(advanced_settings_dialog.hide)
	vbox.add_child(close_btn)

func _create_format_manager_dialog() -> void:
	format_manager_dialog = Window.new()
	format_manager_dialog.title = "Manage Collapsible Formats"
	format_manager_dialog.min_size = Vector2i(350, 400)
	format_manager_dialog.size = Vector2i(350, 500)
	format_manager_dialog.close_requested.connect(format_manager_dialog.hide)
	window.add_child(format_manager_dialog)
	
	var bg_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = THEME_BG_COLOR
	bg_panel.add_theme_stylebox_override("panel", style)
	bg_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	format_manager_dialog.add_child(bg_panel)
	
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	bg_panel.add_child(margin)
	
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

	# --- Action Buttons Row 1 (Settings) ---
	var settings_hbox = HBoxContainer.new()
	settings_hbox.alignment = BoxContainer.ALIGNMENT_END
	parent.add_child(settings_hbox)
	
	var adv_btn = Button.new()
	adv_btn.text = "Advanced Settings"
	adv_btn.flat = true
	adv_btn.add_theme_color_override("font_color", COLOR_ACCENT)
	adv_btn.pressed.connect(_on_advanced_settings_pressed)
	settings_hbox.add_child(adv_btn)

	# --- Action Buttons Row 2 (Export) ---
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
	_scan_and_refresh()
	
	status_label.remove_theme_color_override("font_color")
	status_label.text = "Select scripts and/or scenes to export."
	window.popup_centered()

func _scan_and_refresh() -> void:
	# Scripts
	var gd_scripts = _find_files_recursive("res://", ".gd")
	var cs_scripts = _find_files_recursive("res://", ".cs")
	all_script_paths = gd_scripts + cs_scripts
	all_script_paths.sort()
	
	# Scenes
	all_scene_paths = _find_files_recursive("res://", ".tscn")
	all_scene_paths.sort()
	
	_build_script_data_model()
	_render_script_list()
	
	_build_scene_data_model()
	_render_scene_list()

# --- Scripts Model ---
func _build_script_data_model() -> void:
	if group_depth == 0:
		_build_recursive_tree_data(all_script_paths, tree_nodes, "tree_nodes")
	else:
		_build_flat_group_data(all_script_paths, folder_data, group_depth)

# --- Scenes Model ---
func _build_scene_data_model() -> void:
	if scene_group_depth == 0:
		_build_recursive_tree_data(all_scene_paths, scene_tree_nodes, "scene_tree_nodes")
	else:
		_build_flat_group_data(all_scene_paths, scene_folder_data, scene_group_depth)

# --- Generic Logic Helpers ---

func _get_group_dir_for_path(path: String, depth: int) -> String:
	if depth == 0: return path.get_base_dir() # Should handle recursive elsewhere
	
	var clean_path = path.trim_prefix("res://")
	var parts = clean_path.split("/")
	
	if parts.size() - 1 < depth:
		return path.get_base_dir()
		
	var subset = parts.slice(0, depth)
	return "res://" + "/".join(subset)

func _build_flat_group_data(all_paths: Array[String], out_data: Dictionary, depth: int) -> void:
	# Save state
	var old_checked = {}
	for dir in out_data:
		if out_data[dir].has("items"):
			for path in out_data[dir]["items"]:
				if out_data[dir]["items"][path]["is_checked"]:
					old_checked[path] = true

	out_data.clear()

	for path in all_paths:
		var dir = _get_group_dir_for_path(path, depth)
		
		if not out_data.has(dir):
			out_data[dir] = { "is_expanded": true, "is_checked": false, "items": {} }
		
		var is_checked = old_checked.has(path)
		out_data[dir]["items"][path] = {"is_checked": is_checked}
	
	# Update group check state
	for dir in out_data:
		var all_checked = true
		var items = out_data[dir]["items"]
		if items.is_empty(): all_checked = false
		else:
			for path in items:
				if not items[path]["is_checked"]:
					all_checked = false; break
		out_data[dir]["is_checked"] = all_checked

func _build_recursive_tree_data(all_paths: Array[String], out_nodes: Dictionary, state_key_hint: String) -> void:
	var old_state = out_nodes.duplicate(true)
	out_nodes.clear()
	
	# Root
	if not out_nodes.has("res://"):
		var was_expanded = true
		if old_state.has("res://"): was_expanded = old_state["res://"]["is_expanded"]
		out_nodes["res://"] = { 
			"type": "folder", "parent": "", "children": [], 
			"is_expanded": was_expanded, "is_checked": false 
		}

	for file_path in all_paths:
		var was_checked = false
		if old_state.has(file_path): was_checked = old_state[file_path]["is_checked"]
		
		out_nodes[file_path] = {
			"type": "file",
			"parent": file_path.get_base_dir(),
			"children": [],
			"is_expanded": false,
			"is_checked": was_checked
		}
		
		var current_path = file_path
		while current_path != "res://":
			var parent_dir = current_path.get_base_dir()
			
			if out_nodes.has(parent_dir):
				if not out_nodes[parent_dir]["children"].has(current_path):
					out_nodes[parent_dir]["children"].append(current_path)
			else:
				var dir_expanded = true
				if old_state.has(parent_dir): dir_expanded = old_state[parent_dir]["is_expanded"]
				
				out_nodes[parent_dir] = {
					"type": "folder",
					"parent": parent_dir.get_base_dir(),
					"children": [current_path],
					"is_expanded": dir_expanded,
					"is_checked": false
				}
			
			current_path = parent_dir
			if current_path == "res://" and not out_nodes["res://"]["children"].has(current_path):
				# Safety catch, though loop should end
				pass

	# Update folder checks (simple pass)
	for path in out_nodes:
		if out_nodes[path]["type"] == "folder":
			_update_tree_folder_checked_state(path, out_nodes)

func _update_tree_folder_checked_state(folder_path: String, nodes_dict: Dictionary) -> bool:
	if not nodes_dict.has(folder_path): return false
	var node = nodes_dict[folder_path]
	if node["type"] == "file": return node["is_checked"]
	
	if node["children"].is_empty():
		node["is_checked"] = false
		return false
		
	var all_children_checked = true
	for child in node["children"]:
		if not _update_tree_folder_checked_state(child, nodes_dict):
			all_children_checked = false
	
	node["is_checked"] = all_children_checked
	return all_children_checked

# --- Script Rendering ---

func _render_script_list() -> void:
	script_list.clear()
	if group_depth == 0:
		_render_recursive_tree_list(script_list, tree_nodes, "res://", 0, "script")
	elif group_by_folder:
		_render_flat_list(script_list, folder_data, "script")
	else:
		_render_simple_flat_list(script_list, all_script_paths, folder_data, "script")

# --- Scene Rendering ---

func _render_scene_list() -> void:
	scene_list.clear()
	if scene_group_depth == 0:
		_render_recursive_tree_list(scene_list, scene_tree_nodes, "res://", 0, "scene")
	elif scene_group_by_folder:
		_render_flat_list(scene_list, scene_folder_data, "scene")
	else:
		_render_simple_flat_list(scene_list, all_scene_paths, scene_folder_data, "scene")

# --- Generic Rendering Helpers ---

func _render_recursive_tree_list(list: ItemList, nodes: Dictionary, current_path: String, indent_level: int, item_type: String) -> void:
	if not nodes.has(current_path): return
	
	var node = nodes[current_path]
	var is_folder = (node["type"] == "folder")
	
	var indent_str = "    ".repeat(indent_level)
	var checkbox = "☑ " if node["is_checked"] else "☐ "
	
	var icon = ""
	var text_name = ""
	
	if is_folder:
		icon = "▾ " if node["is_expanded"] else "▸ "
		if current_path == "res://":
			text_name = "res://"
		else:
			text_name = current_path.get_file() + "/"
	else:
		icon = "    " 
		text_name = current_path.get_file()
	
	list.add_item(indent_str + icon + checkbox + text_name)
	
	var idx = list.get_item_count() - 1
	list.set_item_metadata(idx, {
		"mode": "tree",
		"path": current_path,
		"type": node["type"],
		"item_type": item_type
	})
	
	if is_folder and node["is_expanded"]:
		var folders = []
		var files = []
		for child_path in node["children"]:
			if nodes[child_path]["type"] == "folder":
				folders.append(child_path)
			else:
				files.append(child_path)
		
		folders.sort()
		files.sort()
		
		for f in folders: _render_recursive_tree_list(list, nodes, f, indent_level + 1, item_type)
		for f in files: _render_recursive_tree_list(list, nodes, f, indent_level + 1, item_type)

func _render_flat_list(list: ItemList, data_dict: Dictionary, item_type: String) -> void:
	var sorted_folders = data_dict.keys(); sorted_folders.sort()
	for dir in sorted_folders:
		var folder_info = data_dict[dir]
		var display_dir = dir.replace("res://", "")
		if display_dir == "": display_dir = "res://"
		elif not display_dir.ends_with("/"): display_dir += "/"
		
		var checkbox = "☑ " if folder_info.is_checked else "☐ "
		var expand_symbol = "▾ " if folder_info.is_expanded else "▸ "
		
		list.add_item(expand_symbol + checkbox + display_dir)
		var folder_idx = list.get_item_count() - 1
		list.set_item_metadata(folder_idx, {"mode": "flat", "type": "folder", "dir": dir, "item_type": item_type})

		if folder_info.is_expanded:
			var sorted_items = folder_info.items.keys(); sorted_items.sort()
			for path in sorted_items:
				var item_info = folder_info.items[path]
				var item_checkbox = "☑ " if item_info.is_checked else "☐ "
				
				var display_name = path
				if dir != "res://" and path.begins_with(dir):
					display_name = path.trim_prefix(dir).trim_prefix("/")
				else:
					display_name = path.replace("res://", "")
				
				var indent_str = "        "
				list.add_item(indent_str + item_checkbox + display_name)
				
				var item_idx = list.get_item_count() - 1
				list.set_item_metadata(item_idx, {"mode": "flat", "type": "file", "path": path, "item_type": item_type})

func _render_simple_flat_list(list: ItemList, all_paths: Array[String], data_dict: Dictionary, item_type: String) -> void:
	# Even in simple mode, we use data_dict to track checked state if needed, 
	# but simple mode usually means "No grouping". 
	# To keep state consistent, we will just use the flat data logic but render without folders.
	# But wait, logic "Depth > 0" uses data_dict. Logic "No Grouping" is basically flat list.
	# To persist selection we need to look up in the data structure that is currently active or a unified one.
	# For simplicity, if Grouping is OFF, we iterate all_paths and check a "global set" or just the data_dict for keys.
	# Let's assume folder_data populated with depth-logic or simple logic. 
	
	# Actually, the requirement was "Group by Folder off". 
	# Let's map check state from folder_data (using parent dir logic)
	
	for path in all_paths:
		var is_checked = false
		# Look up in data_dict (which is built based on Depth)
		# If Depth logic was active, keys exist.
		# But if Grouping is toggled OFF, we need to know check state.
		# Let's check against the `folder_data` assuming it was built for the current state.
		var dir = _get_group_dir_for_path(path, 0 if (item_type == "script" and group_depth == 0) or (item_type == "scene" and scene_group_depth == 0) else 1)
		# This is getting complex to share state between modes.
		# Simplification: We look into folder_data searching for the path in any folder.
		for d in data_dict:
			if data_dict[d].has("items") and data_dict[d]["items"].has(path):
				is_checked = data_dict[d]["items"][path]["is_checked"]
				break
				
		var checkbox = "☑ " if is_checked else "☐ "
		list.add_item(checkbox + path.replace("res://", ""))
		var idx = list.get_item_count() - 1
		list.set_item_metadata(idx, {"mode": "simple", "type": "file", "path": path, "item_type": item_type})

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

func _on_advanced_settings_pressed() -> void:
	if not is_instance_valid(advanced_settings_dialog):
		_create_advanced_settings_dialog()
	advanced_settings_dialog.popup_centered()

func _on_include_addons_toggled(pressed: bool) -> void:
	include_addons = pressed
	_scan_and_refresh()

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

# --- Common Click Logic ---

func _handle_item_click(list: ItemList, index: int, at_position: Vector2, mouse_button_index: int, 
						tree_dict: Dictionary, flat_dict: Dictionary, is_tree_mode: bool, 
						refresh_callback: Callable, toggle_tree_cb: Callable, toggle_flat_cb: Callable) -> void:
	
	if mouse_button_index != MOUSE_BUTTON_LEFT: return
	var meta = list.get_item_metadata(index)
	if meta.is_empty(): return

	if is_tree_mode and meta["mode"] == "tree":
		var path = meta["path"]
		var node = tree_dict[path]
		
		# Heuristic for click position
		var depth = 0
		var p = node["parent"]
		while p != "":
			depth += 1
			p = tree_dict[p]["parent"]
			
		var indent_offset = depth * 25
		var arrow_zone = indent_offset + 20
		var checkbox_zone_start = arrow_zone
		
		if node["type"] == "folder":
			if at_position.x < checkbox_zone_start:
				node["is_expanded"] = not node["is_expanded"]
			else:
				toggle_tree_cb.call(path, not node["is_checked"])
		else:
			toggle_tree_cb.call(path, not node["is_checked"])
			
	elif meta["mode"] == "flat":
		if meta["type"] == "folder":
			var dir = meta["dir"]
			if at_position.x < 20: 
				flat_dict[dir].is_expanded = not flat_dict[dir].is_expanded
			else:
				flat_dict[dir].is_checked = not flat_dict[dir].is_checked
				for path in flat_dict[dir].items:
					flat_dict[dir].items[path].is_checked = flat_dict[dir].is_checked
		
		elif meta["type"] == "file":
			var path = meta["path"]
			# Find which dir contains this
			var found_dir = ""
			for d in flat_dict:
				if flat_dict[d].items.has(path):
					found_dir = d; break
			
			if found_dir != "":
				flat_dict[found_dir].items[path].is_checked = not flat_dict[found_dir].items[path].is_checked
				# Update folder check
				var all_checked = true
				for s_path in flat_dict[found_dir].items:
					if not flat_dict[found_dir].items[s_path].is_checked:
						all_checked = false; break
				flat_dict[found_dir].is_checked = all_checked
				
	elif meta["mode"] == "simple":
		# Simple Flat
		var path = meta["path"]
		# Update in flat_dict to persist state
		for d in flat_dict:
			if flat_dict[d].items.has(path):
				flat_dict[d].items[path].is_checked = not flat_dict[d].items[path].is_checked

	refresh_callback.call()

# --- Script Event Handlers ---

func _on_script_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	_handle_item_click(script_list, index, at_position, mouse_button_index, 
		tree_nodes, folder_data, group_depth == 0, 
		_render_script_list, _toggle_script_tree_checkbox, Callable())

func _toggle_script_tree_checkbox(path: String, new_state: bool) -> void:
	_toggle_generic_tree_checkbox(path, new_state, tree_nodes)

func _on_group_by_folder_toggled(pressed: bool) -> void:
	group_by_folder = pressed
	if is_instance_valid(group_depth_spinbox):
		group_depth_spinbox.editable = pressed
		group_depth_spinbox.modulate.a = 1.0 if pressed else 0.5
	
	if is_instance_valid(expand_all_scripts_button):
		expand_all_scripts_button.disabled = not pressed
		collapse_all_scripts_button.disabled = not pressed

	_build_script_data_model()
	_render_script_list()

func _on_expand_collapse_scripts(do_expand: bool) -> void:
	_expand_collapse_generic(do_expand, group_depth == 0, tree_nodes, folder_data)
	_render_script_list()

func _on_select_all_scripts_toggled() -> void:
	var is_checked = select_all_scripts_checkbox.button_pressed
	if group_depth == 0:
		_toggle_generic_tree_checkbox("res://", is_checked, tree_nodes)
	else:
		_select_all_flat(is_checked, folder_data)
	_render_script_list()

# --- Scene Event Handlers ---

func _on_scene_item_clicked(index: int, at_position: Vector2, mouse_button_index: int) -> void:
	# Using the same generic handler
	_handle_item_click(scene_list, index, at_position, mouse_button_index,
		scene_tree_nodes, scene_folder_data, scene_group_depth == 0,
		_render_scene_list, _toggle_scene_tree_checkbox, Callable())

func _toggle_scene_tree_checkbox(path: String, new_state: bool) -> void:
	_toggle_generic_tree_checkbox(path, new_state, scene_tree_nodes)

func _on_scene_group_by_folder_toggled(pressed: bool) -> void:
	scene_group_by_folder = pressed
	if is_instance_valid(scene_group_depth_spinbox):
		scene_group_depth_spinbox.editable = pressed
		scene_group_depth_spinbox.modulate.a = 1.0 if pressed else 0.5
	
	if is_instance_valid(scene_expand_all_button):
		scene_expand_all_button.disabled = not pressed
		scene_collapse_all_button.disabled = not pressed

	_build_scene_data_model()
	_render_scene_list()

func _on_expand_collapse_scenes(do_expand: bool) -> void:
	_expand_collapse_generic(do_expand, scene_group_depth == 0, scene_tree_nodes, scene_folder_data)
	_render_scene_list()

func _on_select_all_scenes_toggled() -> void:
	var is_checked = select_all_scenes_checkbox.button_pressed
	if scene_group_depth == 0:
		_toggle_generic_tree_checkbox("res://", is_checked, scene_tree_nodes)
	else:
		_select_all_flat(is_checked, scene_folder_data)
	_render_scene_list()

# --- Generic Logic Implementations ---

func _toggle_generic_tree_checkbox(path: String, new_state: bool, nodes: Dictionary) -> void:
	if not nodes.has(path): return
	var node = nodes[path]
	
	node["is_checked"] = new_state
	if node["type"] == "folder":
		for child in node["children"]:
			_toggle_generic_tree_checkbox(child, new_state, nodes)
			
	_update_parent_check_state(node["parent"], nodes)

func _update_parent_check_state(parent_path: String, nodes: Dictionary) -> void:
	if parent_path == "" or not nodes.has(parent_path): return
	
	var parent = nodes[parent_path]
	var all_checked = true
	for child in parent["children"]:
		if not nodes[child]["is_checked"]:
			all_checked = false; break
	
	if parent["is_checked"] != all_checked:
		parent["is_checked"] = all_checked
		_update_parent_check_state(parent["parent"], nodes)

func _expand_collapse_generic(do_expand: bool, is_tree: bool, tree_dict: Dictionary, flat_dict: Dictionary) -> void:
	if is_tree:
		for path in tree_dict:
			if tree_dict[path]["type"] == "folder":
				tree_dict[path]["is_expanded"] = do_expand
	else:
		for dir in flat_dict:
			flat_dict[dir]["is_expanded"] = do_expand

func _select_all_flat(is_checked: bool, flat_dict: Dictionary) -> void:
	for dir in flat_dict:
		flat_dict[dir].is_checked = is_checked
		for path in flat_dict[dir].items:
			flat_dict[dir].items[path].is_checked = is_checked

#endregion


#region Export Logic
#-----------------------------------------------------------------------------

func _export_selected(to_clipboard: bool) -> void:
	var selected_scripts = _get_selected_script_paths()
	var selected_scenes = _get_selected_scene_paths()
	
	selected_scripts.sort()
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
		var output_path = "res://context_export.txt"
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
	
	for prop in ProjectSettings.get_property_list():
		var name = prop.name
		if name.begins_with("autoload/"):
			var path = ProjectSettings.get_setting(name)
			if path.begins_with("*"):
				path = path.substr(1)
			if path.ends_with(".gd") or path.ends_with(".cs"):
				result["scripts"].append(path)
			elif path.ends_with(".tscn"):
				result["scenes"].append(path)
				
	return result

func _get_selected_script_paths() -> Array[String]:
	return _get_selected_paths_generic(group_depth == 0, tree_nodes, folder_data)

func _get_selected_scene_paths() -> Array[String]:
	return _get_selected_paths_generic(scene_group_depth == 0, scene_tree_nodes, scene_folder_data)

func _get_selected_paths_generic(is_tree: bool, tree_dict: Dictionary, flat_dict: Dictionary) -> Array[String]:
	var selected: Array[String] = []
	if is_tree:
		for path in tree_dict:
			if tree_dict[path]["type"] == "file" and tree_dict[path]["is_checked"]:
				selected.append(path)
	else:
		for dir in flat_dict:
			for path in flat_dict[dir].items:
				if flat_dict[dir].items[path].is_checked:
					selected.append(path)
	return selected

#endregion


#region Content Formatters
#-----------------------------------------------------------------------------

func _build_project_godot_content() -> String:
	var content = ""
	content += "[application]\n"
	
	var app_name = ProjectSettings.get_setting("application/config/name", "")
	if not app_name.is_empty():
		content += 'config/name="%s"\n' % app_name
	
	var main_scene = ProjectSettings.get_setting("application/run/main_scene", "")
	if not main_scene.is_empty():
		if main_scene.begins_with("uid://"):
			var uid_id = ResourceUID.text_to_id(main_scene)
			if ResourceUID.has_id(uid_id):
				main_scene = ResourceUID.get_id_path(uid_id)
		content += 'run/main_scene="%s"\n' % main_scene
	content += "\n"

	var autoloads = _get_project_settings_section("autoload")
	if not autoloads.is_empty():
		content += "[autoload]\n"
		for key in autoloads:
			content += '%s="%s"\n' % [key, autoloads[key]]
		content += "\n"

	var groups = _get_project_settings_section("global_group")
	if not groups.is_empty():
		content += "[global_group]\n"
		for key in groups:
			content += '%s="%s"\n' % [key, groups[key]]
		content += "\n"
		
	var layers = _get_project_settings_section("layer_names")
	var active_layers = {}
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
				var lang_tag = "gdscript"
				if file_path.ends_with(".cs"):
					lang_tag = "csharp"
				content += "```" + lang_tag + "\n" + file_content + "\n```\n\n"
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
	
	if collapse_instanced_scenes and _path_ends_with_collapsible_format(scene_path):
		return root_line
	
	var children_lines: Array[String] = []
	
	var signal_strings = _get_node_signals(root_node)
	var real_children = root_node.get_children()
	var has_signals = not signal_strings.is_empty()
	var has_children = not real_children.is_empty()
	
	if has_signals:
		var is_last_item = not has_children
		children_lines.append(_format_signals_block(signal_strings, "", is_last_item))

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
	
	if has_signals:
		var signals_is_last = not has_children 
		children_lines.append(_format_signals_block(signal_strings, child_prefix, signals_is_last))
	
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
		if action_name.begins_with("ui_"): continue
			
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
	if not include_addons and path.begins_with("res://addons"): return files
	
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
