
typedef struct option option;
struct option {
	char *text;
	option *next, *prev;
};

void usage();
void die(char *msg);
void finish();

int text_width(char *str);
void draw_string(char *str, int x, int y);

void render_options(int oy); 
void render(); 

void insert(char *str, ssize_t n); 
size_t nextrune(int inc); 

void handle_button(XButtonEvent be); 
void handle_key(XKeyEvent ke); 

void update_valid_options(); 
void select_forward_match();

void make_cursor();
void load_font();
void grab_keyboard_pointer();
void update_size();
void set_position();

void read_input();
