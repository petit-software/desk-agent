#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hardware/pio.h"
#include "pico/stdlib.h"
#include "pico/unique_id.h"
#include "ws2812.pio.h"

#define MATRIX_PIN 16
#define MATRIX_PIXELS 25
#define BRIGHTNESS_LIMIT 64
#define DEFAULT_BRIGHTNESS 16
#define COMMAND_CAPACITY 128
#define HEARTBEAT_TIMEOUT_MS 8000

typedef enum {
    STATE_BOOTING,
    STATE_DISCONNECTED,
    STATE_IDLE,
    STATE_WORKING,
    STATE_NEEDS_INPUT,
    STATE_FINISHED,
    STATE_ERROR,
} display_state_t;

typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} rgb_t;

static const char *booting_frames[] = {
    "WWWWW00000000000000000000",
    "WWWWWWWWWW000000000000000",
    "WWWWWWWWWWWWWWW0000000000",
    "WWWWWWWWWWWWWWWWWWWW00000",
    "WWWWWWWWWWWWWWWWWWWWWWWWW",
    "00000WWWWWWWWWWWWWWWWWWWW",
    "0000000000WWWWWWWWWWWWWWW",
    "000000000000000WWWWWWWWWW",
    "00000000000000000000WWWWW",
    "0000000000000000000000000",
};

static const char *disconnected_frames[] = {
    "000000000000d000000000000",
};

static const char *idle_frames[] = {
    "000000000000C000000000000",
    "0000000C000C0C000C0000000",
    "000000000000C000000000000",
};

static const char *working_frames[] = {
    "00C00C0C0C0CBC00C0C0C000C",
    "C00C00CC0000BCC0CC00C00C0",
    "C000C0C0C00CBC0C0C0C00C00",
    "0C00C00CC0CCB0000CC00C00C",
};

static const char *needs_input_frames[] = {
    "00A0000A0000A000000000A00",
    "00A0000A0000A000000000000",
};

static const char *finished_frames[] = {
    "000000000GG00G00GG0000000",
};

static const char *error_frames[] = {
    "R000R0R0R000R000R0R0R000R",
    "R000R0000000R0000000R000R",
};

static PIO matrix_pio = pio0;
static uint matrix_state_machine;
static display_state_t display_state = STATE_BOOTING;
static display_state_t state_before_identify = STATE_IDLE;
static uint8_t brightness = DEFAULT_BRIGHTNESS;
static uint32_t state_started_ms;
static uint32_t state_deadline_ms;
static uint32_t last_heartbeat_ms;
static uint32_t identify_deadline_ms;
static bool host_seen;

static rgb_t palette(char code) {
    switch (code) {
        case 'd': return (rgb_t){24, 24, 24};
        case 'W': return (rgb_t){255, 255, 255};
        case 'B': return (rgb_t){0, 120, 255};
        case 'C': return (rgb_t){0, 220, 255};
        case 'A': return (rgb_t){255, 120, 0};
        case 'G': return (rgb_t){0, 255, 80};
        case 'R': return (rgb_t){255, 0, 0};
        default: return (rgb_t){0, 0, 0};
    }
}

static uint32_t rgb_value(rgb_t color) {
    const uint8_t red = (uint8_t)((uint16_t)color.red * brightness / 255);
    const uint8_t green = (uint8_t)((uint16_t)color.green * brightness / 255);
    const uint8_t blue = (uint8_t)((uint16_t)color.blue * brightness / 255);
    return ((uint32_t)red << 24) | ((uint32_t)green << 16) | ((uint32_t)blue << 8);
}

static void render_pattern(const char *pattern) {
    for (int physical_index = 0; physical_index < MATRIX_PIXELS; ++physical_index) {
        const int logical_index = MATRIX_PIXELS - 1 - physical_index;
        pio_sm_put_blocking(matrix_pio, matrix_state_machine, rgb_value(palette(pattern[logical_index])));
    }
}

static void animation_for_state(
    display_state_t state,
    const char ***frames,
    size_t *frame_count,
    uint32_t *duration_ms
) {
    switch (state) {
        case STATE_BOOTING:
            *frames = booting_frames;
            *frame_count = sizeof(booting_frames) / sizeof(booting_frames[0]);
            *duration_ms = 150;
            break;
        case STATE_DISCONNECTED:
            *frames = disconnected_frames;
            *frame_count = 1;
            *duration_ms = 1000;
            break;
        case STATE_IDLE:
            *frames = idle_frames;
            *frame_count = sizeof(idle_frames) / sizeof(idle_frames[0]);
            *duration_ms = 600;
            break;
        case STATE_WORKING:
            *frames = working_frames;
            *frame_count = sizeof(working_frames) / sizeof(working_frames[0]);
            *duration_ms = 180;
            break;
        case STATE_NEEDS_INPUT:
            *frames = needs_input_frames;
            *frame_count = sizeof(needs_input_frames) / sizeof(needs_input_frames[0]);
            *duration_ms = 360;
            break;
        case STATE_FINISHED:
            *frames = finished_frames;
            *frame_count = 1;
            *duration_ms = 900;
            break;
        case STATE_ERROR:
            *frames = error_frames;
            *frame_count = sizeof(error_frames) / sizeof(error_frames[0]);
            *duration_ms = 250;
            break;
    }
}

static void render_current_state(uint32_t now_ms) {
    const char **frames;
    size_t frame_count;
    uint32_t duration_ms;
    animation_for_state(display_state, &frames, &frame_count, &duration_ms);
    const size_t frame_index = ((now_ms - state_started_ms) / duration_ms) % frame_count;
    render_pattern(frames[frame_index]);
}

static bool parse_state(const char *value, display_state_t *state) {
    if (strcmp(value, "BOOTING") == 0) *state = STATE_BOOTING;
    else if (strcmp(value, "DISCONNECTED") == 0) *state = STATE_DISCONNECTED;
    else if (strcmp(value, "IDLE") == 0) *state = STATE_IDLE;
    else if (strcmp(value, "WORKING") == 0) *state = STATE_WORKING;
    else if (strcmp(value, "NEEDS_INPUT") == 0) *state = STATE_NEEDS_INPUT;
    else if (strcmp(value, "FINISHED") == 0) *state = STATE_FINISHED;
    else if (strcmp(value, "ERROR") == 0) *state = STATE_ERROR;
    else return false;
    return true;
}

static void acknowledge(unsigned long sequence) {
    printf("AM1 ACK %lu\n", sequence);
    stdio_flush();
}

static void process_command(char *line, uint32_t now_ms) {
    if (strcmp(line, "AM1 HELLO") == 0) {
        pico_unique_board_id_t board_id;
        pico_get_unique_board_id(&board_id);
        printf("AM1 READY 0.1.3 waveshare-rp2040-matrix-");
        for (size_t index = 0; index < PICO_UNIQUE_BOARD_ID_SIZE_BYTES; ++index) {
            printf("%02x", board_id.id[index]);
        }
        printf("\n");
        stdio_flush();
        host_seen = true;
        last_heartbeat_ms = now_ms;
        return;
    }

    unsigned long sequence = 0;
    unsigned long value = 0;
    char state_value[24];
    if (sscanf(line, "AM1 STATE %lu %23s %lu", &sequence, state_value, &value) == 3) {
        display_state_t requested_state;
        if (!parse_state(state_value, &requested_state)) {
            printf("AM1 ERR %lu BAD_STATE\n", sequence);
            stdio_flush();
            return;
        }
        display_state = requested_state;
        state_started_ms = now_ms;
        state_deadline_ms = now_ms + (uint32_t)value;
        identify_deadline_ms = 0;
        host_seen = true;
        last_heartbeat_ms = now_ms;
        acknowledge(sequence);
        return;
    }

    if (sscanf(line, "AM1 PING %lu", &sequence) == 1) {
        host_seen = true;
        last_heartbeat_ms = now_ms;
        acknowledge(sequence);
        return;
    }

    if (sscanf(line, "AM1 BRIGHTNESS %lu %lu", &sequence, &value) == 2) {
        brightness = value > BRIGHTNESS_LIMIT ? BRIGHTNESS_LIMIT : (uint8_t)value;
        host_seen = true;
        last_heartbeat_ms = now_ms;
        acknowledge(sequence);
        return;
    }

    if (sscanf(line, "AM1 IDENTIFY %lu", &sequence) == 1) {
        state_before_identify = display_state;
        display_state = STATE_BOOTING;
        state_started_ms = now_ms;
        identify_deadline_ms = now_ms + 1500;
        host_seen = true;
        last_heartbeat_ms = now_ms;
        acknowledge(sequence);
        return;
    }

    if (sscanf(line, "AM1 RESET_STATE %lu", &sequence) == 1) {
        display_state = STATE_IDLE;
        state_started_ms = now_ms;
        state_deadline_ms = 0;
        identify_deadline_ms = 0;
        host_seen = true;
        last_heartbeat_ms = now_ms;
        acknowledge(sequence);
        return;
    }

    printf("AM1 ERR %lu BAD_COMMAND\n", sequence);
    stdio_flush();
}

static void read_commands(uint32_t now_ms) {
    static char command[COMMAND_CAPACITY];
    static size_t length;
    int character;
    while ((character = getchar_timeout_us(0)) != PICO_ERROR_TIMEOUT) {
        if (character == '\n' || character == '\r') {
            if (length > 0) {
                command[length] = '\0';
                process_command(command, now_ms);
                length = 0;
            }
        } else if (length < COMMAND_CAPACITY - 1) {
            command[length++] = (char)character;
        } else {
            length = 0;
        }
    }
}

int main(void) {
    stdio_init_all();
    const uint offset = pio_add_program(matrix_pio, &ws2812_program);
    matrix_state_machine = pio_claim_unused_sm(matrix_pio, true);
    ws2812_program_init(matrix_pio, matrix_state_machine, offset, MATRIX_PIN, 800000.0f);

    state_started_ms = to_ms_since_boot(get_absolute_time());
    uint32_t last_render_ms = 0;
    while (true) {
        const uint32_t now_ms = to_ms_since_boot(get_absolute_time());
        read_commands(now_ms);

        if (identify_deadline_ms != 0 && (int32_t)(now_ms - identify_deadline_ms) >= 0) {
            display_state = state_before_identify;
            state_started_ms = now_ms;
            identify_deadline_ms = 0;
        } else if (host_seen && (int32_t)(now_ms - last_heartbeat_ms) >= HEARTBEAT_TIMEOUT_MS) {
            display_state = STATE_DISCONNECTED;
            state_started_ms = now_ms;
            state_deadline_ms = 0;
            identify_deadline_ms = 0;
            host_seen = false;
        } else if (state_deadline_ms != 0 && (int32_t)(now_ms - state_deadline_ms) >= 0) {
            display_state = STATE_IDLE;
            state_started_ms = now_ms;
            state_deadline_ms = 0;
        } else if (!host_seen && display_state == STATE_BOOTING && now_ms - state_started_ms >= 1500) {
            display_state = STATE_DISCONNECTED;
            state_started_ms = now_ms;
        }

        if (now_ms - last_render_ms >= 33) {
            render_current_state(now_ms);
            last_render_ms = now_ms;
        }
        sleep_ms(1);
    }
}
