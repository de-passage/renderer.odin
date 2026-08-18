package renderer

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:time"
import "vendor:x11/xlib"

quited := false

MOVEMENT_OFFSET :: .03
ROTATION_ANGLE :: math.PI / 200
TARGET_FPS :: 60.
FRAME_DURATION :: time.Second / TARGET_FPS

Camera :: struct {
  position:    Vec3,
  orientation: Rotation,
}

render :: proc(
  width, height: int,
  output: []RGB,
  camera: Camera,
  allocator := context.allocator,
) -> (
  err: mem.Allocator_Error,
) {

  size := height * width
  fw := f64(width)
  fh := f64(height)

  cube: Object
  cube.mesh = new_cube(.7, allocator = allocator) or_return
  defer release_mesh(&cube.mesh, allocator)

  cube.translation.z = 2.
  cube.rotation = matrix_mult(
    matrix_mult(rotation_matrix_y(math.PI / 3.), rotation_matrix_x(math.PI / 10)),
    rotation_matrix_z(math.PI / 10),
  )

  triangles := (make_slice([]Triangle, len(cube.triangles), allocator) or_return)[:]
  defer delete(triangles, allocator)

  transform(&triangles, cube, camera.position, transpose(camera.orientation))

  projection := project(triangles[:], 1, fw, fh, allocator) or_return
  defer delete(projection, allocator)

  depth_buffer := make_slice([]f64, size, allocator) or_return
  defer delete(depth_buffer, allocator)

  colors := create_cube_colors({RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA})

  rasterize(projection, colors[:], depth_buffer, width, height, output)

  return
}

XLib_State :: struct {
  display:            ^xlib.Display,
  event:              xlib.XEvent,
  closeWindowMessage: xlib.Atom,
  a_code:             xlib.KeyCode,
  w_code:             xlib.KeyCode,
  s_code:             xlib.KeyCode,
  d_code:             xlib.KeyCode,
  q_code:             xlib.KeyCode,
  e_code:             xlib.KeyCode,
  r_code:             xlib.KeyCode,
  f_code:             xlib.KeyCode,
  x_code:             xlib.KeyCode,
  c_code:             xlib.KeyCode,

  // Cache
  x_rotation: Rotation,
  y_rotation: Rotation,
  z_rotation: Rotation,
}

fill_keysyms :: proc(state: ^XLib_State) {
  state.a_code = xlib.KeysymToKeycode(state.display, .XK_a)
  state.w_code = xlib.KeysymToKeycode(state.display, .XK_w)
  state.s_code = xlib.KeysymToKeycode(state.display, .XK_s)
  state.d_code = xlib.KeysymToKeycode(state.display, .XK_d)
  state.q_code = xlib.KeysymToKeycode(state.display, .XK_q)
  state.e_code = xlib.KeysymToKeycode(state.display, .XK_e)
  state.r_code = xlib.KeysymToKeycode(state.display, .XK_r)
  state.f_code = xlib.KeysymToKeycode(state.display, .XK_f)
  state.x_code = xlib.KeysymToKeycode(state.display, .XK_x)
  state.c_code = xlib.KeysymToKeycode(state.display, .XK_c)
}

handle_window_event :: proc(
  camera: ^Camera,
  keys: ^[256]bool,
  state: XLib_State,
  elapsed: time.Duration,
) -> (
  needs_render: bool,
) {
  display := state.display
  event := state.event
  needs_render = false
  for xlib.Pending(display) > 0 {
    xlib.NextEvent(display, &event)

    #partial switch event.type {
    case .Expose:
      if event.xexpose.count == 0 {
        needs_render = true
      }
    case .ClientMessage:
      if event.xclient.data.l[0] == int(state.closeWindowMessage) {
        quited = true
        break
      }
    case .KeyPress:
      keys[event.xkey.keycode] = true
    case .KeyRelease:
      if xlib.LookupKeysym(&event.xkey, 0) == .XK_Escape {
        quited = true
        break
      }
      keys[event.xkey.keycode] = false
    }
  }

  if keys[state.r_code] {
    needs_render = true
    camera.orientation = matrix_mult(camera.orientation, state.x_rotation)
  }
  if keys[state.f_code] {
    needs_render = true
    camera.orientation = matrix_mult(camera.orientation, transpose(state.x_rotation))
  }
  if keys[state.q_code] {
    needs_render = true
    camera.orientation = matrix_mult(camera.orientation, state.y_rotation)
  }
  if keys[state.e_code] {
    needs_render = true
    camera.orientation = matrix_mult(camera.orientation, transpose(state.y_rotation))
  }

  x_movement := rotate(&Vec3{MOVEMENT_OFFSET, 0, 0}, camera.orientation)
  y_movement := rotate(&Vec3{0, MOVEMENT_OFFSET, 0}, camera.orientation)
  z_movement := rotate(&Vec3{0, 0, MOVEMENT_OFFSET}, camera.orientation)
  if keys[state.a_code] {
    needs_render = true
    camera.position -= x_movement
  }
  if keys[state.w_code] {
    needs_render = true
    camera.position += z_movement
  }
  if keys[state.s_code] {
    needs_render = true
    camera.position -= z_movement
  }
  if keys[state.d_code] {
    needs_render = true
    camera.position += x_movement
  }
  if keys[state.x_code] {
    needs_render = true
    camera.position -= y_movement
  }
  if keys[state.c_code] {
    needs_render = true
    camera.position += y_movement
  }

  return true
}

main :: proc() {
  opts := parse_options()

  camera := Camera {
    orientation = ZERO_ROTATION
  }

  file := opts.output
  width := u32(opts.width)
  height := u32(opts.height)

  display := xlib.OpenDisplay(nil)
  if display == nil {
    exit_with_prejudice("Failed to open display")
  }
  defer xlib.CloseDisplay(display)

  root := xlib.DefaultRootWindow(display)
  if root == xlib.None {
    exit_with_prejudice("No root window found")
  }

  window := xlib.CreateSimpleWindow(display, root, 0, 0, width, height, 0, 0, 0xffffffff)
  if (window == xlib.None) {
    exit_with_prejudice("Failed to create window")
  }

  xlib.SelectInput(display, window, {.Exposure, .KeyPress, .KeyRelease})
  xlib.MapWindow(display, window)

  xlibState := XLib_State {
    display = display,
  }

  xlibState.closeWindowMessage = xlib.InternAtom(display, "WM_DELETE_WINDOW", false)
  xlib.SetWMProtocols(display, window, &xlibState.closeWindowMessage, 1)

  screen := xlib.DefaultScreen(display)
  depth := xlib.DefaultDepth(display, screen)
  visual := xlib.DefaultVisual(display, screen)

  frame_buffer, err := make_slice([]RGB, opts.width * opts.height)
  if err != .None {
    exit_with_prejudice("Failed to allocate enough memory: ", err)
  }
  defer delete(frame_buffer)

  image := xlib.CreateImage(
    display,
    visual,
    u32(depth),
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

  gc := xlib.DefaultGC(display, screen)

  fill_keysyms(&xlibState)
  xlibState.y_rotation = rotation_matrix_y(ROTATION_ANGLE)
  xlibState.z_rotation = rotation_matrix_z(ROTATION_ANGLE)
  xlibState.x_rotation = rotation_matrix_x(ROTATION_ANGLE)

  event: xlib.XEvent
  keys: [256]bool
  last:= time.now()
  for !quited {
    start := time.now()

    tainted := handle_window_event(&camera, &keys, xlibState, time.diff(last, start))
    last := time.now()

    if tainted {
      mem.zero_slice(frame_buffer)
      err = render(opts.width, opts.height, frame_buffer, camera)
      if err != .None {
        exit_with_prejudice("Allocation failed")
      }
      image.data = &frame_buffer[0]
      xlib.PutImage(display, window, gc, image, 0, 0, 0, 0, width, height)
    }

    end := time.since(start)
    if end < FRAME_DURATION {
      time.accurate_sleep(FRAME_DURATION - end)
    } else {
      fmt.eprintln("Missed frame by ", end - FRAME_DURATION)
    }
  }
  xlib.DestroyWindow(display, window)

}
