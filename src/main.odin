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

Error_Type :: union {
  mem.Allocator_Error,
  x.Error,
}

main_impl :: proc(opts: Options) -> string {
  camera := Camera {
    orientation = ZERO_ROTATION,
  }

  file := opts.output // what should I do with this
  width := u32(opts.width)
  height := u32(opts.height)
  frame_size := width * height

  xlibState, xerr := x.setup_xlib(width, height)
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
  defer x.teardown_xlib(xlibState)

  // Allocate a shared memory block and get its identifier
  frame_buffer_byte_size := frame_size * size_of(RGB)
  shared_memory_id := x.shmget(
    x.IPC_PRIVATE,
    uintptr(frame_buffer_byte_size),
    x.SHM_R | x.SHM_W | x.IPC_CREAT,
  )
  if shared_memory_id == -1 {
    return "Failed to get shared memory id"
  }
  defer x.shmctl(shared_memory_id, x.IPC_RMID, nil)

  // Map the shared memory into program virtual address space
  shared_memory := x.shmat(shared_memory_id, nil, 0)
  if shared_memory == rawptr(~uintptr(0)) {
    return "Failed to allocate shared_memory"
  }
  frame_buffer := mem.slice_ptr((^RGB)(shared_memory), int(frame_size)) // Turn it into an Odin object.
  defer x.shmdt(shared_memory)

  segment_info := x.SegmentInfo {
    shmid    = shared_memory_id,
    shmaddr  = shared_memory,
    readonly = false,
  }

  ok := x.Attach(xlibState.display, &segment_info)
  if !ok {
    return "Failed to attach shared memory to display"
  }

  image := x.CreateImage(
    xlibState.display,
    xlibState.visual,
    u32(xlibState.depth),
    .ZPixmap,
    nil,
    &segment_info,
    width,
    height,
  )
  if image == nil {
    return "Failed to create image"
  }

  defer {
    image.data = nil
  }

  // Allocator for the frame data
  frame_arena_size := frame_size * 8 + 1024 * 1024 * 2 // Size of the depth buffer + headroom
  frame_arena_buffer := make_slice([]byte, frame_arena_size)
  frame_arena: mem.Arena

  mem.arena_init(&frame_arena, frame_arena_buffer)
  frame_allocator := mem.arena_allocator(&frame_arena)

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
      err := render(opts.width, opts.height, frame_buffer, camera, frame_allocator)
      if err != .None {
        return fmt.aprintf(
          "Frame arena exhausted: capacity=%d, peak=%d",
          len(frame_arena_buffer),
          frame_arena.peak_used,
        )
      }
      image.data = &frame_buffer[0]
      x.PutImage(
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
        true,
      )
    }

    mem.arena_free_all(&frame_arena)
    end := time.since(start)
    xlib.Flush(xlibState.display)
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
