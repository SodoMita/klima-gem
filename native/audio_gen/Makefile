CC ?= cc
CFLAGS = -std=c11 -O2 -Iinclude -I../scene_score -Wall -Wextra
LDFLAGS = -lm

SRC = src/ag_common.c src/ag_osc.c src/ag_envelope.c src/ag_filter.c src/ag_noise.c src/ag_sfx.c src/ag_drums.c src/ag_fm.c src/ag_chiptune.c src/ag_ambient.c src/ag_music_box.c src/ag_sequencer.c src/ag_reverb.c src/ag_delay.c src/ag_wav.c src/ag_proc_music.c src/ag_distortion.c src/ag_sampler.c src/ag_formant.c src/ag_presets.c src/ag_3d.c src/ag_water.c src/ag_fire.c src/ag_nature.c src/ag_weather.c src/ag_biome.c src/ag_ambience_3d.c src/ag_soundscape.c src/ag_material.c src/ag_terrain.c src/ag_scifi.c src/ag_magic.c src/audio_gen.c

OBJ = $(SRC:.c=.o)

BIN = bin/test_all bin/gen_samples bin/gen_env

all: $(BIN)

bin/test_all: $(SRC) tests/test_all.c | bin
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

bin/gen_samples: $(SRC) tests/gen_samples.c | bin
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

bin/gen_env: $(SRC) tests/gen_env.c | bin
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

bin:
	mkdir -p bin

test: bin/test_all
	./bin/test_all

samples: bin/gen_samples
	./bin/gen_samples
	ls -lh /tmp/ag_*.wav

clean:
	rm -rf bin/*.o src/*.o bin/test_all bin/gen_samples
	rm -f /tmp/ag_*.wav /tmp/test_audio_gen.wav

.PHONY: all test samples clean
