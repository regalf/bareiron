#ifndef H_CONFIG
#define H_CONFIG

#include <stdint.h>
#include <stdbool.h>

typedef struct {
  uint16_t port;
  uint8_t gamemode;
  uint8_t view_distance;
  uint64_t time_between_ticks;
  uint16_t mob_despawn_distance;
  int16_t terrain_base_height;
  uint8_t cave_base_depth;
  uint64_t disk_sync_interval;
  uint64_t network_timeout_time;
  uint32_t world_seed;
  uint32_t rng_seed;
  char motd[64];
  char brand[64];
  bool send_brand;
} Config;

extern Config config;

void config_load(const char *path);

#endif
