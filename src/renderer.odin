package renderer

import "core:mem"
import "core:math"

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

  cube_data := (make(Triangle_List, len(cube.triangles), allocator) or_return)
  triangles, colors := soa_unzip(cube_data)

  cube_colors := create_cube_colors({RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA})
  copy(colors, cube_colors[:])
  defer delete(cube_data, allocator)

  transform(&triangles, cube, camera.position, transpose(camera.orientation))

  projection := project(cube_data, 1, fw, fh, allocator) or_return
  defer delete(projection, allocator)

  depth_buffer := make_slice([]f64, size, allocator) or_return
  defer delete(depth_buffer, allocator)

  rasterize(projection, depth_buffer, width, height, output)

  return
}
