
typedef struct option option;
struct option {
	FcChar8 *text;
	option *next, *prev;
};

void usage();
void die(FcChar8 *msg);
void finish();

int text_width(FcChar8 *str);
void draw_string(FcChar8 *str, int x, int y);

void render_options(int oy); 
void render(); 

void insert(FcChar8 *str, ssize_t n); 
size_t nextrune(int inc); 

void handle_button(XButtonEvent be); 
void handle_key(XKeyEvent ke); 

void update_valid_options(); 
void select_forward_match();

void make_cursor();
void load_font(FcChar8 *fontstr);
void grab_keyboard_pointer();
void update_size();
void set_position();

void read_input();
