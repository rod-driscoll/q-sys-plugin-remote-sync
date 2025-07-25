
# q-sys-plugin-remote-sync

Plugin for Q-Sys environment to sync components between two qsys cores.

Language: Lua\
Platform: Q-Sys

Source code location: <https://github.com/rod-driscoll/q-sys-plugin-remote-sync>

![Control tab](https://github.com/rod-driscoll/q-sys-plugin-remote-sync/blob/master/content/control.png)

![Setup tab](https://github.com/rod-driscoll/q-sys-plugin-remote-sync/blob/master/content/setup.png)

## Deploying code

Copy the *.qplug file into "%USERPROFILE%\Documents\QSC\Q-Sys Designer\Plugins" then drag the plugin into a design.

## Developing code

Instructions and resources for Q-Sys plugin development is available at:

* <https://q-syshelp.qsc.com/DeveloperHelp/>
* <https://github.com/q-sys-community/q-sys-plugin-guide/tree/master>

Do not edit the *.qplug file directly, this is created using the compiler.
"plugin.lua" contains the main code.

### Development and testing

The files in "./DEV/" are for dev only and may not be the most current code, they were created from the main *.qplug file following these instructions for run-time debugging:\
[Debugging Run-time Code](https://q-syshelp.qsc.com/DeveloperHelp/#Getting_Started/Building_a_Plugin.htm?TocPath=Getting%2520Started%257C_____3)

## Features

Sync components between cores.\
This will sync components from a remote core to the local core.\
On connection the local components will be synched with the remote components.

1. Place a component in a remote core and give it script access of 'External' or 'All'.
2. Copy and paste the component into the local core and make sure the local copy of the script has script access of 'Internal' or 'All'.
3. Repeat steps 1 and 2 for each component you want to sync between cores.
4. Add this plugin to the local core.
5. Enter the details of the remote core into this plugin.
6. Run the system and select the systems you want to sync in the plugin.

### Items of note

The original use-case of this plugin was the desire to run UCI code on a separate core to the main code, wher the local core runs the UCI and the remote core runs the main program. To achieve the requiremnt it is necessary to have a copy of any component that the UCI references on the local core.

It is recommented to use the 'common components' drop down box and select components which have the same script ID on both the local and remote cores. It is possible to sync components with different script ID names by selecting the 'Local components' and 'remote component' combos.

If local and remote components are not the same type then it will sync all controls with the same name if possible.

Only writable controls can be synched, e.g. it won't sync the status control of devices.

By default the 'code' control will not be modified in either direction to prevent accidentally overwriting scripts, this can be chaged with the controls "Enable pulling code" and "Enable pushing code".

If you enable the control "Clear local code" then the script will delete the 'code' in any local scripts if and when the local script is selected to be synched, this is for situations where you only want the buttons of the local script to trigger events on the remote script and have the remote script run without any logic being performed on the local system. If you accidentally clear the code in your scripts it is backed up and toggling "Clear local code" off will restore the original code to the scripts.

Synchronising plugins has not been tested, if you wish to synchronise a plugin then it is best to sync a remote plugin with a script on the local system, add controls to the local script with the same names as the controls you want to synch and do not add any code to the local script.

### Possible future updates

* The ability to select controls within each component and set them from the plugin.
* The ability to exclude individual controls from synching.
* It currently synchs from remote to local on connect. It could be configured to synch local to remote instead or not synch at all.
* A button to clear all components.
* Filters for component type.
* Runtime controls to enable/disable synchronising script 'code' per script.
* Look into the best way to handle plugin synchronisation.

## Changelog

20250711 v1.0.0 Rod Driscoll<rod@theavitgroup.com.au>\
Initial version

## Authors

Original author: [Rod Driscoll](rod@theavitgroup.com.au)
Revision author: [Rod Driscoll](rod@theavitgroup.com.au)
