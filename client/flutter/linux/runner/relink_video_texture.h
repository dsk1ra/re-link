// FlPixelBufferTexture subclass that delegates to a Rust-side callback.
//
// The Rust crate is loaded by Dart at runtime as an FFI plugin, so the
// runner can't link against it directly. Instead, Rust registers a
// callback with this module at startup (via `#[frb(init)]`); the
// FlPixelBufferTexture's `copy_pixels` callback delegates through that
// function pointer.

#ifndef RELINK_VIDEO_TEXTURE_H_
#define RELINK_VIDEO_TEXTURE_H_

#include <flutter_linux/flutter_linux.h>
#include <stdint.h>

G_BEGIN_DECLS

#define RELINK_TYPE_VIDEO_TEXTURE relink_video_texture_get_type()
G_DECLARE_FINAL_TYPE(RelinkVideoTexture,
                     relink_video_texture,
                     RELINK,
                     VIDEO_TEXTURE,
                     FlPixelBufferTexture)

// Signature of the Rust-provided callback. The implementation should fill
// the out parameters and return true if a frame is available, or return
// false to tell the engine to skip this upload.
typedef bool (*RelinkVideoCopyPixelsFn)(const uint8_t** out_buffer,
                                         uint32_t* out_width,
                                         uint32_t* out_height);

// Create and register the texture on `registrar`. Returns the texture id
// the Flutter `Texture` widget should bind to.
int64_t relink_video_texture_register(FlTextureRegistrar* registrar);

// Returns the id of the registered texture, or 0 if registration has not
// happened yet. Callable from Rust as a plain extern "C" function.
int64_t relink_video_texture_get_id(void);

// Mark the texture as having a new frame; the engine will schedule a
// `copy_pixels` callback. Safe to call from any thread.
void relink_video_texture_mark_dirty(void);

// Rust calls this once at FRB init time to install its `copy_pixels`
// implementation. Until this is called the texture renders empty.
void relink_video_texture_set_copy_pixels_callback(RelinkVideoCopyPixelsFn cb);

G_END_DECLS

#endif  // RELINK_VIDEO_TEXTURE_H_
