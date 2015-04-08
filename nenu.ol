#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/Xutil.h>
#include <X11/Xft/Xft.h>
#include <X11/extensions/Xrender.h>
#include <X11/extensions/Xinerama.h>
#include <fontconfig/fontconfig.h>
#include <ctype.h>
#include <strings.h>

#define MAX(A, B) (A > B ? A : B)

#include "nenu.h"
#include "config.h"

Window root, win;
int screen;
Display *display;
GC gc;
Drawable buf;
XftDraw *draw;
Pixmap nullpixmap;

XIM xim;
XIC xic;

XftColor fg, bg;

XftFont *font;
int ascent, descent;
int heading_width, cursor_width;

int x = -1, y = -1;
int w = 0, h = 0;

int exit_on_one = 0;
int complete_on_exit = 0;
int input_bar = 1;
int read_options = 1;
int absolute_position = 0;

size_t cursor;
char *text;
char *heading;

option *options;
option *current, *valid;

void usage() {
	printf(
			"usage: nenu [-a|-c|-n|-e|-p x,y|-ap] [header]\n\n"
			"nenu takes options from stdin and display them, allowing the user to input \n"
			"their desired option\n\n"
			"    -a    : exits as soon as there is only one match.\n"
			"    -c    : on exit return the match at the begining of the list. if there is\n"
			"            no match nenu returns the user input\n"
			"    -n    : no input bar is displayed and -c is put on.\n"
			"	 -e    : takes no input from stdin\n"
			"\n"
			"    -p x,y: set window position\n"
			"    -ap   : don't shift the window so it stays inside the screen\n"
			"\n"
			"    -fg #ff00ff : set foreground and border color\n"
			"    -bg #000000 : set background color\n"
			"    -fn font    : set font.\n"
		  );
} 

void die(char *msg) {
	fprintf(stderr, "nenu [ERROR]: %s\n", msg);
	exit(EXIT_FAILURE);
}

void finish() {
	if (complete_on_exit) {
		if (current) printf("%s\n", current->text);
		else if (valid) printf("%s\n", valid->text);
	} else if (exit_on_one) {
		if (valid) printf("%s\n", valid->text);
	} else  {
		printf("%s\n", text);
	}
	exit(0);
}

int text_width(char *str) {
	XGlyphInfo g;
	int len = strlen(str);

	XftTextExtents8(display, font, str, len, &g);
	return g.width;
}

void draw_string(FcChar8 *str, int x, int y) {
	XftDrawStringUtf8(draw, &fg, font, x, y, (FcChar8 *) str, strlen(str));
}

void render_options(int oy) {
	option *o;
	int flipped;
	if (current) 
		o = current;
	else
		o = valid;

	for (flipped = 0; o; o = !o->next && !(flipped++) ? valid : o->next) {
		if (flipped && o == current)
			break;
		draw_string(o->text, PADDING, oy + ascent);
		oy += ascent + descent;
	}
}

void render() {
	char *cursor_text;
	int cursor_pos;

	update_size();
	XftDrawRect(draw, &bg, 0, 0, w, h);

	if (input_bar) {
		cursor_text = malloc(sizeof(char) * (cursor + 1));
		strncpy(cursor_text, text, cursor);
		cursor_text[cursor] = '\0';
		cursor_pos = text_width(cursor_text);
		free(cursor_text); 

		draw_string(heading, PADDING, PADDING + ascent);
		draw_string(text, PADDING + heading_width, PADDING + ascent);
		draw_string("_", PADDING + heading_width + cursor_pos, 
				PADDING + ascent);

		render_options(PADDING + ascent + 5);
	} else
		render_options(PADDING);

	XCopyArea(display, buf, win, gc, 0, 0, w, h, 0, 0);
}

void insert(char *str, ssize_t n) {
	int i, j;

	if (strlen(text) + n > MAX_LEN)
		return;

	memmove(&text[cursor + n], &text[cursor], MAX_LEN - cursor - MAX(n, 0));
	if (n > 0)
		memcpy(&text[cursor], str, n);
	cursor += n;
}

// return location of next utf8 rune in the given direction -- thanks dmenu
size_t nextrune(int inc) {
	ssize_t n;

	for (n = cursor + inc; n + inc >= 0 && (text[n] & 0xc0) == 0x80; n += inc);
	return n;
}

void handle_button(XButtonEvent be) {
	option *o;
	switch(be.button) {
		case Button4:
			if (current && current->prev)
				current = current->prev;
			else {
				for (o = valid; o && o->next; o = o->next);
				current = o;
			}
			break;
		case Button5:
			if (current && current->next)
				current = current->next;
			else
				current = valid;
			break;
		case Button1:
			finish();
			break;
		case Button3:
			finish();
			break;
		case Button2:
			finish();
			break;
	}

	render();
}

void handle_key(XKeyEvent ke) {
	char buf[32];
	int len, n;
	KeySym keysym = NoSymbol;
	Status status;
	option *o;

	len = XmbLookupString(xic, &ke, buf, sizeof(buf), &keysym, &status);
	if (status == XBufferOverflow)
		return;

	if (ke.state & ControlMask) {
		switch(keysym) {
			// Emacs
			case XK_a:
				keysym = XK_Home;
				break;
			case XK_e:
				keysym = XK_End;
				break;
			case XK_p:
				keysym = XK_Up;
				break;
			case XK_n:
				keysym = XK_Down;
				break;
			case XK_f:
				keysym = XK_Right;
				break;
			case XK_b:
				keysym = XK_Left;
				break;
			case XK_d:
				keysym = XK_Delete;
				break;
				// Vim
			case XK_j:
				keysym = XK_Down;
				break;
			case XK_k:
				keysym = XK_Up;
				break;
			case XK_h:
				keysym = XK_Left;
				break;
			case XK_l:
				keysym = XK_Right;
				break;
		}
	} else if (ke.state & Mod1Mask) {

	}

	if (input_bar) {
		switch(keysym) {
			default:
				if (!iscntrl(*buf))
					insert(buf, len);
				update_valid_options();
				break;

			case XK_Delete: // How the fuck does this work?
				if (text[cursor] == '\0')
					return;
				cursor = nextrune(+1);
				update_valid_options();

			case XK_BackSpace:
				if (cursor == 0)
					exit(0);
				insert(NULL, nextrune(-1) - cursor);
				update_valid_options();
				break;

			case XK_Tab:
				select_forward_match();
				update_valid_options();
				break;

			case XK_Left:
				if (cursor != 0)
					cursor = nextrune(-1);
				break;

			case XK_Right:
				if (text[cursor] != '\0' && cursor < MAX_LEN - 1)
					cursor = nextrune(+1);
				break;

			case XK_Home:
				cursor = 0;
				break;
			
			case XK_End:
				while (text[cursor] != '\0' && cursor < MAX_LEN - 1)
					cursor = nextrune(+1);
		}
	}

	switch(keysym) {
		case XK_Up:
			if (current->prev) {
				current = current->prev;
			} else {
				for (o = valid; o && o->next; o = o->next);
				current = o;
			}
			break;
		case XK_Down:
			if (current->next)
				current = current->next;
			else
				current = valid;
			break;
		case XK_Return:
			finish();
			break;
		case XK_Escape:
			exit(1);
			break;
	}

	if (exit_on_one) {
		for (n = 0, o = valid; o; o = o->next) n++;
		if (n == 1) {
			current = valid;
			finish();
		}
	}

	render();
}

void update_valid_options() {
	option *head = malloc(sizeof(option));
	head->next = NULL;
	option *v = head;
	option *o;

	for (o = options; o; o = o->next) {
		if (strncmp(text, o->text, strlen(text)) == 0) {
			v->next = malloc(sizeof(option));
			v->next->prev = v;
			v = v->next;
			v->text = o->text;
			v->next = NULL;
		}
	}

	valid = head->next;
	if (valid)
		valid->prev = NULL;
	free(head);
	current = valid;
}

void select_forward_match() {
	option *o;
	int i, can_move = -1, good = 1;
	char c;

	if (!valid)
		return;

	while (good) {
		c = valid->text[++can_move];
		if (!c) break;
		for (o = valid; o && good; o = o->next)
			if (o->text[can_move] != c)
				good = 0;
	}

	if (can_move > 0)
		for (i = 0; i < can_move; i++)
			text[i] = valid->text[i];
	cursor = can_move;
}

void load_font(char *fontstr) {
	FcPattern *pattern, *match;
	FcResult result;

	if (fontstr[0] == '-') 
		pattern = XftXlfdParse(fontstr, False, False);
	else
		pattern = FcNameParse((FcChar8 *) fontstr);

	if (!pattern)
		die("Failed to get font pattern");

	match = FcFontMatch(NULL, pattern, &result);
	if (!match)
		die("Failed to get font match");

	if (!(font = XftFontOpenPattern(display, match))) {
		FcPatternDestroy(match);
		die("Failed to open font");
	}

	ascent = font->ascent;
	descent = font->descent;
}

void grab_keyboard_pointer() {
	int i, p = 1, k = 1;
	XColor dummycolor;
	Cursor nullcursor;

	nullpixmap = XCreatePixmap(display, root, 1, 1, 1);
	nullcursor = XCreatePixmapCursor(display, nullpixmap, nullpixmap, 
			&dummycolor, &dummycolor, 0, 0);

	for (i = 0; (k || p) && i < 1000; i++) {

		if (p && XGrabPointer(display, root, False, ButtonPressMask,
					GrabModeAsync, GrabModeAsync, 
					win, nullcursor, CurrentTime) 
				== GrabSuccess) p = 0;

		if (k && XGrabKeyboard(display, root, True, 
					GrabModeAsync, GrabModeAsync,
					CurrentTime) == GrabSuccess) k = 0;

		usleep(1000);
	}
	if (p) die("Failed to grab pointer!");
	if (k) die("Failed to grab keyboard!");
}

void update_size() { 
	int tw;
	int ow = w, oh = h;
	option *o;

	w = heading_width + cursor_width + text_width(text);
	h = input_bar ? ascent + descent : 0;

	for (o = valid; o; o = o->next) {
		tw = text_width(o->text);
		if (tw > w)
			w = tw;
		h += ascent + descent;
	}

	w += PADDING * 2;
	h += PADDING * 2;

	if (ow == w && oh == h)
		return;

	XResizeWindow(display, win, w, h);

	if (buf)
		XFreePixmap(display, buf);
	buf = XCreatePixmap(display, win, w, h, DefaultDepth(display, screen));
	XftDrawChange(draw, buf);
}

void set_position() {
	Window ww;
	int c, v;

	/* if x,y not set then set to cursor position. */
	if (x == -1 && y == -1) 
		XQueryPointer(display, root, &ww, &ww, &x, &y, &c, &c, &v);

	XMoveWindow(display, win, x, y);
}

void keep_in_screen() {
	XineramaScreenInfo *info;
	int i, count;
	if ((info = XineramaQueryScreens(display, &count))) {
		for (i = 0; i < count; i++) 
			if (info[i].x_org <= x 
			 && x <= info[i].x_org + info[i].width 
			 && info[i].y_org <= y 
			 && y <= info[i].y_org + info[i].height)
				break;
		if (i == count) return;

		if (x + w > info[i].x_org + info[i].width)
			x = info[i].x_org + info[i].width - w - BORDER_WIDTH - 1;
		if (x < info[i].x_org) x = info[i].x_org;
		if (y + h > info[i].y_org + info[i].height)
			y = info[i].y_org + info[i].height - h - BORDER_WIDTH - 1;
		if (y < info[i].y_org) y = info[i].y_org;

		XMoveWindow(display, win, x, y);
	}
}

char *clean_tabs(char *str) {
	int i, t, c;
	char *ret;
	for (i = t = 0; str[i] && str[i] != '\n'; i++) if (str[i] == '\t') t++;
	ret = calloc(sizeof(char), i + t * (TAB_WIDTH - 1) + 1);
	for (i = c = 0; str[i] && str[i] != '\n'; i++) {
		if (str[i] == '\t') 
			for (t = 0; t < TAB_WIDTH; t++)
				ret[c++] = ' ';
		else ret[c++] = str[i];
	}

	ret[i] = '\0';
	return ret;
}

void read_input() {
	char line[512];
	option *o, *head;
	head = malloc(sizeof(option));
	head->next = NULL;
	o = head;

	while (fgets(line, sizeof(line), stdin)) {
		o->next = malloc(sizeof(option));
		o->next->prev = o;
		o = o->next;

		o->text = clean_tabs(line);
		o->next = NULL;
	}

	options = head->next;
	options->prev = NULL;
	free(head);
	update_valid_options();
}

int main(int argc, char *argv[]) {
	XSetWindowAttributes attributes;
	XWindowAttributes window_attributes;
	Visual *vis;
	Colormap cmap;
	XEvent ev;
	int i;

	char *bg_name = default_bg;
	char *fg_name = default_fg;
	char *fontstr = default_fontstr;

	cursor = 0;
	heading = "";
	text = calloc(MAX_LEN, sizeof(char));
	valid = NULL;
	current = NULL;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-h") == 0) {
			usage();
			return 0;
		} else if (strcmp(argv[i], "-a") == 0) {
			exit_on_one = 1;
		} else if (strcmp(argv[i], "-c") == 0) {
			complete_on_exit = 1;
		} else if (strcmp(argv[i], "-n") == 0) {
			complete_on_exit = 1;
			input_bar = 0;
		} else if (strcmp(argv[i], "-e") == 0) {
			read_options = 0;
		} else if (strcmp(argv[i], "-p") == 0) {
			i++;
			x = atoi(strsep(&argv[i], ","));
			y = atoi(argv[i]);
		} else if (strcmp(argv[i], "-ap") == 0) {
			absolute_position = 1;
		} else if (strcmp(argv[i], "-fg") == 0) {
			fg_name = argv[++i];
		} else if (strcmp(argv[i], "-bg") == 0) {
			bg_name = argv[++i];
		} else if (strcmp(argv[i], "-fn") == 0) {
			fontstr = argv[++i];
		} else {
			heading = clean_tabs(argv[i]);
		}
	}

	if (read_options) 
		read_input();

	display = XOpenDisplay(NULL);
	root = RootWindow(display, 0);
	screen = DefaultScreen(display);
	vis = XDefaultVisual(display, screen);
	cmap = DefaultColormap(display, screen);

	if (!XftColorAllocName(display, vis, cmap, fg_name, &fg))
		die("Failed to allocate foreground color");
	if (!XftColorAllocName(display, vis, cmap, bg_name, &bg))
		die("Failed to allocate background color");

	/* Setup and map window */
	attributes.border_pixel = fg.pixel;
	attributes.background_pixel = bg.pixel;
	attributes.override_redirect = True;
	attributes.event_mask = ExposureMask | KeyPressMask | ButtonPressMask;

	win = XCreateWindow(display, root,
			0, 0, 10, 10, BORDER_WIDTH,
			DefaultDepth(display, 0),
			CopyFromParent, CopyFromParent,
			CWBackPixel | CWOverrideRedirect | CWEventMask 
			| CWBorderPixel,
			&attributes);

	xim = XOpenIM(display, NULL, NULL, NULL);
	xic = XCreateIC(xim, XNInputStyle, XIMPreeditNothing | XIMStatusNothing,
			XNClientWindow, win, XNFocusWindow, win, NULL);

	gc = XCreateGC(display, win, 0, 0);

	buf = XCreatePixmap(display, win, 10, 10, DefaultDepth(display, screen));
	draw = XftDrawCreate(display, buf, vis, cmap);

	load_font(fontstr);

	heading_width = text_width(heading);
	cursor_width = text_width("_");

	update_size();
	set_position();
	if (!absolute_position)
		keep_in_screen();

	render();

	XMapWindow(display, win);

	grab_keyboard_pointer();

	while (!XNextEvent(display, &ev)) {
		if (ev.type == KeyPress)
			handle_key(ev.xkey);
		else if (ev.type == ButtonPress)
			handle_button(ev.xbutton);
		else if  (ev.type == Expose) {
			XRaiseWindow(display, win);
			render();
		}
	}

	XUngrabKeyboard(display, CurrentTime);
	XUngrabPointer(display, CurrentTime);
	XFreeGC(display, gc);
	XFreePixmap(display, buf);
	XFreePixmap(display, nullpixmap);

	return 0;
}
