#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "config.h"
#include "globals.h"

Config config;

static void trim(char *s) {
  char *e = s + strlen(s) - 1;
  while (e >= s && isspace((unsigned char)*e)) *e-- = '\0';
}

static uint32_t parse_num(const char *s) {
  if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
    return strtoul(s + 2, NULL, 16);
  return strtoul(s, NULL, 10);
}

static bool parse_bool(const char *s) {
  return strcmp(s, "true") == 0 || strcmp(s, "yes") == 0 || strcmp(s, "1") == 0;
}

static void set_defaults(void) {
  config.port                = PORT;
  config.gamemode            = GAMEMODE;
  config.view_distance       = VIEW_DISTANCE;
  config.time_between_ticks  = TIME_BETWEEN_TICKS;
  config.mob_despawn_distance = MOB_DESPAWN_DISTANCE;
  config.terrain_base_height  = TERRAIN_BASE_HEIGHT;
  config.cave_base_depth      = CAVE_BASE_DEPTH;
  config.disk_sync_interval   = DISK_SYNC_INTERVAL;
  config.network_timeout_time = NETWORK_TIMEOUT_TIME;
  config.world_seed           = INITIAL_WORLD_SEED;
  config.rng_seed             = INITIAL_RNG_SEED;
  strcpy(config.motd, "A bareiron server");
#ifdef SEND_BRAND
  strcpy(config.brand, "bareiron");
  config.send_brand = true;
#else
  config.brand[0] = '\0';
  config.send_brand = false;
#endif
}

void config_save_default(const char *path) {
  FILE *f = fopen(path, "w");
  if (!f) {
    perror("Failed to create server.conf");
    return;
  }
  fprintf(f, "# bareiron server configuration\n");
  fprintf(f, "# Uncomment and change a value, then restart the server.\n\n");
  fprintf(f, "# port=%u\n", (unsigned)PORT);
  fprintf(f, "# gamemode=%u\n", (unsigned)GAMEMODE);
  fprintf(f, "# view_distance=%u\n", (unsigned)VIEW_DISTANCE);
  fprintf(f, "# time_between_ticks=%llu\n", (unsigned long long)TIME_BETWEEN_TICKS);
  fprintf(f, "# mob_despawn_distance=%u\n", (unsigned)MOB_DESPAWN_DISTANCE);
  fprintf(f, "# terrain_base_height=%d\n", TERRAIN_BASE_HEIGHT);
  fprintf(f, "# cave_base_depth=%u\n", (unsigned)CAVE_BASE_DEPTH);
  fprintf(f, "# disk_sync_interval=%llu\n", (unsigned long long)DISK_SYNC_INTERVAL);
  fprintf(f, "# network_timeout_time=%llu\n", (unsigned long long)NETWORK_TIMEOUT_TIME);
  fprintf(f, "# world_seed=%u  (0x%X)\n", (unsigned)INITIAL_WORLD_SEED, (unsigned)INITIAL_WORLD_SEED);
  fprintf(f, "# rng_seed=%u  (0x%X)\n", (unsigned)INITIAL_RNG_SEED, (unsigned)INITIAL_RNG_SEED);
  fprintf(f, "# motd=A bareiron server\n");
#ifdef SEND_BRAND
  fprintf(f, "# brand=bareiron\n");
  fprintf(f, "# send_brand=true\n");
#endif
  fclose(f);
  printf("Created server.conf with default settings.\n");
}

void config_load(const char *path) {
  set_defaults();

  FILE *f = fopen(path, "r");
  if (!f) {
    config_save_default(path);
    return;
  }

  char line[256];
  int linenum = 0;
  while (fgets(line, sizeof(line), f)) {
    linenum++;
    char *p = line;
    while (*p && isspace((unsigned char)*p)) p++;
    if (*p == '#' || *p == '\0') continue;

    char *eq = strchr(p, '=');
    if (!eq) continue;

    *eq = '\0';
    char *key = p;
    char *val = eq + 1;
    trim(key);
    trim(val);

    if (strcmp(key, "port") == 0) {
      unsigned long v = strtoul(val, NULL, 10);
      if (v > 0 && v <= 65535) config.port = (uint16_t)v;
      else fprintf(stderr, "server.conf:%d: invalid port\n", linenum);
    } else if (strcmp(key, "gamemode") == 0) {
      unsigned long v = strtoul(val, NULL, 10);
      if (v <= 3) config.gamemode = (uint8_t)v;
      else fprintf(stderr, "server.conf:%d: invalid gamemode (0-3)\n", linenum);
    } else if (strcmp(key, "view_distance") == 0) {
      unsigned long v = strtoul(val, NULL, 10);
      if (v >= 1 && v <= 32) config.view_distance = (uint8_t)v;
      else fprintf(stderr, "server.conf:%d: invalid view_distance\n", linenum);
    } else if (strcmp(key, "time_between_ticks") == 0) {
      config.time_between_ticks = strtoull(val, NULL, 10);
    } else if (strcmp(key, "mob_despawn_distance") == 0) {
      config.mob_despawn_distance = (uint16_t)strtoul(val, NULL, 10);
    } else if (strcmp(key, "terrain_base_height") == 0) {
      config.terrain_base_height = (int16_t)strtol(val, NULL, 10);
    } else if (strcmp(key, "cave_base_depth") == 0) {
      config.cave_base_depth = (uint8_t)strtoul(val, NULL, 10);
    } else if (strcmp(key, "disk_sync_interval") == 0) {
      config.disk_sync_interval = strtoull(val, NULL, 10);
    } else if (strcmp(key, "network_timeout_time") == 0) {
      config.network_timeout_time = strtoull(val, NULL, 10);
    } else if (strcmp(key, "world_seed") == 0) {
      config.world_seed = parse_num(val);
    } else if (strcmp(key, "rng_seed") == 0) {
      config.rng_seed = parse_num(val);
    } else if (strcmp(key, "motd") == 0) {
      strncpy(config.motd, val, sizeof(config.motd) - 1);
      config.motd[sizeof(config.motd) - 1] = '\0';
    } else if (strcmp(key, "brand") == 0) {
      strncpy(config.brand, val, sizeof(config.brand) - 1);
      config.brand[sizeof(config.brand) - 1] = '\0';
    } else if (strcmp(key, "send_brand") == 0) {
      config.send_brand = parse_bool(val);
    } else {
      fprintf(stderr, "server.conf:%d: unknown key '%s'\n", linenum, key);
    }
  }

  fclose(f);
  printf("Loaded server.conf\n");
}
