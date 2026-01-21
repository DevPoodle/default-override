@tool
extends EditorPlugin

const DICT_SETTING_PATH := "plugins/editor/default_override/overriden_properties"
const INHERITED_SETTING_PATH := "plugins/editor/default_override/apply_to_inherited_classes"
const VERBOSE_SETTING_PATH := "plugins/editor/default_override/verbose_output"

var default_dict: Dictionary[String, Variant] = { "ExampleNode:example_property": 0.0 }
var overriden_properties: Dictionary[String, Variant]
var apply_to_inherited := true
var verbose := false

#region - Recursively find necessary nodes in editor

var scene_tree_dock: VBoxContainer
var create_dialog: ConfirmationDialog

## Finds the scene tree. There is no dedicated get_scene_tree function, and I
## don't want to include an absolute path that is likely to change in updates,
## so this is the best we can do for now.
func find_scene_tree_recursively(node: Node) -> void:
	if scene_tree_dock:
		return
	for child: Node in node.get_children():
		find_scene_tree_recursively(child)
		if child.get_class() == "SceneTreeEditor":
			if child.get_parent().get_class() == "SceneTreeDock":
				scene_tree_dock = child.get_parent()

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

func update_settings() -> void:
	if !ProjectSettings.has_setting(DICT_SETTING_PATH):
		ProjectSettings.set_setting(DICT_SETTING_PATH, default_dict)
		ProjectSettings.set_initial_value(DICT_SETTING_PATH, default_dict)
		var property_info := {
			"name": DICT_SETTING_PATH , "type": TYPE_DICTIONARY,
			"hint": PROPERTY_HINT_ENUM, "hint_string": "String;"
		}
		ProjectSettings.add_property_info(property_info)
		ProjectSettings.set_as_basic(DICT_SETTING_PATH, true)
	overriden_properties = ProjectSettings.get_setting(DICT_SETTING_PATH, default_dict)
	
	if !ProjectSettings.has_setting(INHERITED_SETTING_PATH):
		ProjectSettings.set_setting(INHERITED_SETTING_PATH, true)
		ProjectSettings.set_initial_value(INHERITED_SETTING_PATH, true)
		var property_info := {
			"name": INHERITED_SETTING_PATH, "type": TYPE_BOOL
		}
		ProjectSettings.add_property_info(property_info)
		ProjectSettings.set_as_basic(INHERITED_SETTING_PATH, true)
	apply_to_inherited = ProjectSettings.get_setting(INHERITED_SETTING_PATH, true)
	
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
	DICT_SETTING_PATH, INHERITED_SETTING_PATH, VERBOSE_SETTING_PATH]):
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

## Connected to scene_tree_dock's 'node_created' signal.
func node_instantiated(node: Node) -> void:
	if node_is_new:
		update_settings()
		for path: NodePath in overriden_properties:
			var set_default := node.get_class() == path.get_name(0)
			if apply_to_inherited:
				set_default = node.is_class(path.get_name(0))
			if set_default:
				var key := path as String
				if verbose:
					print("Default Value Set: " + key + " = " + str(overriden_properties[key]))
				node.set_indexed(path.slice(1) as String, overriden_properties[key])
	node_is_new = false

#endregion
#region - Add "Set As Default Value" option to inspector shortcut menu

const POPUP_ITEM_ID := 9

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
		if popup.id_pressed.is_connected(set_new_default_value):
			popup.id_pressed.disconnect(set_new_default_value)
		if popup.get_item_index(POPUP_ITEM_ID) != -1:
			popup.remove_item(popup.get_item_index(POPUP_ITEM_ID))
	
	popup = new_popup
	popup.add_icon_item(preload("icon.svg"), "Set As Default Value", POPUP_ITEM_ID)
	if !popup.id_pressed.is_connected(set_new_default_value):
		popup.id_pressed.connect(set_new_default_value)
	if !popup.menu_changed.is_connected(popup_changed):
		popup.menu_changed.connect(popup_changed)
	editing_popup = false

func set_new_default_value(id: int) -> void:
	if id != POPUP_ITEM_ID:
		return
	var property := editor_property.get_edited_property()
	var path := editor_property.get_edited_object().get_class() + ":" + property
	var default := editor_property.get_edited_object().get(property)
	
	update_settings()
	overriden_properties[path] = default
	if verbose:
		print("New Default Value: " + path + " = "+ str(default))

#endregion
