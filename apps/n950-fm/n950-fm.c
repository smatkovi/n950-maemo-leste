/*
 * n950-fm -- FM radio for the Nokia N950 on Hildon (Maemo Leste).
 *
 * The Pro1X's FM radio (smatkovi/pro1x-maemo-leste, apps/pro1x-fm at
 * cd36dc6) for the N950's receiver: the FM part of its WL1273, through
 * /dev/radio0 (radio-wl1273, kernel/patches 0016-0019): frequency, seek,
 * mute, the signal and stereo, the RDS station name and radio text, saved
 * stations. The headphone cable is the antenna.
 *
 * What differs from the Pro1X:
 *  - radio-wl1273 keeps the chip in reset until VIDIOC_S_TUNER switches
 *    the receiver on; it stays on after close(), so the window switches
 *    it off (a volume of 0) when it closes.
 *  - RDS comes as raw blocks through read() (the driver has no RDS
 *    controls), from a second descriptor opened once RDS is on (the
 *    driver counts its RDS readers at open()); decoded here.
 *  - The signal is the chip's RSSI level as the driver passes it on, not
 *    V4L2's 0..65535.
 *  - The sound leaves the chip at its analog output into the TWL5031's
 *    AUX inputs; n950-fm-audio sets the mixer up and plays it (see
 *    sound() below).
 *
 *   Left/Right  0.1 MHz down/up      Up/Down  seek up/down
 *   m           mute
 *
 * All ioctls run in one thread of their own: tuning waits for the chip,
 * a seek takes seconds.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/videodev2.h>
#include <libintl.h>
#include <gtk/gtk.h>
#include <gdk/gdkkeysyms.h>
#include <hildon/hildon.h>

#define DOMAIN "n950-fm"
#define _(s) dgettext(DOMAIN, s)
#define DEVICE "/dev/radio0"
#define BAND_LOW 87500		/* kHz */
#define BAND_HIGH 108000
#define STEP 100
#define POLL_MS 1500
#define RDS_MS 200		/* RDS blocks read this often (the driver keeps 100) */
/*
 * Full scale of the signal bar: the WL1273's RSSI level, as radio-wl1273
 * passes it on (its level interrupt reports values above 14)
 */
#define RSSI_FULL 60

enum req { OPEN, TUNE, SEEK_UP, SEEK_DOWN, MUTE, UNMUTE, POLL, QUIT };

struct result {
	enum req req;
	int err;		/* errno of the request, 0 */
	unsigned freq;		/* kHz */
	unsigned signal;	/* 0..100 */
	int rssi;
	gboolean stereo, rds;
	char ps[32], rt[160];	/* UTF-8 */
};

static GAsyncQueue *requests;
static int fd = -1, rds_fd = -1;
static unsigned freq = BAND_LOW;
static gboolean muted, busy, opened;
static GtkWidget *window, *freq_label, *ps_label, *rt_label, *signal_bar,
		 *stereo_label, *status_label, *mute_button;
static GKeyFile *conf;
static char *conf_path;

/* ---- the radio thread ---- */

/* a request and its argument in one (never NULL) pointer */
static void push(enum req req, unsigned arg)
{
	g_async_queue_push(requests, GUINT_TO_POINTER((req + 1) | arg << 4));
}

static int set_mute(int on)
{
	struct v4l2_control c = { .id = V4L2_CID_AUDIO_MUTE, .value = on };

	return ioctl(fd, VIDIOC_S_CTRL, &c) ? errno : 0;
}

static int set_freq(unsigned khz)
{
	struct v4l2_frequency f = {
		.type = V4L2_TUNER_RADIO, .frequency = khz * 16,
	};

	return ioctl(fd, VIDIOC_S_FREQUENCY, &f) ? errno : 0;
}

static int seek(int up)
{
	struct v4l2_hw_freq_seek s = {
		.type = V4L2_TUNER_RADIO, .seek_upward = up, .wrap_around = 1,
	};

	return ioctl(fd, VIDIOC_S_HW_FREQ_SEEK, &s) ? errno : 0;
}

/* the receiver on: radio-wl1273 leaves reset here, with RDS */
static int power_on(void)
{
	struct v4l2_tuner t = {
		.index = 0, .audmode = V4L2_TUNER_MODE_STEREO,
		.rxsubchans = V4L2_TUNER_SUB_STEREO | V4L2_TUNER_SUB_RDS,
	};

	return ioctl(fd, VIDIOC_S_TUNER, &t) ? errno : 0;
}

/*
 * The receiver off: a volume of 0 puts radio-wl1273's chip back into
 * reset. The control only acts on a change, so 1 first.
 */
static void power_off(void)
{
	struct v4l2_control c = { .id = V4L2_CID_AUDIO_VOLUME, .value = 1 };

	ioctl(fd, VIDIOC_S_CTRL, &c);
	c.value = 0;
	ioctl(fd, VIDIOC_S_CTRL, &c);
}

/* ---- RDS: the station name (groups 0A/0B) and radio text (2A/2B) ---- */

static struct {
	guint16 blk[4];
	unsigned have;		/* blocks A..D of the current group */
	char ps[8], rt[64];	/* RDS characters */
	int ab;			/* the radio text's A/B flag */
} rds;

static void rds_reset(void)
{
	memset(&rds, 0, sizeof(rds));
	memset(rds.ps, ' ', sizeof(rds.ps));
	memset(rds.rt, ' ', sizeof(rds.rt));
	rds.ab = -1;
}

static void rds_group(void)
{
	guint16 b = rds.blk[1], c = rds.blk[2], d = rds.blk[3];
	unsigned type = b >> 12, version_b = b >> 11 & 1;

	if (type == 0) {
		unsigned i = (b & 3) * 2;

		rds.ps[i] = d >> 8;
		rds.ps[i + 1] = d & 0xff;
	} else if (type == 2) {
		unsigned seg = b & 15, ab = b >> 4 & 1;

		if ((int)ab != rds.ab) {
			memset(rds.rt, ' ', sizeof(rds.rt));
			rds.ab = ab;
		}
		if (!version_b) {
			char *t = rds.rt + seg * 4;

			t[0] = c >> 8, t[1] = c & 0xff, t[2] = d >> 8, t[3] = d & 0xff;
		} else {
			char *t = rds.rt + seg * 2;

			t[0] = d >> 8, t[1] = d & 0xff;
		}
	}
}

/* one block as V4L2 hands it on: blocks A, B, C (or C'), D in turn */
static void rds_block(const struct v4l2_rds_data *d)
{
	unsigned id = d->block & V4L2_RDS_BLOCK_MSK;

	if (d->block & V4L2_RDS_BLOCK_ERROR || id > V4L2_RDS_BLOCK_C_ALT) {
		rds.have = 0;
		return;
	}
	if (id == V4L2_RDS_BLOCK_C_ALT)
		id = V4L2_RDS_BLOCK_C;
	if (id == V4L2_RDS_BLOCK_A)
		rds.have = 0;
	else if (!(rds.have & 1u << (id - 1))) {
		rds.have = 0;
		return;
	}
	rds.blk[id] = d->msb << 8 | d->lsb;
	rds.have |= 1u << id;
	if (id == V4L2_RDS_BLOCK_D && rds.have == 0xf)
		rds_group();
}

static void rds_read(void)
{
	struct v4l2_rds_data d[32];
	ssize_t n;

	if (rds_fd < 0)
		return;
	while ((n = read(rds_fd, d, sizeof(d))) > 0) {
		for (ssize_t i = 0; i < n / (ssize_t)sizeof(d[0]); i++)
			rds_block(&d[i]);
		if (n < (ssize_t)sizeof(d))
			break;
	}
}

/*
 * RDS characters as UTF-8: ASCII, and the letters of the EBU Latin table
 * (IEC 62106 annex E) in its columns 8, 9, C and D; 0x0d ends a text
 */
static const char *const ebu_8_9[32] = {
	"á", "à", "é", "è", "í", "ì", "ó", "ò", "ú", "ù", "Ñ", "Ç", "Ş", "ß", "¡", "Ĳ",
	"â", "ä", "ê", "ë", "î", "ï", "ô", "ö", "û", "ü", "ñ", "ç", "ş", "ğ", "ı", "ĳ",
};
static const char *const ebu_c_d[32] = {
	"Á", "À", "É", "È", "Í", "Ì", "Ó", "Ò", "Ú", "Ù", "Ř", "Č", "Š", "Ž", "Đ", "Ŀ",
	"Â", "Ä", "Ê", "Ë", "Î", "Ï", "Ô", "Ö", "Û", "Ü", "ř", "č", "š", "ž", "đ", "ŀ",
};

static void rds_text(const char *in, int n, char *out, size_t size)
{
	GString *s = g_string_new(NULL);

	for (int i = 0; i < n; i++) {
		unsigned char ch = in[i];

		if (ch == 0x0d)
			break;
		if (ch >= 0x20 && ch < 0x7f)
			g_string_append_c(s, ch);
		else if (ch >= 0x80 && ch < 0xa0)
			g_string_append(s, ebu_8_9[ch - 0x80]);
		else if (ch >= 0xc0 && ch < 0xe0)
			g_string_append(s, ebu_c_d[ch - 0xc0]);
		else if (ch)
			g_string_append_c(s, '?');
	}
	g_strlcpy(out, s->str, size);
	g_string_free(s, TRUE);
}

static void status(struct result *r)
{
	struct v4l2_frequency f = { .type = V4L2_TUNER_RADIO };
	struct v4l2_tuner t = { .index = 0 };

	if (!ioctl(fd, VIDIOC_G_FREQUENCY, &f))
		r->freq = f.frequency / 16;
	if (!ioctl(fd, VIDIOC_G_TUNER, &t)) {
		r->rssi = t.signal;
		r->signal = CLAMP(t.signal, 0, RSSI_FULL) * 100 / RSSI_FULL;
		r->stereo = !!(t.rxsubchans & V4L2_TUNER_SUB_STEREO);
		r->rds = !!(t.rxsubchans & V4L2_TUNER_SUB_RDS);
	} else if (!r->err) {
		r->err = errno;
	}
	rds_text(rds.ps, sizeof(rds.ps), r->ps, sizeof(r->ps));
	rds_text(rds.rt, sizeof(rds.rt), r->rt, sizeof(r->rt));
}

static gboolean result_cb(gpointer data);

static gpointer radio_thread(gpointer data)
{
	(void)data;
	rds_reset();
	for (;;) {
		gpointer p = g_async_queue_timeout_pop(requests, RDS_MS * 1000);
		guint v = GPOINTER_TO_UINT(p);
		struct result *r;

		/* between requests: the RDS blocks that came in */
		rds_read();
		if (!p)
			continue;
		r = g_new0(struct result, 1);
		r->req = (v & 0xf) - 1;
		switch (r->req) {
		case OPEN:
			fd = open(DEVICE, O_RDWR);
			if (fd < 0) {
				r->err = errno;
				break;
			}
			r->err = power_on();
			if (!r->err)
				r->err = set_freq(v >> 4);
			/* RDS is on now: the driver counts this one as a reader */
			if (!r->err)
				rds_fd = open(DEVICE, O_RDONLY | O_NONBLOCK);
			break;
		case TUNE:
			r->err = set_freq(v >> 4);
			rds_reset();
			break;
		case SEEK_UP:
		case SEEK_DOWN:
			r->err = seek(r->req == SEEK_UP);
			rds_reset();
			break;
		case MUTE:
		case UNMUTE:
			r->err = set_mute(r->req == MUTE);
			break;
		case POLL:
			break;
		case QUIT:
			if (rds_fd >= 0)
				close(rds_fd);
			if (fd >= 0) {
				power_off();
				close(fd);
			}
			g_free(r);
			return NULL;
		}
		if (fd >= 0)
			status(r);
		g_idle_add(result_cb, r);
	}
}

/* ---- sound: the TWL5031's AUX inputs played back ---- */

/*
 * The receiver's analog output goes to the TWL5031's AUXL and AUXR (the
 * sound card's "FM Radio", Nokia's audio configuration 4 for the RM-680).
 * n950-fm-audio switches those on as the TWL5031's capture and plays it
 * on PulseAudio's default sink through a loopback, as Harmattan's audio
 * policy did; "off" puts the mixer back. /etc/default/n950-fm chooses
 * that or a path inside the codecs without PulseAudio.
 */
#define AUDIO_HELPER "n950-fm-audio"

static gboolean sound_is_on;

/* runs a command; its first line of output as a number, or -1 */
static int run(const char *cmd)
{
	char *out = NULL;
	int n = -1, status;

	if (g_spawn_command_line_sync(cmd, &out, NULL, &status, NULL) &&
	    g_spawn_check_wait_status(status, NULL))
		n = out && g_ascii_isdigit(*out) ? atoi(out) : 0;
	g_free(out);
	return n;
}

static void sound(gboolean on)
{
	if (on == sound_is_on)
		return;
	if (!on) {
		run(AUDIO_HELPER " off");
		sound_is_on = FALSE;
		return;
	}
	sound_is_on = run(AUDIO_HELPER " on") >= 0;
	if (!sound_is_on)
		gtk_label_set_text(GTK_LABEL(status_label),
				   _("The FM sound does not start (run n950-fm-audio on in a terminal)."));
}

/* ---- settings: the last frequency, saved stations ---- */

static void save_conf(void)
{
	char *dir = g_path_get_dirname(conf_path);

	g_mkdir_with_parents(dir, 0700);
	g_key_file_set_integer(conf, "radio", "frequency", freq);
	g_key_file_save_to_file(conf, conf_path, NULL);
	g_free(dir);
}

/* ---- the window ---- */

static void show_freq(unsigned khz)
{
	char *s = g_strdup_printf("%u.%u MHz", khz / 1000, khz % 1000 / 100);

	gtk_label_set_text(GTK_LABEL(freq_label), s);
	g_free(s);
}

static const char *strerr(int err)
{
	switch (err) {
	case ENOENT:
	case ENODEV:
		return _("No FM receiver (kernel without radio-wl1273?)");
	case ETIMEDOUT:
	case EIO:
	case EREMOTEIO:
		return _("The receiver does not answer.");
	case ENODATA:
		return _("No station found.");
	case EBUSY:
		return _("The receiver is busy.");
	default:
		return g_strerror(err);
	}
}

static gboolean result_cb(gpointer data)
{
	struct result *r = data;

	if (r->req == OPEN && !r->err) {
		opened = TRUE;
		push(muted ? MUTE : UNMUTE, 0);
		sound(!muted);
	}
	if (r->req != POLL)
		busy = FALSE;
	if (r->err)
		gtk_label_set_text(GTK_LABEL(status_label), strerr(r->err));
	else if (r->req != POLL)
		gtk_label_set_text(GTK_LABEL(status_label), "");

	if (opened) {
		if (r->freq >= BAND_LOW && r->freq <= BAND_HIGH && r->freq != freq) {
			freq = r->freq;
			save_conf();
		}
		show_freq(freq);
		gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(signal_bar), r->signal / 100.0);
		{
			char *t = g_strdup_printf(_("Signal %d"), r->rssi);

			gtk_progress_bar_set_text(GTK_PROGRESS_BAR(signal_bar), t);
			g_free(t);
		}
		gtk_label_set_text(GTK_LABEL(stereo_label),
				   r->rds ? (r->stereo ? _("Stereo  RDS") : _("Mono  RDS"))
					  : (r->stereo ? _("Stereo") : _("Mono")));
		gtk_label_set_text(GTK_LABEL(ps_label), g_strstrip(r->ps));
		gtk_label_set_text(GTK_LABEL(rt_label), g_strstrip(r->rt));
	}
	g_free(r);
	return FALSE;
}

static gboolean poll_cb(gpointer data)
{
	(void)data;
	if (opened && !busy && g_async_queue_length(requests) == 0)
		push(POLL, 0);
	return TRUE;
}

static void request(enum req req, unsigned arg)
{
	if (!opened || busy)
		return;
	busy = TRUE;
	if (req == SEEK_UP || req == SEEK_DOWN)
		gtk_label_set_text(GTK_LABEL(status_label), _("Searching..."));
	push(req, arg);
}

static void step(int dir)
{
	unsigned f = freq + dir * STEP;

	if (f < BAND_LOW)
		f = BAND_HIGH;
	else if (f > BAND_HIGH)
		f = BAND_LOW;
	freq = f;
	show_freq(f);
	request(TUNE, f);
}

static void down_cb(GtkWidget *w, gpointer data) { (void)w, (void)data; step(-1); }
static void up_cb(GtkWidget *w, gpointer data) { (void)w, (void)data; step(1); }
static void seek_down_cb(GtkWidget *w, gpointer data) { (void)w, (void)data; request(SEEK_DOWN, 0); }
static void seek_up_cb(GtkWidget *w, gpointer data) { (void)w, (void)data; request(SEEK_UP, 0); }

static void mute_cb(GtkToggleButton *b, gpointer data)
{
	(void)data;
	muted = gtk_toggle_button_get_active(b);
	if (opened) {
		push(muted ? MUTE : UNMUTE, 0);
		sound(!muted);
	}
}

static gboolean key_cb(GtkWidget *w, GdkEventKey *e, gpointer data)
{
	(void)w, (void)data;
	switch (e->keyval) {
	case GDK_Left:
		step(-1);
		return TRUE;
	case GDK_Right:
		step(1);
		return TRUE;
	case GDK_Up:
		request(SEEK_UP, 0);
		return TRUE;
	case GDK_Down:
		request(SEEK_DOWN, 0);
		return TRUE;
	case GDK_m:
		gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(mute_button), !muted);
		return TRUE;
	}
	return FALSE;
}

/* saved stations: [stations] <kHz>=<name> */
static void save_station_cb(GtkButton *b, gpointer data)
{
	const char *ps = gtk_label_get_text(GTK_LABEL(ps_label));
	char key[16];

	(void)b, (void)data;
	g_snprintf(key, sizeof(key), "%u", freq);
	g_key_file_set_string(conf, "stations", key, *ps ? ps : "");
	save_conf();
	hildon_banner_show_information(window, NULL, _("Station saved"));
}

static void stations_cb(GtkButton *b, gpointer data)
{
	GtkWidget *dialog, *sel;
	char **keys;
	gsize n, i;

	(void)b, (void)data;
	keys = g_key_file_get_keys(conf, "stations", &n, NULL);
	if (!n) {
		hildon_banner_show_information(window, NULL, _("No saved stations"));
		g_strfreev(keys);
		return;
	}
	sel = hildon_touch_selector_new_text();
	for (i = 0; i < n; i++) {
		unsigned khz = strtoul(keys[i], NULL, 10);
		char *name = g_key_file_get_string(conf, "stations", keys[i], NULL);
		char *row = g_strdup_printf("%u.%u MHz  %s", khz / 1000, khz % 1000 / 100,
					    name ? name : "");

		hildon_touch_selector_append_text(HILDON_TOUCH_SELECTOR(sel), row);
		g_free(row);
		g_free(name);
	}
	dialog = hildon_picker_dialog_new(GTK_WINDOW(window));
	gtk_window_set_title(GTK_WINDOW(dialog), _("Stations"));
	hildon_picker_dialog_set_selector(HILDON_PICKER_DIALOG(dialog),
					  HILDON_TOUCH_SELECTOR(sel));
	if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_OK) {
		int row = hildon_touch_selector_get_active(HILDON_TOUCH_SELECTOR(sel), 0);

		if (row >= 0 && (gsize)row < n) {
			freq = strtoul(keys[row], NULL, 10);
			show_freq(freq);
			request(TUNE, freq);
		}
	}
	gtk_widget_destroy(dialog);
	g_strfreev(keys);
}

static void forget_station_cb(GtkButton *b, gpointer data)
{
	char key[16];

	(void)b, (void)data;
	g_snprintf(key, sizeof(key), "%u", freq);
	if (g_key_file_remove_key(conf, "stations", key, NULL)) {
		save_conf();
		hildon_banner_show_information(window, NULL, _("Station removed"));
	}
}

static GtkWidget *button(const char *label, GCallback cb)
{
	GtkWidget *b = hildon_gtk_button_new(HILDON_SIZE_FINGER_HEIGHT);

	gtk_button_set_label(GTK_BUTTON(b), label);
	g_signal_connect(b, "clicked", cb, NULL);
	return b;
}

static GtkWidget *label(const char *font, gboolean wrap)
{
	GtkWidget *l = gtk_label_new(NULL);

	hildon_helper_set_logical_font(l, font);
	gtk_label_set_line_wrap(GTK_LABEL(l), wrap);
	gtk_label_set_justify(GTK_LABEL(l), GTK_JUSTIFY_CENTER);
	return l;
}

static void build(void)
{
	HildonAppMenu *menu = HILDON_APP_MENU(hildon_app_menu_new());
	GtkWidget *box, *row, *b;
	PangoFontDescription *big;

	window = hildon_stackable_window_new();
	gtk_window_set_title(GTK_WINDOW(window), _("FM Radio"));
	g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);
	g_signal_connect(window, "key-press-event", G_CALLBACK(key_cb), NULL);

	freq_label = gtk_label_new(NULL);
	big = pango_font_description_from_string("Sans Bold 40");
	gtk_widget_modify_font(freq_label, big);
	pango_font_description_free(big);
	ps_label = label("LargeSystemFont", FALSE);
	rt_label = label("SystemFont", TRUE);
	stereo_label = label("SmallSystemFont", FALSE);
	status_label = label("SmallSystemFont", TRUE);
	hildon_helper_set_logical_color(status_label, GTK_RC_FG, GTK_STATE_NORMAL,
					"SecondaryTextColor");
	signal_bar = gtk_progress_bar_new();

	row = gtk_hbox_new(TRUE, HILDON_MARGIN_DEFAULT);
	gtk_box_pack_start(GTK_BOX(row), button(_("Seek down"), G_CALLBACK(seek_down_cb)), TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(row), button("-0.1", G_CALLBACK(down_cb)), TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(row), button("+0.1", G_CALLBACK(up_cb)), TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(row), button(_("Seek up"), G_CALLBACK(seek_up_cb)), TRUE, TRUE, 0);
	mute_button = hildon_gtk_toggle_button_new(HILDON_SIZE_FINGER_HEIGHT);
	gtk_button_set_label(GTK_BUTTON(mute_button), _("Mute"));
	g_signal_connect(mute_button, "toggled", G_CALLBACK(mute_cb), NULL);
	gtk_box_pack_start(GTK_BOX(row), mute_button, TRUE, TRUE, 0);

	box = gtk_vbox_new(FALSE, HILDON_MARGIN_DEFAULT);
	gtk_container_set_border_width(GTK_CONTAINER(box), HILDON_MARGIN_DOUBLE);
	gtk_box_pack_start(GTK_BOX(box), freq_label, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(box), ps_label, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), rt_label, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), signal_bar, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), stereo_label, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), row, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), status_label, FALSE, FALSE, 0);
	gtk_container_add(GTK_CONTAINER(window), box);

	b = hildon_gtk_button_new(HILDON_SIZE_AUTO);
	gtk_button_set_label(GTK_BUTTON(b), _("Stations"));
	g_signal_connect(b, "clicked", G_CALLBACK(stations_cb), NULL);
	hildon_app_menu_append(menu, GTK_BUTTON(b));
	b = hildon_gtk_button_new(HILDON_SIZE_AUTO);
	gtk_button_set_label(GTK_BUTTON(b), _("Save station"));
	g_signal_connect(b, "clicked", G_CALLBACK(save_station_cb), NULL);
	hildon_app_menu_append(menu, GTK_BUTTON(b));
	b = hildon_gtk_button_new(HILDON_SIZE_AUTO);
	gtk_button_set_label(GTK_BUTTON(b), _("Remove station"));
	g_signal_connect(b, "clicked", G_CALLBACK(forget_station_cb), NULL);
	hildon_app_menu_append(menu, GTK_BUTTON(b));
	gtk_widget_show_all(GTK_WIDGET(menu));
	hildon_window_set_app_menu(HILDON_WINDOW(window), menu);

	show_freq(freq);
	gtk_label_set_text(GTK_LABEL(status_label),
			   _("Switching the receiver on (the headphone cable is the antenna)..."));
	gtk_widget_show_all(window);
}

int main(int argc, char **argv)
{
	GThread *thread;
	int f;

	bindtextdomain(DOMAIN, LOCALEDIR);
	bind_textdomain_codeset(DOMAIN, "UTF-8");
	hildon_gtk_init(&argc, &argv);

	conf = g_key_file_new();
	conf_path = g_build_filename(g_get_user_config_dir(), DOMAIN, "settings", NULL);
	g_key_file_load_from_file(conf, conf_path, G_KEY_FILE_KEEP_COMMENTS, NULL);
	f = g_key_file_get_integer(conf, "radio", "frequency", NULL);
	if (f >= BAND_LOW && f <= BAND_HIGH)
		freq = f;

	build();
	requests = g_async_queue_new();
	thread = g_thread_new("radio", radio_thread, NULL);
	push(OPEN, freq);
	g_timeout_add(POLL_MS, poll_cb, NULL);

	gtk_main();

	sound(FALSE);
	push(QUIT, 0);
	g_thread_join(thread);
	return 0;
}
