#include <cstdio>
#include <iostream>
#include <cstdlib>
#include <climits>
#include <cstring>
#include <vector>
#include <cctype>
#include <SDL.h>

#include "Vpctang_top.h"
#include "Vpctang_top_pctang_top.h"
#include "Vpctang_top_i8088.h"
#include "Vpctang_top_mcl86_eu_core.h"

#include "verilated.h"
#include <verilated_fst_c.h>

#define TRACE_ON

using namespace std;

// See: https://projectf.io/posts/verilog-sim-verilator-sdl/
const int H_RES = 640;
const int V_RES = 200;
int resolution_x = H_RES;
int resolution_y = V_RES;

typedef struct Pixel
{			   // for SDL texture
	uint8_t a; // transparency
	uint8_t b; // blue
	uint8_t g; // green
	uint8_t r; // red
} Pixel;

Pixel screenbuffer[H_RES * V_RES];

long long max_sim_time = 0LL;
bool double_size = false;

bool trace_toggle;				// -t or "t" key
bool trace_loading;				// -tl option
long long start_trace_time;		// -tt option
int start_trace_frame;			// -tf option
int trace_frame_length;			// -flen option
bool showFrameCount = true;

void usage()
{
	printf("Usage: sim [options] <rom_file>\n");
	printf("  -d     double windows size\n");
	printf("  -t     start tracing once sms is on (to waveform.fst)\n");
	printf("  -tt T  start tracing from time T\n");
	printf("  -tf F  start tracing from frame F\n");
	printf("  -flen N  trace for N frames\n");
	printf("  -tl    start tracing from game loading (i.e. before md is turned on)\n");
	printf("  -s T   stop simulation at time T\n");
	printf("  -f     print flash related memory accesses\n");
}

void help() {
	printf("ROM loaded. Use these keys in the simulation window for controls:\n");
	printf("SPC: Start/stop simulation.      ESC: Quit.     T: toggle tracing on/off\n");
	printf("Arrow keys: D-pad, A: A button, S: B button, D: C button, Q: X button, W: Y button, E: Z Select, Z: Start, X: Mode\n");
	// printf("V: dump VRAM.\n");
	// printf("I: show additional info like frame count.\n");
}

VerilatedFstC *m_trace;
Vpctang_top *top = new Vpctang_top;
Vpctang_top_pctang_top *pc = top->pctang_top;
uint64_t sim_time;
uint8_t clkcnt;
int hblank_r, ce_pix_r;
bool cpu_trace = false;
uint32_t pc_addr = 0;
uint32_t pc_addr0 = 0;

// split by spaces
vector<string> tokenize(string s);
long long parse_num(string s);
void trace_on();
void trace_off();

uint32_t cga2rgb(uint8_t cga);

void test_pattern() {
	for (int i = 0; i < V_RES; i++) {
		for (int j = 0; j < H_RES; j++) {
			uint32_t rgb = cga2rgb((i / 100) * 8 + (j / 80));
			Pixel *p = &screenbuffer[i*H_RES + j];
			p->a = 0xff;
			p->r = (rgb & 0xff0000) >> 16;
			p->g = (rgb & 0xff00) >> 8;
			p->b = rgb & 0xff;
		}
	}
}

#include "scancode.h"

map<uint32_t, string> bios_labels = {
	{0x0FE05B, "START     8088 processor test"},
	{0x0FE165, "          Base 16K read/write storage test"},
	{0x0FE245, "E6        Init and start of CRT controller (6845)"},
	{0x0FE2AA, "E10       Setup video data on screen for video line test."},
	// {0x0FE329, "C21       8259 interrupt controller test"},
	{0x0FE35D, "D7        8253 timer checkout"},
	{0x0FE3A2, "TST12     keyboard self test"},
	{0x0FE418, "EXP_IO    expansion I/O box test"},
	{0x0FE46A, "E19       additional read/write storage test"},
	{0x0FE518, "ROM_SCAN  CHECK FOR OPTIONAL ROM FROM C8000->F4000 IN 2K BLOCKS"},
	{0x0FE551, "F9        diskette attachment test"},
    {0x0FE56A, "F11       turn drive 0 motor on"},
    {0x0FE591, "F14       turn drive 0 motor off"},
	{0x0FE597, "F15       setup printer and rs232 base addresses if device attached"},
	{0x0FE5FC, "F15B      clear screen"},
	{0x0FE644, "F19       set up equip flag to indicate number of printers and rs232 cards"},
	{0x0FE65F, "F20       enable NMI interrupts and go to boot loader"},

	// INT13
	{0x0FEC59, "diskette_io INT 13h entry"},
	{0x0FEC85, "J1          floppy work"},
	{0x0FECB7, "disk_reset  reset floppy controller"},
	{0x0FED0B, "disk_read   diskette read"},
	{0x0FED14, "disk_verf   diskette verify"},
	{0x0FED18, "disk_format diskette format"},
	{0x0FED3E, "disk_write  diskette write"},

	// INT19 boot loader
	{0x0FE6F2, "boot_strap  boot loader"},
	{0x0FE704, "H1          load system from diskette"},
	{0x0FE71F, "H3          unable to IPL from the diskette, go to resident basic"},
	{0x0FE710, "H4          IPL was successful, jump to BOOT_LOCN"},

};

int main(int argc, char **argv, char **env)
{
	Verilated::commandArgs(argc, argv);
	bool frame_updated = false;
	uint64_t start_ticks = SDL_GetPerformanceCounter();
	int frame_count = 0;

	// if (argc == 1)
	// {
	// 	usage();
	// 	exit(1);
	// }

	// parse options
	bool loaded = false;
	for (int i = 1; i < argc; i++)
	{
		char *eptr;
		if (strcmp(argv[i], "-t") == 0)
		{
			trace_toggle = true;
			printf("Tracing ON\n");
			trace_on();
		}
		else if (strcmp(argv[i], "-s") == 0 && i + 1 < argc)
		{
			max_sim_time = strtoll(argv[++i], &eptr, 10);
			if (max_sim_time == 0)
				printf("Simulating forever.\n");
			else
				printf("Simulating %lld steps\n", max_sim_time);
		}
		else if (strcmp(argv[i], "-tt") == 0 && i + 1 < argc) {
			start_trace_time = strtoll(argv[++i], &eptr, 10);
			printf("Start tracing from %lld\n", start_trace_time);
		}
		else if (strcmp(argv[i], "-tf") == 0 && i + 1 < argc) {
			start_trace_frame = atoi(argv[++i]);
			printf("Start tracing from frame %d\n", start_trace_frame);
		}
		else if (strcmp(argv[i], "-flen") == 0 && i + 1 < argc) {
			trace_frame_length = atoi(argv[++i]);
			printf("Trace for %d frames\n", trace_frame_length);
		}
		else if (strcmp(argv[i], "-tl") == 0) {
			trace_loading = true;
			trace_on();
			trace_toggle = true;
			printf("Include loading in tracing\n");
		}
		else if (strcmp(argv[i], "-d") == 0) {
			double_size = true;
		}
		else if (strcmp(argv[i], "-cpu") == 0) {
			cpu_trace = true;
		}
		else if (strcmp(argv[i], "-pc") == 0) {
			// print matching pc address
			pc_addr = strtoul(argv[++i], &eptr, 16);
			printf("Printing pc address: %06x\n", pc_addr);
		}
		else if (argv[i][0] == '-') {
			printf("Unrecognized option: %s\n", argv[i]);
			usage();
			exit(1);
		}
		else
		{
			// load ROM
			// load_rom(argv[i]);
			loaded = true;

			if (!trace_loading)
				sim_time = 0;		// return sim_time to 0 when we are not tracing loading
		}
	}
	// if (!loaded)
	// {
	// 	usage();
	// 	exit(1);
	// }

	if (SDL_Init(SDL_INIT_VIDEO) < 0)
	{
		printf("SDL init failed.\n");
		return 1;
	}

	SDL_Window *sdl_window = NULL;
	SDL_Renderer *sdl_renderer = NULL;
	SDL_Texture *sdl_texture = NULL;

	sdl_window = SDL_CreateWindow("PCTang Sim", SDL_WINDOWPOS_CENTERED,
								  SDL_WINDOWPOS_CENTERED, 640 * (double_size ? 2 : 1), 480 * (double_size ? 2 : 1), SDL_WINDOW_SHOWN);
	if (!sdl_window)
	{
		printf("Window creation failed: %s\n", SDL_GetError());
		return 1;
	}
	sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
									  SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
	if (!sdl_renderer)
	{
		printf("Renderer creation failed: %s\n", SDL_GetError());
		return 1;
	}

	sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
									SDL_TEXTUREACCESS_TARGET, H_RES, V_RES);
	if (!sdl_texture)
	{
		printf("Texture creation failed: %s\n", SDL_GetError());
		return 1;
	}

	FILE *f = fopen("pcxt.aud", "w");
	long long samples = 0;
	bool sample_valid = false;

	FILE *f_cpu = NULL;
	if (cpu_trace) {
		f_cpu = fopen("cpu.log", "w");
	}

	bool sim_on = true; // max_sim_time > 0;
	bool done = false;
	uint64_t cnt = 0;

	SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES * sizeof(Pixel));
	SDL_RenderClear(sdl_renderer);
	SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
	SDL_RenderPresent(sdl_renderer);
	SDL_StopTextInput(); // for SDL_KEYDOWN

	help();

	test_pattern();

	int x = 0, y = 0;
	bool hblank_r = 0, vblank_r = 0;
	int clk_cga_cnt = 0;
	bool pixel_printed = false;
	const int sample_frame = 3;
	int hblank_width[512], video_width[512];
	memset(hblank_width, 0, sizeof(hblank_width));
	memset(video_width, 0, sizeof(video_width));
	vector<uint8_t> scancode;
	uint64_t last_scancode_time;

	uint32_t cpu_address0 = 0;
	uint16_t ax0, bx0, cx0, dx0;

	uint64_t last_pixel_time = sim_time, last_frame_time = sim_time;
	while (!done)
	{
		cnt++;

		if (sim_on && max_sim_time > 0 && sim_time >= max_sim_time) {
			printf("Simulation time is up: sim_time=%" PRIu64 "\n", sim_time);
			sim_on = false;
		}

		if (sim_on) {

			sim_time++;

			top->clk_g = !top->clk_g;
			// generate clk_cga @ 28.636Mhz vs clk_g @ 50Mhz
			// clk_cga_cnt += 28636;
			// if (clk_cga_cnt >= 50000) {
			// 	top->clk_cga = !top->clk_cga;
			// 	clk_cga_cnt -= 50000;
			// }

			top->eval();

			if (	trace_toggle ||
					start_trace_time != 0 && sim_time == start_trace_time ||
					start_trace_frame != 0 && frame_count == start_trace_frame) 
			{
				trace_toggle = true;
				trace_on();
				m_trace->dump(sim_time);
			}

			if (trace_frame_length > 0 && frame_count >= start_trace_frame +trace_frame_length) {
				trace_toggle = false;
			}

			if (pc->cpu_address != pc_addr0 && bios_labels.find(pc->cpu_address) != bios_labels.end()) {
				printf("BIOS address: %06x %s\n", pc->cpu_address, bios_labels[pc->cpu_address].c_str());
			}
			
			if (pc_addr != 0 && pc->cpu_address == pc_addr && pc->cpu_address != pc_addr0) {
				printf("PC address match: %06x\n", pc->cpu_address);
			}
			pc_addr0 = pc->cpu_address;



			// collect 8088 cpu trace
			if (f_cpu) {
				uint32_t cpu_address = pc->cpu_address;
				uint16_t ax = pc->u_cpu->EU_CORE->eu_register_ax;
				uint16_t bx = pc->u_cpu->EU_CORE->eu_register_bx;
				uint16_t cx = pc->u_cpu->EU_CORE->eu_register_cx;
				uint16_t dx = pc->u_cpu->EU_CORE->eu_register_dx;
				if (cpu_address != cpu_address0 || ax != ax0 || bx != bx0 || cx != cx0 || dx != dx0) {
					fprintf(f_cpu, "%lld %06x %04x %04x %04x\n", sim_time, cpu_address, ax, bx, cx, dx);
					cpu_address0 = cpu_address;
					ax0 = ax; bx0 = bx; cx0 = cx; dx0 = dx;
				}
			}

			// collect audio samples @ 48Khz
			// if (sim_time % (53693175 * 2 / 48000) == 0 && !pc->reset) {
			// 	uint16_t ar, al;
			// 	ar = pc->audio_r;
			// 	al = pc->audio_l;
			// 	if (al != 0 || ar != 0)
			// 		sample_valid = true;
			// 	fwrite(&al, sizeof(al), 1, f);
			// 	fwrite(&ar, sizeof(ar), 1, f);
			// 	samples++;
			// 	if (samples % 1000 == 0 && sample_valid)
			// 	{
			// 		printf("%lld sound samples\n", samples);
			// 		sample_valid = false;
			// 	}
			// }

			if (top->clk_g && pc->ce_cga) {
				if (pc->VBlank) {
					x = 0;
					y = 0;
					pixel_printed = false;
				} else if (pc->HBlank && !hblank_r) {
					x = 0;
					y++;
				} else if (!pc->HBlank && pc->ce_pixel_cga) {
					if (frame_count == sample_frame) {
						if (y < 512)
							video_width[y] = max(video_width[y], x);
						else
							printf("Video width overflow: y=%d, x=%d\n", y, x);
					}
					if (y < V_RES && x < H_RES) {
						Pixel *p = &screenbuffer[y * H_RES + x];
						bool draw = true /* frame_count > 2*/;
						if (draw) {
							p->a = 0xff;
							uint32_t rgb = cga2rgb(pc->color_cga);
							p->r = (rgb & 0xff0000) >> 16;
							p->g = (rgb & 0xff00) >> 8;
							p->b = rgb & 0xff;
						}
					}

					if (sim_time % 10000000 == 0) {
						uint64_t pix_time = sim_time - last_pixel_time;
						printf("Pixel clock: %fMhz\n", (double)(53593175 * 2) / pix_time / 1000000);
					}
					last_pixel_time = sim_time;
					x++;
				}
				hblank_r = pc->HBlank;
				vblank_r = pc->VBlank;
				ce_pix_r = pc->ce_pixel_cga;
			}

			// update texture once per frame (in blanking)
			if (pc->VBlank) {
				if (!frame_updated)
				{
					// if (frame_count == sample_frame) {
					// 	for (int i = 0; i < 512; i++) {
					// 		printf("[%3d]=%3d", i, video_width[i]);
					// 		if (i % 8 == 7)
					// 			printf("\n");
					// 		else
					// 			printf(" ");
					// 	}
					// }
					// check resolution
					resolution_x = 640; resolution_y = 480;

					frame_updated = true;
					SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES * sizeof(Pixel));
					SDL_RenderClear(sdl_renderer);
					const SDL_Rect srcRect = {0, 0, resolution_x, resolution_y};
					SDL_RenderCopy(sdl_renderer, sdl_texture, &srcRect, NULL);
					SDL_RenderPresent(sdl_renderer);
					frame_count++;

					if (frame_count == 220) {
						printf("Frame %d\n", frame_count);
					}

					if (frame_count % 5 == 0 || m_trace)
						printf("Frame #%d. Framerate %4.1f\n", frame_count, (double)5e7*2/(sim_time - last_frame_time));
					last_frame_time = sim_time;

					if (showFrameCount) {
						SDL_SetWindowTitle(sdl_window, ("PCTang Sim - frame " + to_string(frame_count) + 
											(trace_toggle ? " tracing" : "")).c_str());
					} else {
						SDL_SetWindowTitle(sdl_window, "PCTang Sim");
					}
				}
			}
			else
				frame_updated = false;
		}

		if (cnt % 100 == 0)
		{
			// check for SDL events
			SDL_Event e;
			if (SDL_PollEvent(&e))
			{
				// printf("Event type: %d, SDL_KEYDOWN=%d\n", e.type, SDL_KEYDOWN);
				switch (e.type) {
				
				case SDL_QUIT:
					done = true;
					break;
				case SDL_KEYDOWN:
					// printf("Key pressed: %d\n", e.key.keysym.sym);
					// press WIN-T to toggle trace
					if (e.key.keysym.mod & KMOD_LGUI) {
						if (e.key.keysym.sym == SDLK_t) {
							trace_toggle = !trace_toggle;
						}
					} else if (ps2scancodes.find(e.key.keysym.sym) != ps2scancodes.end()) {
						scancode.insert(scancode.end(), ps2scancodes[e.key.keysym.sym].first.begin(), ps2scancodes[e.key.keysym.sym].first.end());
					}
					break;
				case SDL_KEYUP:
					if (e.key.keysym.mod & KMOD_LGUI) {
						// nothing
					} else if (ps2scancodes.find(e.key.keysym.sym) != ps2scancodes.end()) {
						scancode.insert(scancode.end(), ps2scancodes[e.key.keysym.sym].second.begin(), ps2scancodes[e.key.keysym.sym].second.end());
					}
					break;
				case SDL_WINDOWEVENT:
					if (e.window.event == SDL_WINDOWEVENT_CLOSE) {
						 if (e.window.windowID == SDL_GetWindowID(sdl_window))
							done = true;
					}
					break;
				}
			}
		}
		
		// send scancode to ps2_device, one scancode takes about 1ms (we'll wait 2ms)
		if (sim_time - last_scancode_time > 2e5  && !scancode.empty()) {
			printf("Sending scancode %d\n", scancode.front());
			last_scancode_time = sim_time;
			top->kbd_data = scancode.front();
			top->kbd_req = !top->kbd_req;
			scancode.erase(scancode.begin());
		}
	}

	fclose(f);
	printf("Audio output to md.aud done.\n");
	if (f_cpu) {
		fclose(f_cpu);
		printf("CPU trace output to cpu.log done.\n");
	}

	if (m_trace)
		m_trace->close();
	delete top;

	// calculate frame rate
	uint64_t end_ticks = SDL_GetPerformanceCounter();
	double duration = ((double)(end_ticks - start_ticks)) / SDL_GetPerformanceFrequency();
	double fps = (double)frame_count / duration;
	printf("Frames per second: %.1f. Total frames=%d\n", fps, frame_count);

	SDL_DestroyTexture(sdl_texture);
	SDL_DestroyRenderer(sdl_renderer);
	SDL_DestroyWindow(sdl_window);
	SDL_Quit();

	return 0;
}

uint32_t cga2rgb(uint8_t cga) {
	switch (cga) {
	case 0: return 0x000000;
	case 1: return 0xcc0000;
	case 2: return 0x00cc00;
	case 3: return 0xcccc00;
	case 4: return 0x0000cc;
	case 5: return 0xcc00cc;
	case 6: return 0x00cccc;
	case 7: return 0xcccccc;
	case 8: return 0x555555;
	case 9: return 0xff5555;
	case 10: return 0x55ff55;
	case 11: return 0xffff55;
	case 12: return 0x5555ff;
	case 13: return 0xff55ff;
	case 14: return 0x55ffff;
	case 15: return 0xffffff;
	default: return 0x000000;
	}
}

bool is_space(char c)
{
	return c == ' ' || c == '\t';
}

vector<string> tokenize(string s)
{
	string w;
	vector<string> r;

	for (int i = 0; i < s.size(); i++)
	{
		char c = s[i];
		if (is_space(c) && w.size() > 0)
		{
			r.push_back(w);
			w = "";
		}
		if (!is_space(c))
			w += c;
	}
	if (w.size() > 0)
		r.push_back(w);
	return r;
}

// parse something like 100m or 10k
// return -1 if there's an error
long long parse_num(string s)
{
	long long times = 1;
	if (s.size() == 0)
		return -1;
	char last = tolower(s[s.size() - 1]);
	if (last >= 'a' && last <= 'z')
	{
		s = s.substr(0, s.size() - 1);
		if (last == 'k')
			times = 1000LL;
		else if (last == 'm')
			times = 1000000LL;
		else if (last == 'g')
			times = 1000000000LL;
		else
			return -1;
	}
	return atoll(s.c_str()) * times;
}

void trace_on()
{
	if (!m_trace)
	{
		m_trace = new VerilatedFstC;
		top->trace(m_trace, 5);
		Verilated::traceEverOn(true);
		m_trace->open("waveform.fst");
	}
}

void trace_off()
{
	if (m_trace)
	{
		top->trace(m_trace, 0);
	}
}

