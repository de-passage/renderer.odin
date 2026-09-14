package renderer

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:time"
import "vendor:x11/xlib"

import "x"

Cache :: struct {
  xlibState: x.State,
}

quited := false

MOVEMENT_OFFSET :: .003
ROTATION_ANGLE :: math.PI * .0005
TARGET_FPS :: 60.
FRAME_DURATION :: time.Second / TARGET_FPS

State :: struct {
  xstate: x.State,
  frames: [2]Frame,
}

delete_state :: proc(state: ^State) {
  for &frame in state.frames {
    delete_frame(&frame, state.xstate)
  }
}

main_impl :: proc(opts: Options) -> string {
  camera := Camera {
    orientation = ZERO_ROTATION,
  }

  file := opts.output // what should I do with this
  width := u32(opts.width)
  height := u32(opts.height)
  frame_size := width * height

  xerr: x.Error
  state: State
  state.xstate, xerr = x.setup_xlib(width, height)
  xstate := &state.xstate
  switch xerr {
  case .None:
  case .Display_Open_Failed:
    return "Failed to open X Display"
  case .Window_No_Root:
    return "Failed to find X root window"
  case .Window_Create_Failed:
    return "Failed to create X Window"
  case .Extension_Missing:
    return "Extension missing"
  }
  defer x.teardown_xlib(state.xstate)

  for &frame, index in state.frames {
    err: Frame_Error
    err = init_frame(&frame, height, width, xstate^)
    if err != nil {
      for x in 0 ..< index {
        delete_frame(&state.frames[x], state.xstate)
      }
      switch err {
      case .SHM_ID_FAILED:
        return "Failed to get shared memory id"
      case .SHM_ALLOC_FAILED:
        return "Failed to allocate shared_memory"
      case .SHM_ATTACH_FAILED:
        return "Failed to attach shared memory to display"
      case .SHM_IMAGE_FAILED:
        return "Failed to create image"
      }
    }
  }
  defer delete_state(&state)

  // Allocator for the frame data
  frame_arena_size := frame_size * 8 + 1024 * 1024 * 2 // Size of the depth buffer + headroom
  frame_arena_buffer := make_slice([]byte, frame_arena_size)
  frame_arena: mem.Arena

  mem.arena_init(&frame_arena, frame_arena_buffer)
  frame_allocator := mem.arena_allocator(&frame_arena)

  event: xlib.XEvent
  keys: [256]bool
  last := time.now()

  force_redraw := false
  for !quited {
    start := time.now()

    elapsed := f64(time.diff(last, start)) / f64(time.Second)
    tainted := handle_window_event(&camera, &keys, &state, elapsed)
    last := time.now()

    if tainted || force_redraw {
      frame: ^Frame
      for &f in state.frames {
        if !f.in_flight {
          frame = &f
        }
      }
      if frame == nil {
        // X is too slow, we'll loop until we can get an empty buffer
        force_redraw = true
        continue
      }

      mem.zero_slice(frame.buffer)
      err := render(opts.width, opts.height, frame.buffer, camera, frame_allocator)
      if err != .None {
        return fmt.aprintf(
          "Frame arena exhausted: capacity=%d, peak=%d",
          len(frame_arena_buffer),
          frame_arena.peak_used,
        )
      }
      frame.in_flight = true

      x.PutImage(
        xstate.display,
        xstate.window,
        xstate.gc,
        frame.image,
        0,
        0,
        0,
        0,
        width,
        height,
        true,
      )
    }

    mem.arena_free_all(&frame_arena)
    xlib.Flush(xstate.display)

    end := time.since(start)
    force_redraw = false
    if end < FRAME_DURATION {
      time.accurate_sleep(FRAME_DURATION - end)
    } else {
      fmt.eprintln("Missed frame by ", end - FRAME_DURATION)
    }
  }
  return ""
}

main :: proc() {
  opts := parse_options()
  err := main_impl(opts)
  if err != "" {
    exit_with_prejudice(err)
  }
}
