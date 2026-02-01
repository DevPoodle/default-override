@tool
extends EditorPlugin

const NON_INHERITED_DICT_SETTING_PATH := "plugins/editor/default_override/non_inherited_overriden_properties"
const INHERITED_DICT_SETTING_PATH := "plugins/editor/default_override/inherited_overriden_properties"
const VERBOSE_SETTING_PATH := "plugins/editor/default_override/verbose_output"

var default_dict: Dictionary[String, Variant] = { "ExampleNode:example_property": 0.0 }
var non_inherited_overriden_properties: Dictionary[String, Variant]
var inherited_overriden_properties: Dictionary[String, Variant]
var verbose := false

#region - Recursively find necessary nodes in editor

var scene_tree_dock: Node
var create_dialog: ConfirmationDialog
var version: int = Engine.get_version_info()["minor"]

## Finds the scene tree. There is no dedicated get_scene_tree function, and I
## don't want to include an absolute path that is likely to change in updates,
## so this is the best we can do for now.
func find_scene_tree_recursively(node: Node) -> void:
	if scene_tree_dock:
		return
	for child: Node in node.get_children():
		find_scene_tree_recursively(child)
		if child.get_class() == "SceneTreeEditor":
			var dock := child.get_node("../../../" if version > 5 else "../")
			if dock.get_class() == "SceneTreeDock":
				scene_tree_dock = dock

## Finds the editor property that edits the property described by path.
func find_property_recursively(node: Node, path: String) -> EditorProperty:
	for child: Node in node.get_children():
		if child is EditorProperty and child.get_edited_property() == path:
			return child
		var property := find_property_recursively(child, path)
		if property:
			return property
	return null

#endregion
#region - Initialize and deinitialize plugin and plugin settings

func setup_dict_setting(path: String) -> Dictionary[String, Variant]:
	# Duplicate to make sure different settings don't reference each other.
	var default_value := default_dict.duplicate()
	
	if !ProjectSettings.has_setting(path):
		ProjectSettings.set_setting(path, default_value)
		ProjectSettings.set_initial_value(path, default_value)
		var property_info := {
			"name": path , "type": TYPE_DICTIONARY,
			"hint": PROPERTY_HINT_ENUM, "hint_string": "String;"
		}
		ProjectSettings.add_property_info(property_info)
		ProjectSettings.set_as_basic(path, true)
	
	return ProjectSettings.get_setting(path, default_value)

func update_settings() -> void:
	non_inherited_overriden_properties = setup_dict_setting(NON_INHERITED_DICT_SETTING_PATH)
	inherited_overriden_properties = setup_dict_setting(INHERITED_DICT_SETTING_PATH)
	
	if !ProjectSettings.has_setting(VERBOSE_SETTING_PATH):
		ProjectSettings.set_setting(VERBOSE_SETTING_PATH, false)
		ProjectSettings.set_initial_value(VERBOSE_SETTING_PATH,false)
		var property_info := {
			"name": VERBOSE_SETTING_PATH, "type": TYPE_BOOL
		}
		ProjectSettings.add_property_info(property_info)
		ProjectSettings.set_as_basic(VERBOSE_SETTING_PATH, false)
	verbose = ProjectSettings.get_setting(VERBOSE_SETTING_PATH, false)

func _enter_tree() -> void:
	update_settings()
	
	find_scene_tree_recursively(EditorInterface.get_base_control())
	for child: Node in scene_tree_dock.get_children():
		if child.get_class() == "CreateDialog":
			create_dialog = child
			break
	create_dialog.connect("create", new_node_created)
	scene_tree_dock.connect("node_created", node_instantiated, ConnectFlags.CONNECT_DEFERRED)
	EditorInterface.get_inspector().property_selected.connect(property_selected)

func _exit_tree() -> void:
	create_dialog.disconnect("create", new_node_created)
	scene_tree_dock.disconnect("node_created", node_instantiated)
	ProjectSettings.save()

func _disable_plugin() -> void:
	for setting: String in PackedStringArray([
	NON_INHERITED_DICT_SETTING_PATH, INHERITED_DICT_SETTING_PATH, VERBOSE_SETTING_PATH]):
		if ProjectSettings.has_setting(setting):
			ProjectSettings.set_setting(setting, null)

#endregion
#region - Override properties when new nodes are created

## Multiple actions can trigger the scene_tree_dock's 'node_created' signal,
## so we need to make sure a fully new node is being created.
var node_is_new := false

## Connected to create_dialog's 'create' signal.
func new_node_created() -> void:
	node_is_new = true

## Returns whether `child_script` inherits the given `base_class_name`.
## Only checks for custom global classes (aka `class_name`).
func inherits_global_class(child_script: Script, base_class_name: StringName) -> bool:
	if child_script.get_global_name() == base_class_name:
		return true
	
	var base_script := child_script.get_base_script()
	if not base_script:
		return false
	
	return inherits_global_class(base_script, base_class_name)

func override_node_properties(node: Node, overriden_properties_dict: Dictionary, apply_to_inherited: bool) -> void:
	var node_script: Script = node.get_script()
	
	for path: NodePath in overriden_properties_dict:
		var owner_name := path.get_name(0)
		var set_default := false
		
		if ClassDB.class_exists(owner_name):
			set_default = node.get_class() == owner_name
			
			if apply_to_inherited:
				set_default = node.is_class(owner_name)
		elif node_script:
			set_default = node_script.get_global_name() == owner_name
			
			if apply_to_inherited:
				set_default = inherits_global_class(node_script, owner_name)
		
		if set_default:
			var key := path as String
			if verbose:
				print("Default Value Set: " + key + " = " + str(overriden_properties_dict[key]))
			
			node.set_indexed(path.slice(1) as String, overriden_properties_dict[key])

## Connected to scene_tree_dock's 'node_created' signal.
func node_instantiated(node: Node) -> void:
	if node_is_new:
		update_settings()
		# Overrides inherited first to give priority for non-inherited.
		override_node_properties(node, inherited_overriden_properties, true)
		override_node_properties(node, non_inherited_overriden_properties, false)
	
	node_is_new = false

#endregion
#region - Add "Set As Default Value" and "Set As Default Value (Inherited)" options to inspector shortcut menu

const NON_INHERITED_POPUP_ITEM_ID := 9
const INHERITED_POPUP_ITEM_ID := 10

var editor_property: EditorProperty
var popup: PopupMenu
var editing_popup := false ## Makes sure we don't call popup_changed recursively

## Connected to the inspector's 'property_selected' signal.
func property_selected(property: String) -> void:
	editor_property = find_property_recursively(EditorInterface.get_inspector(), property)
	try_to_setup_popup()

## Connected to editor_property's 'child_entered_tree' signal.
func popup_created(node: Node) -> void:
	if node is PopupMenu and node.get_parent() == editor_property:
		await get_tree().process_frame
		try_to_setup_popup()

## Connected to popup's 'menu_changed' signal.
func popup_changed() -> void:
	if editing_popup:
		return
	editing_popup = true
	await get_tree().process_frame
	editing_popup = false
	try_to_setup_popup()

## Attempts to add our button to popup, with a few fail-safes if popup doesn't exist.
## Unfortunately, we have no control over when EditorProperty decides to initialize popup.
func try_to_setup_popup() -> void:
	var new_popup: PopupMenu
	for child: Node in editor_property.get_children():
		if child is PopupMenu:
			new_popup = child
			break
	if !new_popup:
		if !editor_property.child_entered_tree.is_connected(popup_created):
			editor_property.child_entered_tree.connect(popup_created)
		return
	
	editing_popup = true
	if popup:
		for set_default_value: Callable in [add_new_non_inherited_default_value, add_new_inherited_default_value]:
			if popup.id_pressed.is_connected(set_default_value):
				popup.id_pressed.disconnect(set_default_value)
		
		for popup_item_id: int in [NON_INHERITED_POPUP_ITEM_ID, INHERITED_POPUP_ITEM_ID]:
			if popup.get_item_index(popup_item_id) != -1:
				popup.remove_item(popup.get_item_index(popup_item_id))
	
	popup = new_popup
	
	var edited_object := editor_property.get_edited_object()
	var edited_property := editor_property.get_edited_property()
	var is_built_in := false
	
	# Check whether the edited property is built-in.
	for property: Dictionary in ClassDB.class_get_property_list(edited_object.get_class()):
		if property["name"] == edited_property:
			is_built_in = true
	
	# Skip adding buttons for non–built-in properties on nodes without a global name (aka `class_name`).
	var edited_object_script: Script = edited_object.get_script()
	var edited_object_global_name := edited_object_script.get_global_name() if edited_object_script else ""
	if not is_built_in and not edited_object_global_name:
		return
	
	popup.add_icon_item(preload("icon.svg"), "Set As Default Value", NON_INHERITED_POPUP_ITEM_ID)
	popup.add_icon_item(preload("icon.svg"), "Set As Default Value (Inherited)", INHERITED_POPUP_ITEM_ID)
	
	for set_default_value: Callable in [add_new_non_inherited_default_value, add_new_inherited_default_value]:
		if not popup.id_pressed.is_connected(set_default_value):
			popup.id_pressed.connect(set_default_value)
	
	if !popup.menu_changed.is_connected(popup_changed):
		popup.menu_changed.connect(popup_changed)
	
	editing_popup = false

# Uses a Callable to work around an issue where passing property dictionaries directly
# causes the reference to be lost after calling update_settings().
func add_new_default_value(id: int, ITEM_ID: int, add_value_callable: Callable) -> void:
	if id != ITEM_ID:
		return
	
	var edited_property := editor_property.get_edited_property()
	var edited_object := editor_property.get_edited_object()
	
	# The name registered with the property.
	var owner_name := editor_property.get_edited_object().get_class()
	
	# If the object has a global name (aka `class_name`), use it instead.
	var edited_object_script: Script = edited_object.get_script()
	var edited_object_global_name := edited_object_script.get_global_name() if edited_object_script else ""
	if edited_object_global_name:
		owner_name = edited_object_global_name
	
	var path := owner_name + ":" + edited_property
	var default := editor_property.get_edited_object().get(edited_property)
	
	update_settings()
	add_value_callable.call(path, default)
	
	if verbose:
		print("New Default Value: " + path + " = "+ str(default))

# Uses separate method because Godot treats a Callable with different bound parameters as identical,
# preventing connecting them to the same signal twice.
func add_new_non_inherited_default_value(id: int) -> void:
	add_new_default_value(id, NON_INHERITED_POPUP_ITEM_ID, func(path: String, default: Variant):
			non_inherited_overriden_properties[path] = default
			inherited_overriden_properties.erase(path)
	)

func add_new_inherited_default_value(id: int) -> void:
	add_new_default_value(id, INHERITED_POPUP_ITEM_ID, func(path: String, default: Variant):
			inherited_overriden_properties[path] = default
			non_inherited_overriden_properties.erase(path)
	)

#endregion
