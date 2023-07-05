#include <stdlib.h>
#include <stdio.h>

#include "pd_api.h"
#include "gifenc.h"

static PlaydateAPI *pd = NULL;
static int build_bitmap_from_message(lua_State *L);
static int create_gif(lua_State *L);
static int close_gif(lua_State *L);
static int append_image(lua_State *L);

static int const FRAME_WIDTH = 320;
static int const FRAME_HEIGHT = 240;

#ifdef _WINDLL
__declspec(dllexport)
#endif
    int eventHandler(PlaydateAPI *playdate, PDSystemEvent event, uint32_t arg)
{
  if (event == kEventInitLua)
  {
    pd = playdate;

    const char *err;

    if (!pd->lua->addFunction(build_bitmap_from_message, "_cameraProcessMessage", &err))
      pd->system->logToConsole("%s:%i: addFunction failed, %s", __FILE__, __LINE__, err);

    if (!pd->lua->addFunction(create_gif, "_createGif", &err))
      pd->system->logToConsole("%s:%i: addFunction failed, %s", __FILE__, __LINE__, err);

    if (!pd->lua->addFunction(close_gif, "_closeGif", &err))
      pd->system->logToConsole("%s:%i: addFunction failed, %s", __FILE__, __LINE__, err);

    if (!pd->lua->addFunction(append_image, "_appendImage", &err))
      pd->system->logToConsole("%s:%i: addFunction failed, %s", __FILE__, __LINE__, err);
  }

  return 0;
}

static int build_bitmap_from_message(lua_State *L)
{
  const char *data = pd->lua->getArgString(1);

  (void)L;

  int bitmap_rowbytes = 0;
  uint8_t *bitmap_data = NULL;
  LCDBitmap *bitmap = pd->graphics->newBitmap(FRAME_WIDTH, FRAME_HEIGHT, kColorBlack);
  pd->graphics->getBitmapData(bitmap, NULL, NULL, &bitmap_rowbytes, NULL, &bitmap_data);

  int i, j, x = 0, y = 0;
  for (i = 0; i < 9600; i++)
  {
    for (j = 7; j >= 0; j--)
    {
      if (x == FRAME_WIDTH)
      {
        y++;
        x = 0;
      }
      if (((data[i] >> j) & 1) == 1)
      {
        bitmap_data[(y)*bitmap_rowbytes + (x) / 8] |= (1 << (uint8_t)(7 - ((x) % 8)));
      }
      x++;
    }
  }
  pd->lua->pushBitmap(bitmap);
  return 1;
}

// Determine pixel at x, y is black or white.
// https://devforum.play.date/t/c-macros-for-working-with-playdate-bitmap-data/7706
#define samplepixel(data, x, y, rowbytes) (((data[(y)*rowbytes + (x) / 8] & (1 << (uint8_t)(7 - ((x) % 8)))) != 0) ? 1 : 0)
ge_GIF *gif = NULL;

int counter = 0;
static int append_image(lua_State *L) {
  const char *path = pd->lua->getArgString(1);
  (void)L;
  pd->system->logToConsole("appending %s", path);

  const char *outerr = NULL;
  LCDBitmap *bitmap = pd->graphics->loadBitmap(path, &outerr);
  if (outerr != NULL)
  {
    pd->system->logToConsole("Error loading image at path '%s': %s", path, outerr);
    return 0;
  }
  
  uint8_t* bitmap_data = NULL;
  int bitmap_rowbytes = 0;
  int width;
  int height;
  pd->graphics->getBitmapData(bitmap, &width, &height, &bitmap_rowbytes, NULL, &bitmap_data);
  pd->system->logToConsole("Loaded %u bytes, w%d h%d", sizeof(bitmap_data), width, height);

  for (size_t y = 0; y < height; y++)
  {
    for (size_t x = 0; x < width; x++)
    {
      gif->frame[x + width * y] = samplepixel(bitmap_data, x, y, bitmap_rowbytes);
    }
  }
  ge_add_frame(gif, 20);

  counter++;
  pd->lua->pushInt(counter);
  return 1;
}

static int create_gif(lua_State *L)
{
  const char *filename = pd->lua->getArgString(1);
  const int paletteCode = fmin(fmax(pd->lua->getArgInt(2), 1), 4);
  (void)L;

  pd->system->logToConsole("encoding %s", filename);
  
  /* palette */
  static uint8_t palette[4][6] = {
    {
          0x00, 0x00, 0x00, /* 0 -> black */
          0xFF, 0xFF, 0xFF, /* 1 -> white */
    },
    {
          0x30, 0x2E, 0x27, /* brown */
          0xB0, 0xAE, 0xA7, /* cream */
    },
    {
          0x0F, 0x38, 0x0F,  /* dark green */
          0x9B, 0xBC, 0x0f,  /* light green */
    },
    {
          0x78, 0x00, 0xFF, /* purple */
          0xFF, 0xCD, 0x3F, /* yellow */
    }
  };

  gif = ge_new_gif(
      pd,
      filename,
      FRAME_WIDTH, FRAME_HEIGHT, /* canvas size */
      palette[paletteCode - 1],
      1,  /* palette depth == log2(# of colors) */
      -1, /* no transparency */
      0   /* infinite loop */
  );
  pd->system->logToConsole("gif created");
  return 0;
}

static int close_gif(lua_State *L)
{
  (void)L;
  ge_close_gif(gif);
  pd->system->logToConsole("closed gif");
  return 0;
}
