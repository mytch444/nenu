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

static Window root, win;
static int screen;
static Display *display;
static GC gc;
static Drawable buf;
static XftDraw *draw;
static Pixmap nullpixmap;

static int max_width, max_height;
static int draw_options;

static XIM xim;
static XIC xic;

static XftColor fg, bg;

static XftFont *font;
static int ascent, descent;
static int prompt_width, cursor_width;

static int x = -1, y = -1;
static int w = 0, h = 0;

static int exit_on_one = 0;
static int first_on_exit = 0;
static int text_input = 1;
static int read_options = 1;
static int print_on_exit = 1;
static int absolute_position = 0;
static int grab = 1;

static size_t cursor = 0;
static FcChar8 text[MAX_LEN] = {'\0'};
static FcChar8 prompt[MAX_LEN] = {'\0'};

static option *options = NULL;
static option *valid = NULL;

void usage() {
	printf(
"usage: nenu [options] [prompt]\n"
"\n"
"    nenu takes options from stdin and displays them in a list,\n"
"    allowing the user to choose their deisred option.\n"
"\n"
"    -o   : exits as soon as there is only ONE match.\n"
"    -f   : on exit return the FIRST match.\n"
"           if there are no matchs return user input.\n"
"    -t   : no TEXT input\n"
"    -q   : no output on exit\n"
"    -n   : take NO input from stdin\n"
"    -g   : don't grab keyboard and cursor (useful if you just want it as a message)\n"
"\n"
"    --pos x,y\n"
"         : set window position\n"
"    --abs\n"
"         : don't shift the window so it stays inside the screen\n"
"\n"
"    --fg c\n"
"         : set foreground and border color\n"
"    --bg c\n"
"         : set background color\n"
"    --fn font\n"
"         : set font.\n"
	);
} 

void clean_resources() {
	XUngrabKeyboard(display, CurrentTime);
	XUngrabPointer(display, CurrentTime);
	XFreeGC(display, gc);
	XFreePixmap(display, buf);
	XFreePixmap(display, nullpixmap);
}

void die(char *msg) {
	fprintf(stderr, "nenu [ERROR]: %s\n", msg);
	exit(EXIT_FAILURE);
}

void finish() {
	if (print_on_exit) {
		if ((first_on_exit || exit_on_one) && valid) 
			printf("%s\n", valid->text);
		else
			printf("%s\n", text);
	}
	
	clean_resources();
	exit(EXIT_SUCCESS);
}

int text_width(FcChar8 *s) {
	XGlyphInfo g;
	int i, len = strlen(s);
	/* XftTextExtentsUtf8 doesn't seem to know what a space is. */
	char str[MAX_LEN];
	strcpy(str, s);
	for (i = 0; i < len; i++) 
		if (str[i] == ' ') str[i] = '-';
	
	XftTextExtentsUtf8(display, font, str, len, &g);
	return g.width;
}

void draw_string(FcChar8 *s, int x, int y) {
	if (x > w * 2 || y > h * 2) return;
	XftDrawStringUtf8(draw, &fg, font, x, y,
	                  (FcChar8 *) s, strlen(s));
}

void render_options(int oy) {
	option *o = valid;
	int flip = 2;
	while (flip) {
		if (flip == 1 && o == valid) break;
		if (o) {
			draw_string(o->text, PADDING, oy + ascent);
			oy += ascent + descent;
			o = o->next;
		} else if (--flip && valid) {
			for (o = valid->prev; o && o->prev; o = o->prev);
		}
	}
}

void render() {
	int cursor_pos;
	FcChar8 t;

	update_size();
	update_position();
	
	XftDrawRect(draw, &bg, 0, 0, w, h);

	if (prompt[0])
		draw_string(prompt, PADDING, PADDING + ascent);

	if (text_input) {
		draw_string(text, PADDING + prompt_width,
		                  PADDING + ascent);
		
		t = text[cursor];
		text[cursor] = '\0';
		cursor_pos = prompt_width + text_width(text);
		text[cursor] = t;

		draw_string("_", PADDING + 1 + cursor_pos, 
				PADDING + ascent);
	}

	printf("draw options = %i\n", draw_options);
	if (draw_options)
		render_options(PADDING + ((text_input || prompt[0]) ?
		                ascent + descent : 0));

	XCopyArea(display, buf, win, gc, 0, 0, w, h, 0, 0);
}

void insert(FcChar8 *str, ssize_t n) {
	int i, j;

	if (strlen(text) + n > MAX_LEN)
		return;

	memmove(&text[cursor + n], &text[cursor], 
	        MAX_LEN - cursor - MAX(n, 0));
	if (n > 0)
		memcpy(&text[cursor], str, n);
	cursor += n;
}

void copy_first() {
	if (valid) {
		strcpy(text, valid->text);
		while (text[cursor] != '\0' && cursor < MAX_LEN - 1)
			cursor = nextrune(+1);					
		update_valid_options();
	}
}

/* return location of next utf8 rune in the given direction
 * -- thanks dmenu */
size_t nextrune(int inc) {
	ssize_t n;

	for (n = cursor + inc;
	     n + inc >= 0 && (text[n] & 0xc0) == 0x80;
	     n += inc);
	return n;
}

void handle_button(XButtonEvent be) {
	option *o;
	switch(be.button) {
		case Button4:
			if (valid->prev) 
				valid = valid->prev;
			else
				for (; valid && valid->next;
				     valid = valid->next);
			break;
		case Button5:
			if (valid->next) 
				valid = valid->next;
			else
			 	for (; valid && valid->prev;
			 	     valid = valid->prev);	
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
	FcChar8 buf[32];
	int len, n;
	KeySym keysym = NoSymbol;
	Status status;
	option *o;

	len = XmbLookupString(xic, &ke, buf, sizeof(buf),
	                      &keysym, &status);
	if (status == XBufferOverflow)
		return;

	if (ke.state & ControlMask) {
		switch(keysym) {
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
			case XK_bracketleft:
				keysym = XK_Escape;
				break;
			case XK_k:
				text[cursor] = '\0';
				break;
		}
	}

	if (text_input) {
		switch(keysym) {
			default:
				if (!iscntrl(*buf)) {
					insert(buf, len);
					update_valid_options();
				}
				break;

			case XK_Delete:
				if (text[cursor] == '\0') break;
				cursor = nextrune(+1);
				
				/* Fall through to backspace */

			case XK_BackSpace:
				if (cursor == 0)
					exit(0);
				insert(NULL, nextrune(-1) - cursor);
				update_valid_options();
				break;

			case XK_Tab:
				copy_first();
				break;

			case XK_Left:
				if (cursor != 0)
					cursor = nextrune(-1);
				break;

			case XK_Right:
				if (text[cursor] != '\0') 
					cursor = nextrune(+1);
				break;

			case XK_Home:
				cursor = 0;
				break;
			
			case XK_End:
				while (text[cursor] != '\0')
					cursor = nextrune(+1);
		}
	}

	switch(keysym) {
		case XK_Up:
			if (valid->prev) 
				valid = valid->prev;
			else
				for (; 
				     valid && valid->next; 
				     valid = valid->next);
			break;
		case XK_Down:
			if (valid->next) 
				valid = valid->next;
			else
			 	for (; 
			 	     valid && valid->prev;
			 	     valid = valid->prev);
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
		if (n == 1) finish();
	}

	render();
}

void update_valid_options() {
	option *head, *o, *v;
	v = head = calloc(sizeof(option), 1);

	for (o = valid; o && o->prev; o = o->prev);
	for (; o; o = o->next) 
		free(o);

	for (o = options; o; o = o->next) {
		if (strncmp(text, o->text, strlen(text)) == 0) {
			v->next = malloc(sizeof(option));
			v->next->prev = v;
			v = v->next;
			v->text = o->text;
			v->next = NULL;
		}
	}

	if (head->next)
		head->next->prev = NULL;
	valid = head->next;
	free(head);
}

void load_font(FcChar8 *font_str) {
	FcPattern *pattern, *match;
	FcResult result;

	if (font_str[0] == '-') 
		pattern = XftXlfdParse(font_str, False, False);
	else
		pattern = FcNameParse((FcChar8 *) font_str);

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
	nullcursor = XCreatePixmapCursor(display,
	                nullpixmap, nullpixmap, 
	                &dummycolor, &dummycolor, 0, 0);

	if (!grab) return;
	/* Keep trying for pointer. */
	for (; p; ) {
		if (XGrabPointer(display, root, False,
		                 ButtonPressMask|ButtonReleaseMask,
		                 GrabModeAsync, GrabModeAsync, 
		                 win, nullcursor, CurrentTime) 
				== GrabSuccess)
			p = 0;
		usleep(10000);
	}
	/* Because we won't grab keyboard until pointer has been
	 * gotten. Then only try a few times for keyboard */
	for (i = 0; k && i < 1000; i++) {
		if (XGrabKeyboard(display, root, True, 
		               GrabModeAsync, GrabModeAsync,
		               CurrentTime) == GrabSuccess)
			k = 0;
		usleep(1000);
	}

	if (k) die("Failed to grab keyboard!");
}

void update_size() { 
	int ow = w, oh = h;
	int tw, bw, bh;
	option *o;

	prompt_width = text_width(prompt);
	cursor_width = text_width("_");
	
	bw = w = (text_input ? cursor_width : 0) 
	          + prompt_width + text_width(text);
	bh = h = (text_input || prompt[0]) ? ascent + descent : 0;
	
	for (o = valid; o && o->prev; o = o->prev);
	for (; o; o = o->next) {
		tw = text_width(o->text);
		if (tw > w) w = tw;
		h += ascent + descent;
	}

	if (h > max_height)
	{
		w = bw;
		h = bh;
		draw_options = 0;
	} else draw_options = 1;
	

	w += PADDING * 2;
	h += PADDING * 2;
	
	if (ow == w && oh == h) return;
	
	printf("changing size\n");
	if (buf) XFreePixmap(display, buf);
	buf = XCreatePixmap(display, win, w, h, 
	                    DefaultDepth(display, screen));
	printf("buf = %i\n", buf);
	printf("resize\n");
	XResizeWindow(display, win, w, h);
	printf("draw change\n");
	XftDrawChange(draw, buf);
}

void update_position() {
	Window ww;
	int c, v;

	/* if x,y not set then set to cursor position. */
	if (x == -1 && y == -1) 
		XQueryPointer(display, root, &ww, &ww,
		              &x, &y, &c, &c, &v);

	if (!absolute_position)
		keep_in_screen();

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
			x = info[i].x_org + info[i].width 
			    - w - BORDER_WIDTH - 1;
		if (x < info[i].x_org) x = info[i].x_org;
		if (y + h > info[i].y_org + info[i].height)
			y = info[i].y_org + info[i].height 
			    - h - BORDER_WIDTH - 1;
		if (y < info[i].y_org) y = info[i].y_org;
	}
}

void read_input() {
	FcChar8 line[512];
	int l;
	option *o, *head;
	o = head = calloc(sizeof(option), 1);

	while (fgets(line, sizeof(line), stdin)) {
		o->next = calloc(sizeof(option), 1);
		o->next->prev = o;
		o = o->next;

		l = strlen(line);
		o->text = calloc(sizeof(char), l);
		strncpy(o->text, line, l - 1);
		o->text[l - 1] = '\0';
	}

	options = head->next;
	options->prev = NULL;
	free(head);
	update_valid_options();
}

void setup() {
	XSetWindowAttributes attributes;
	XWindowAttributes window_attributes;
	Visual *vis;
	Colormap cmap;
	int ignore;
	
	display = XOpenDisplay(NULL);
	screen = DefaultScreen(display);
	vis = XDefaultVisual(display, screen);
	cmap = DefaultColormap(display, screen);

	if (XGetGeometry(display, RootWindow(display, screen), &root,
	        &ignore, &ignore,
	        &max_width, &max_height, &ignore, &ignore) == False)
	        die("Failed to get root Geometry!");

	if (!XftColorAllocName(display, vis, cmap, fg_name, &fg))
		die("Failed to allocate foreground color");
	if (!XftColorAllocName(display, vis, cmap, bg_name, &bg))
		die("Failed to allocate background color");

	/* Setup and map window */
	attributes.border_pixel = fg.pixel;
	attributes.background_pixel = bg.pixel;
	attributes.override_redirect = True;
	attributes.event_mask = 
	     ExposureMask|KeyPressMask|ButtonPressMask|ButtonReleaseMask;

	win = XCreateWindow(display, root,
	     0, 0, 1, 1, BORDER_WIDTH,
	     DefaultDepth(display, 0),
	     CopyFromParent, CopyFromParent,
	     CWBackPixel|CWOverrideRedirect|CWEventMask|CWBorderPixel,
	     &attributes);

	xim = XOpenIM(display, NULL, NULL, NULL);
	xic = XCreateIC(xim, XNInputStyle, 
	    XIMPreeditNothing | XIMStatusNothing,
	    XNClientWindow, win, XNFocusWindow, win, NULL);

	gc = XCreateGC(display, win, 0, 0);

	buf = XCreatePixmap(display, win, 1, 1, 
	                    DefaultDepth(display, screen));
	    
	draw = XftDrawCreate(display, buf, vis, cmap);

	load_font(font_str);
}

int main(int argc, char *argv[]) {
	XEvent ev;
	int i;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--p") == 0) {
			x = atoi(strsep(&argv[++i], ","));
			y = atoi(argv[i]);
		} else if (strcmp(argv[i], "--abs") == 0) {
			absolute_position = 1;
		} else if (strcmp(argv[i], "--fg") == 0) {
			strcpy(fg_name, argv[++i]);
		} else if (strcmp(argv[i], "--bg") == 0) {
			strcpy(bg_name, argv[++i]);
		} else if (strcmp(argv[i], "--fn") == 0) {
			strcpy(font_str, argv[++i]);
		} else if (argv[i][0] == '-') {
			switch (argv[i][1])
			{
			case 'h':
				usage();
				exit(EXIT_SUCCESS);
			case 'o': exit_on_one = 1; break;
			case 'f': first_on_exit = 1; break;
			case 't': text_input = 0; break;
			case 'q': print_on_exit = 0; break;
			case 'n': read_options = 0; break;
			case 'g': grab = 0; break;
			default:
				fprintf(stderr, "Unknown option: %s\n",
					argv[i]);
				exit(EXIT_FAILURE);
			}
		} else {
			strcpy(prompt, argv[i]);
		}
	}

	setup();

	if (read_options) read_input();

	update_position();
	XMapWindow(display, win);
	grab_keyboard_pointer();
	render();

	while (!XNextEvent(display, &ev)) {
		if (ev.type == KeyPress)
			handle_key(ev.xkey);
		else if (ev.type == ButtonRelease)
			handle_button(ev.xbutton);
		else if  (ev.type == Expose) {
			XRaiseWindow(display, win);
			render();
		}
	}

	clean_resources();
	exit(EXIT_FAILURE);
}