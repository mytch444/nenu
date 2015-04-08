nenu
==========

Nenu is a X11 utility similar to dmenu (but visually more like the menu's in 
cwm) that takes input from stdin and presents it to the user in a way they they
can select what to return in a number of different ways.

By default nenu takes input from stdin and display it to the user in a vertical
list. The user then types which reduces the list to those that match. Once the 
user presses return nenu exits and prints what was typed to stdout.

Check out the man page.

Look in nexec, ntime and nwindow for examples of use. These are useable scripts
in their own right.

On exit returns 0, unless escape was pressed, then returns 1.
Seems to be unicode safe, haven't don't much testing though.