package renderer

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "vendor:x11/xlib"

quited := false

Camera :: struct {
  position: Vec3,
  orientation: Rotation,
}

run :: proc(width, height: int, output: []RGB, allocator := context.allocator) -> (err: mem.Allocator_Error) {

  size := height * width
  fw := f64(width)
  fh := f64(height)

  cube: Object
  cube.mesh = new_cube(.7, allocator = allocator) or_return
  defer release_mesh(&cube.mesh, allocator)

  cube.translation.z = 2.
  cube.rotation = matrix_mult(matrix_mult(rotation_matrix_y(math.PI / 3.), rotation_matrix_x(math.PI / 10)), rotation_matrix_z(math.PI / 10))

  triangles := (make_slice([]Triangle, len(cube.triangles), allocator) or_return)[:]
  defer delete(triangles, allocator)

  camera:= Camera{
    position = Vec3{0.7, -0.1, 0.5},
    orientation = matrix_mult( rotation_matrix_x(math.PI / 12), rotation_matrix_y(math.PI / 10))
  }

  transform(&triangles, cube, camera.position, transpose(camera.orientation))

  projection := project(triangles[:], 1.57, fw, fh, allocator) or_return
  defer delete(projection, allocator)

  depth_buffer := make_slice([]f64, size, allocator) or_return
  defer delete(depth_buffer, allocator)

  colors := create_cube_colors({RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA})

  rasterize(projection, colors[:], depth_buffer, width, height, output)

  return
}

main :: proc() {
  opts := parse_options()

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

  xlib.SelectInput(display, window, {.Exposure})
  xlib.MapWindow(display, window)

  closeWindowMessage := xlib.InternAtom(display, "WM_DELETE_WINDOW", false)
  xlib.SetWMProtocols(display, window, &closeWindowMessage, 1)

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

  event: xlib.XEvent
  for !quited {
    xlib.NextEvent(display, &event)

    #partial switch event.type {
    case .Expose:
      if event.xexpose.count == 0 {
        err = run(opts.width, opts.height, frame_buffer)
        image.data = &frame_buffer[0]
        xlib.PutImage(display, window, gc, image, 0, 0, 0, 0, width, height)
      }
    case .ClientMessage:
      if event.xclient.data.l[0] == int(closeWindowMessage) {
        xlib.DestroyWindow(display, window)
        quited = true
      }
    }
  }

}
