#include "relink_video_texture.h"

#include <flutter_linux/flutter_linux.h>
#include <stdint.h>

struct _RelinkVideoTexture {
  FlPixelBufferTexture parent_instance;
};

G_DEFINE_TYPE(RelinkVideoTexture,
              relink_video_texture,
              fl_pixel_buffer_texture_get_type())

static FlTextureRegistrar* g_registrar = nullptr;
static FlTexture* g_texture = nullptr;
static int64_t g_texture_id = 0;
static RelinkVideoCopyPixelsFn g_copy_pixels = nullptr;

static gboolean relink_video_texture_copy_pixels(FlPixelBufferTexture* texture,
                                                  const uint8_t** out_buffer,
                                                  uint32_t* width,
                                                  uint32_t* height,
                                                  GError** error) {
  (void)texture;
  if (g_copy_pixels != nullptr && g_copy_pixels(out_buffer, width, height)) {
    return TRUE;
  }
  // Contract: a FALSE return MUST set the GError. The engine's external
  // texture frame callback logs error->message unconditionally on failure,
  // so FALSE with a null error segfaults the raster thread — hit whenever
  // the texture painted before the first decoded frame was published.
  g_set_error(error, g_quark_from_static_string("relink-video-texture"), 0,
              "no video frame available yet");
  return FALSE;
}

static void relink_video_texture_class_init(RelinkVideoTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      relink_video_texture_copy_pixels;
}

static void relink_video_texture_init(RelinkVideoTexture* /*self*/) {}

int64_t relink_video_texture_register(FlTextureRegistrar* registrar) {
  if (g_texture != nullptr) {
    return g_texture_id;  // already registered
  }
  g_registrar = registrar;
  g_texture = FL_TEXTURE(g_object_new(RELINK_TYPE_VIDEO_TEXTURE, nullptr));
  if (!fl_texture_registrar_register_texture(registrar, g_texture)) {
    g_warning("relink_video_texture: failed to register texture");
    g_object_unref(g_texture);
    g_texture = nullptr;
    g_registrar = nullptr;
    return 0;
  }
  g_texture_id = fl_texture_get_id(g_texture);
  return g_texture_id;
}

int64_t relink_video_texture_get_id(void) {
  return g_texture_id;
}

void relink_video_texture_mark_dirty(void) {
  if (g_registrar != nullptr && g_texture != nullptr) {
    fl_texture_registrar_mark_texture_frame_available(g_registrar, g_texture);
  }
}

void relink_video_texture_set_copy_pixels_callback(RelinkVideoCopyPixelsFn cb) {
  g_copy_pixels = cb;
}
