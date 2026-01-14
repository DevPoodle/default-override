# Default Value Overrider
This is a [Godot](https://godotengine.org/) 4.5 plugin that lets you override
the default values of node properties.

## How to Use
In a node's inspector, change the given property to the new default value you
want. Then, right-click on the property. You should see a "Set As Default Value"
option. When pressed, it stores a path to the property and the new value. Now,
whenever you create a new node from the Scene dock, it will automatically have
its property changed.

Here are some recommend use-cases:
- Change OmniLight3D and SpotLight3D's default attenuation. To be physically
accurate, these should be set to 2.0 by default, but at the moment, the default
is 1.0.
- Setting y_sort enabled. If you're rendering a 2D scene using y_sort, then
you'll likely want most of the Node2D's in the scene to have y_sort enabled by
default.
- Disabling Camera2D's ignore_rotation property. By default, all Camera2D's
ignore their rotation. If you're making a game that regularly rotates the
camera, then this setting should probably be set to false.

## Settings
*Overriden Properties:* A dictionary containing pairs from node property paths
to their new default value. The first entry is an example of how add an entry
manually.

*Apply to Inherited Classes:* If true, default values will also be overriden for
node types that inherit the class they were specified for. For example, if you
set y_sort to true for Node2Ds, then it will also be changed for Sprite2Ds.
Otherwise, it will only apply to the base class.

*Verbose Output:* If true, the plugin will output text when it does something.
Useful for debugging the plugin, but not for regular use.

## Limitations
Most of these limitations are intentional, but they're still worth mentioning.
First, this does not override the values for already created nodes. It only
applies to new nodes going forward. Second, it does not override the values of
nodes instantiated at run-time. This is purely an editor tool. Finally, the new
defaults are stored in Project Settings, not Editor Settings, so each of your
Godot projects can have different defaults set.

## Possible Additions
There are a few new features being considered:
- Allow default values of resources to be changed. I have a feeling this would
be substantially more difficult than it is for scenes, but I'd need to look into
it further.
- Add separate Editor Settings options. These would be applied first, and then
the options in Project Settings would be added on top.
- Add settings to specify whether each individual override should apply only to
base classes or also to inherited ones.

## YouTube
This plugin was created by me, DevPoodle! I'll probably have a video out about
it soon, with a more thorough explanation on how the plugin works and the
choices I took while I making it. So keep an eye out for that. Thanks!
