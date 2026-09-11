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

Frame :: struct {
  buffer:    []RGB,
  in_flight: bool,
  id:        x.ShmSeg,
  shmid:     x.ShmID,
  image:     ^xlib.XImage,
  segment_info: x.SegmentInfo,
}

State :: struct {
  xstate: x.State,
  frames: [2]Frame,
}

Frame_Error :: enum {
  SHM_ID_FAILED,
  SHM_ALLOC_FAILED,
  SHM_ATTACH_FAILED,
  SHM_IMAGE_FAILED,
}

init_frame :: proc(frame: ^Frame, height, width: u32, xstate: x.State) -> (err: Frame_Error) {
  // Allocate a shared memory block and get its identifier
  frame_size := height * width
  frame_buffer_byte_size := frame_size * size_of(RGB)
  frame.shmid = x.shmget(
    x.IPC_PRIVATE,
    uintptr(frame_buffer_byte_size),
    x.SHM_R | x.SHM_W | x.IPC_CREAT,
  )
  if frame.shmid == -1 {
    err = .SHM_ID_FAILED
    return
  }

  // Map the shared memory into program virtual address space
  shared_memory := x.shmat(frame.shmid, nil, 0)
  if shared_memory == rawptr(~uintptr(0)) {
    err = .SHM_ALLOC_FAILED
    x.shmctl(frame.shmid, x.IPC_RMID, nil)
    return
  }
  frame.buffer = mem.slice_ptr((^RGB)(shared_memory), int(frame_size)) // Turn it into an Odin object.

  frame.segment_info = x.SegmentInfo {
    shmid    = frame.shmid,
    shmaddr  = shared_memory,
    readonly = false,
  }

  ok := x.Attach(xstate.display, &frame.segment_info)
  if !ok {
    err = .SHM_ATTACH_FAILED
    x.shmdt(shared_memory)
    x.shmctl(frame.shmid, x.IPC_RMID, nil)
    return
  }

  frame.image = x.CreateImage(
    xstate.display,
    xstate.visual,
    u32(xstate.depth),
    .ZPixmap,
    nil,
    &frame.segment_info,
    width,
    height,
  )
  frame.id = frame.segment_info.shmseg
  if frame.image == nil {
    err = .SHM_IMAGE_FAILED
    x.shmdt(shared_memory)
    x.shmctl(frame.shmid, x.IPC_RMID, nil)
    return
  }
  frame.image.data = &frame.buffer[0]
  return
}

delete_frame :: proc(frame: ^Frame, state: x.State) {
  if frame.buffer != nil {
    x.shmdt(rawptr(&frame.buffer[0]))
    frame.buffer = nil
  }
  if frame.shmid != -1 {
    x.Detach(state.display, &frame.segment_info)
    x.shmctl(frame.shmid, x.IPC_RMID, nil)
    frame.shmid = -1
  }
  if frame.image != nil {
    xlib.DestroyImage(frame.image)
    frame.image = nil
  }
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

      x.PutImage(xstate.display, xstate.window, xstate.gc, frame.image, 0, 0, 0, 0, width, height, true)
    }

    mem.arena_free_all(&frame_arena)
    end := time.since(start)
    xlib.Flush(xstate.display)

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
