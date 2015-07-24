
typedef struct option option;
struct option {
	FcChar8 *text;
	option *next, *prev;
};

static void usage();
static void die(char *msg);

static void clean_resources();

static void finish();

static int text_width(FcChar8 *str);
static void draw_string(FcChar8 *str, int x, int y);

static void render_options(int oy); 
static void render(); 

static void insert(FcChar8 *str, ssize_t n); 
static size_t nextrune(int inc); 

static void copy_first();

static void handle_button(XButtonEvent be); 
static void handle_key(XKeyEvent ke); 

static void update_valid_options(); 

static void make_cursor();
static void load_font(FcChar8 *fontstr);
static void grab_keyboard_pointer();

static void update_size();
static void set_position();
static void keep_in_screen();

static void read_input();

static void setup();
