package renderer

import "core:math"
import "core:mem"

move :: proc(vertex: ^Vertex, vector: Vec3) {
  vertex.x += vector.x
  vertex.y += vector.y
  vertex.z += vector.z
}

rotate :: proc(vertex: ^Vertex, rotation: Rotation) -> Vertex {
  v : Vertex = ---
  #no_bounds_check v.x = rotation[0] * vertex.x + rotation[1] * vertex.y + rotation[2] * vertex.z
  #no_bounds_check v.y = rotation[3] * vertex.x + rotation[4] * vertex.y + rotation[5] * vertex.z
  #no_bounds_check v.z = rotation[6] * vertex.x + rotation[7] * vertex.y + rotation[8] * vertex.z
  vertex^ = v
  return vertex^
}

transform :: proc(buffer: ^[]Triangle, object: Object, camera_position: Vec3, camera_rotation: Rotation) -> []Triangle {
  assert(len(buffer) >= len(object.triangles))

  #no_bounds_check for tri_idx, idx in object.triangles {
    t := &buffer[idx]

    t.x = object.position[tri_idx.x]
    t.y = object.position[tri_idx.y]
    t.z = object.position[tri_idx.z]

    rotate(&t.x, object.rotation)
    rotate(&t.y, object.rotation)
    rotate(&t.z, object.rotation)

    move(&t.x, object.translation - camera_position)
    move(&t.y, object.translation - camera_position)
    move(&t.z, object.translation - camera_position)

    rotate(&t.x, camera_rotation)
    rotate(&t.y, camera_rotation)
    rotate(&t.z, camera_rotation)
  }

  return buffer[len(object.triangles):]
}

project_point :: #force_inline proc(
  point: Vertex,
  f: f64,
  hw: f64,
  hh: f64,
  iar: f64,
) -> (
  projected: Vertex,
) {
  over_z := 1. / point.z
  projected.x = (1 + (point.x * f * over_z * iar)) * hw
  projected.y = (1 - (point.y * f * over_z)) * hh
  projected.z = over_z
  return
}

project :: proc(
  triangles: []Triangle,
  fov: f64,
  width: f64,
  height: f64,
  allocator := context.allocator,
) -> (
  output: []Triangle,
  err: mem.Allocator_Error,
) {
  f := 1. / math.tan(fov / 2.)
  output = make([]Triangle, len(triangles), allocator) or_return

  inverse_aspect := height / width
  half_width := width / 2.
  half_height := height / 2.

  #no_bounds_check for triangle, current_index in triangles {
    o := &output[current_index]
    if triangle.x.z < 0.1 || triangle.y.z < 0.1 || triangle.z.z < 0.1 {
      // current triangle becomes completely 0, will not show in final result
      o^ = Triangle{{0., 0., 0.}, {0., 0., 0.}, {0., 0., 0.}}
      continue
    }
    o.x = project_point(triangle.x, f, half_width, half_height, inverse_aspect)
    o.y = project_point(triangle.y, f, half_width, half_height, inverse_aspect)
    o.z = project_point(triangle.z, f, half_width, half_height, inverse_aspect)
  }

  return
}
