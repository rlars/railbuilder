# railbuilder
A Minetest mod to build rails with tunnels and bridges with a simple click.<br>
Thanks to [y5nw](https://github.com/y5nw) and [Montandalar](https://github.com/Montandalar) for contributing!

## Current state
Please update to the newest version of tunnelmaker to be able to use this mod.
Also, use the latest advtrains version for a better experience.

### How to use it?
- Get the tool with */giveme railbuilder:trackmarker*.
- Use the trainmarker tool to mark the start of a rail with a right click.
- Right click at the desired end point (shown if you are close enough) or
- Right click on the current start marker to stop building.
- Hold down left mouse button and look up or down to set a slope, left click to reset.
- Hold sneak and right-click to bring up the settings. There, you can disable tunnelmaker and choose which tracks to place (standard advtrains tracks and tieless tracks currently supported).

### What does it do?
- This will trigger tunnelmaker to build tunnels / bridges / ground according to your settings.
- It will also place rails leading into the desired direction.

### Features
- Can place straight segments and slopes.
- Tries to bend the start rail (but will, currently, not add switches).
- Continue building with a single click, or stop where you are.
- Should support your tunnelmaker settings and tunnelmaker rights check.

### Warnings and limitations
- Expect bugs which eventually make your world unloadable!
- Building > 10 blocks will result in lags.
- If track nodes are out of sync with the advtrains node database, use the command */at_sync_ndb*.
- Please report any issues you encounter.
- No idea yet how to make this mobile-friendly.

### Dependencies
- [advtrains and advtrains_train_track](https://content.minetest.net/packages/orwell/advtrains/)
- [tunnelmaker](https://content.minetest.net/packages/kestral/tunnelmaker/)
