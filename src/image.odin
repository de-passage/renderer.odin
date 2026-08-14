package renderer

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"

Camera :: struct {
  position: Vec3,
  orientation: Rotation,
}

run :: proc(width, height: int, allocator := context.allocator) -> (output: []RGB, err: mem.Allocator_Error) {

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

  output = make_slice([]RGB, size, allocator)
  rasterize(projection, colors[:], depth_buffer, width, height, output)

  return
}

main :: proc() {
  opts := parse_options()
  output, err := run(opts.width, opts.height, context.allocator)
  defer delete(output, context.allocator)

  if err != .None {
    exit_with_prejudice("Failed to allocate enough memory: ", err)
  }

  file := opts.output
  fmt.fprintf(file, "P6\n%i %i\n255\n", opts.width, opts.height)
  os.write(file, mem.slice_to_bytes(output[:]))
}
