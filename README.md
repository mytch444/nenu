nenu
==========

Nenu is a X11 utility similar to dmenu (but visually more like the menu's in 
cwm) that takes input from stdin and presents it to the user in a way they they
can select what to return in a number of different ways.

By default nenu takes input from stdin and display it to the user in a vertical
list. The user then types which reduces the list to those that match. Once the 
user presses return nenu exits and prints what was typed to stdout.

The last non-flag argument given is used as the header.
Avaliable flags are -a, -c, -n and -e.

-a: exit as soon as there is only one match.

-c: on exit return the match at the begining of the list. If there is no match
	nenu returns the user input.

-n: no input is taken and the -c flag is set. This is useful if you want to use
	nenu to show the user something but take no input.

-e: takes no input from stdin, nenu become a text input box.

-p x,y: opens the window at x,y rather than mouse coords.

-ap: don't shift the window so it stays inside the screen.

Putting that togther, try:
	
	# ls | ./nenu "pick a file: " -a -c

Look in nexec, ntime and nwindow for examples of use. These are useable scripts
in their own right.

On exit returns 0, unless escape was pressed, then returns 1.
