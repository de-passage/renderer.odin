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

  cube.translation = {-0.5, 0, 2.}
  cube.rotation = matrix_mult(
    matrix_mult(rotation_matrix_y(math.PI / 3.), rotation_matrix_x(math.PI / 10)),
    rotation_matrix_z(math.PI / 10),
  )

  test_pyramid: Object
  test_pyramid.mesh = new_interpolation_test_pyramid(allocator) or_return
  defer release_mesh(&test_pyramid.mesh, allocator)

  test_pyramid.translation = {0.65, 0, 2.}
  test_pyramid.rotation = rotation_matrix_y(-math.PI / 8.)

  triangle_count := len(cube.triangles) + len(test_pyramid.triangles)
  scene_data := (make(Triangle_List, triangle_count, allocator) or_return)
  triangles, colors := soa_unzip(scene_data)
  defer delete(scene_data, allocator)

  remaining_triangles := transform(&triangles, cube, camera.position, transpose(camera.orientation))
  transform(&remaining_triangles, test_pyramid, camera.position, transpose(camera.orientation))

  cube_colors := create_cube_colors({RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA})
  test_colors := create_interpolation_test_colors()
  cube_color_count := len(cube_colors)
  copy(colors[:cube_color_count], cube_colors[:])
  copy(colors[cube_color_count:], test_colors[:])

  projection := project(scene_data, 1, fw, fh, allocator) or_return
  defer delete(projection, allocator)

  depth_buffer := make_slice([]f64, size, allocator) or_return
  defer delete(depth_buffer, allocator)

  rasterize(projection, depth_buffer, width, height, output)

  return
}
