package renderer

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:time"
import "vendor:x11/xlib"

Cache :: struct {
  xlibState: XLib_State,
}

quited := false

MOVEMENT_OFFSET :: .003
ROTATION_ANGLE :: math.PI * .0005
TARGET_FPS :: 60.
FRAME_DURATION :: time.Second / TARGET_FPS


main :: proc() {
  opts := parse_options()

  camera := Camera {
    orientation = ZERO_ROTATION,
  }

  file := opts.output // what should I do with this
  width := u32(opts.width)
  height := u32(opts.height)

  xlibState := setup_xlib(width, height)
  defer teardown_xlib(xlibState)

  frame_buffer, err := make_slice([]RGB, opts.width * opts.height)
  if err != .None {
    exit_with_prejudice("Failed to allocate enough memory: ", err)
  }
  defer delete(frame_buffer)

  frame_arena_size := opts.width * opts.height * 8 + 1024 * 1024 * 2
  frame_arena_buffer := make_slice([]byte, frame_arena_size) // Size of the depth buffer + headroom
  frame_arena: mem.Arena
  mem.arena_init(&frame_arena, frame_arena_buffer)
  frame_allocator := mem.arena_allocator(&frame_arena)

  image := xlib.CreateImage(
    xlibState.display,
    xlibState.visual,
    u32(xlibState.depth),
    .ZPixmap,
    0,
    &frame_buffer[0],
    width,
    height,
    32,
    0,
  )

  if image == nil {
    exit_with_prejudice("Failed to create image")
  }
  defer {
    image.data = nil
    xlib.DestroyImage(image)
  }

  event: xlib.XEvent
  keys: [256]bool
  last := time.now()
  for !quited {
    start := time.now()

    elapsed := f64(time.diff(last, start)) / f64(time.Second)
    tainted := handle_window_event(&camera, &keys, xlibState, elapsed)
    last := time.now()

    if tainted {
      mem.zero_slice(frame_buffer)
      err = render(opts.width, opts.height, frame_buffer, camera, frame_allocator)
      if err != .None {
        exit_with_prejudice(
          "Frame arena exhausted: capacity=%d, peak=%d",
          len(frame_arena_buffer),
          frame_arena.peak_used,
        )
      }
      image.data = &frame_buffer[0]
      xlib.PutImage(
        xlibState.display,
        xlibState.window,
        xlibState.gc,
        image,
        0,
        0,
        0,
        0,
        width,
        height,
      )
    }

    mem.arena_free_all(&frame_arena)
    end := time.since(start)
    if end < FRAME_DURATION {
      time.accurate_sleep(FRAME_DURATION - end)
    } else {
      fmt.eprintln("Missed frame by ", end - FRAME_DURATION)
    }
  }
}
