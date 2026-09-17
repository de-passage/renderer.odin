package renderer

import "core:mem"

new_hexahedron :: proc(
  points: [8]Vertex,
  allocator := context.allocator,
) -> (
  mesh: Mesh,
  err: mem.Allocator_Error,
) {
  local_points := points
  // odinfmt: disable
  return allocate_mesh_clone(
    local_points[:],
    []Triangle_Index {
      // 0, 1, 2, 3 are the top vertices, 0 and 2 facing us, 1 and 3 in the back.
      // 0 and 1 are the left, 2 and 3 are right, same order for the bottom square
      {0, 1, 2}, {1, 3, 2}, // top face
      {0, 6, 4}, {0, 2, 6}, // front face
      {0, 4, 1}, {1, 4, 5}, // left face
      {1, 5, 3}, {3, 5, 7}, // rear face
      {2, 3, 6}, {3, 7, 6}, // right face
      {4, 6, 5}, {5, 6, 7}, // bottom face
    },
    allocator
  )
  // odinfmt: enable

}

new_cube :: proc(
  scale := 1.,
  allocator := context.allocator,
) -> (
  mesh: Mesh,
  err: mem.Allocator_Error,
) {
  P := scale * 0.5
  M := -1 * P
  return new_hexahedron(
    [8]Vertex {
      {M, P, M},
      {M, P, P},
      {P, P, M},
      {P, P, P},
      {M, M, M},
      {M, M, P},
      {P, M, M},
      {P, M, P},
    },
    allocator,
  )
}

create_cube_colors :: proc(
  colors: [6]fRGB
) -> [12]Triangle_Colors {
  return {
    {colors[0], colors[0], colors[0]}, {colors[0], colors[0], colors[0]},
    {colors[1], colors[1], colors[1]}, {colors[1], colors[1], colors[1]},
    {colors[2], colors[2], colors[2]}, {colors[2], colors[2], colors[2]},
    {colors[3], colors[3], colors[3]}, {colors[3], colors[3], colors[3]},
    {colors[4], colors[4], colors[4]}, {colors[4], colors[4], colors[4]},
    {colors[5], colors[5], colors[5]}, {colors[5], colors[5], colors[5]},
  }
}

new_interpolation_test_pyramid :: proc(
  allocator := context.allocator,
) -> (
  mesh: Mesh,
  err: mem.Allocator_Error,
) {
  points := [5]Vertex {
    {-0.45, -0.45, -0.45},
    { 0.45, -0.45, -0.45},
    {-0.45, -0.45,  0.45},
    { 0.45, -0.45,  0.45},
    { 0.00,  0.55,  0.00},
  }
  indices := [6]Triangle_Index {
    {0, 1, 2}, {1, 3, 2},
    {0, 4, 1}, {1, 4, 3},
    {3, 4, 2}, {2, 4, 0},
  }
  return allocate_mesh_clone(points[:], indices[:], allocator)
}

create_interpolation_test_colors :: proc() -> [6]Triangle_Colors {
  return {
    {RED, GREEN, BLUE}, {GREEN, YELLOW, BLUE},
    {RED, MAGENTA, GREEN}, {GREEN, MAGENTA, YELLOW},
    {YELLOW, MAGENTA, BLUE}, {BLUE, MAGENTA, RED},
  }
}
