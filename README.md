# railbuilder
A Minetest mod to build rails with tunnels and bridges with a simple click.

### How to use it?
- Use the trainmarker tool to mark the start of a rail with a right click.
- Right click at the desired end point (shown if you are close enough) or
- Right click on the current start marker to stop building.
- Hold down left mouse button and look up or down to set a slope, left click to reset.

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
- Please report any issues you encounter.
- No idea yet how to make this mobile-friendly.

### Dependencies
- [advtrains and advtrains_train_track](https://content.minetest.net/packages/orwell/advtrains/)
- [tunnelmaker](https://content.minetest.net/packages/kestral/tunnelmaker/)
