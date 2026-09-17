package renderer

import "core:math"
import "core:mem"

Z_NEAR :: 0.1

move :: proc(vertex: ^Vertex, vector: Vec3) {
  vertex.x += vector.x
  vertex.y += vector.y
  vertex.z += vector.z
}

rotate :: proc(vertex: ^Vertex, rotation: Rotation) -> Vertex {
  v: Vertex = ---
  #no_bounds_check v.x = rotation[0] * vertex.x + rotation[1] * vertex.y + rotation[2] * vertex.z
  #no_bounds_check v.y = rotation[3] * vertex.x + rotation[4] * vertex.y + rotation[5] * vertex.z
  #no_bounds_check v.z = rotation[6] * vertex.x + rotation[7] * vertex.y + rotation[8] * vertex.z
  vertex^ = v
  return vertex^
}

transform :: proc(
  buffer: ^[]Triangle,
  object: Object,
  camera_position: Vec3,
  camera_rotation: Rotation,
) -> []Triangle {
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

project_triangle :: proc(
  vertices: ^Triangle,
  triangle: Triangle,
  f, half_width, half_height, inverse_aspect: f64,
) {
  vertices.x = project_point(triangle.x, f, half_width, half_height, inverse_aspect)
  vertices.y = project_point(triangle.y, f, half_width, half_height, inverse_aspect)
  vertices.z = project_point(triangle.z, f, half_width, half_height, inverse_aspect)
}

project :: proc(
  triangles: Triangle_List,
  fov: f64,
  width: f64,
  height: f64,
  allocator := context.allocator,
) -> (
  output: Triangle_List,
  err: mem.Allocator_Error,
) {
  f := 1. / math.tan(fov / 2.)
  output = make(Triangle_List, len(triangles) * 2, allocator) or_return

  inverse_aspect := height / width
  half_width := width / 2.
  half_height := height / 2.

  current_index := 0
  #no_bounds_check for data in triangles {
    triangle := data.vertices

    clip := [3]bool{triangle.x.z < Z_NEAR, triangle.y.z < Z_NEAR, triangle.z.z < Z_NEAR}
    clip_count := 0
    for c in clip {
      if c {
        clip_count += 1
      }
    }

    switch clip_count {
    case 0:
      // fully in
      o := &output[current_index]
      project_triangle(&o.vertices, triangle, f, half_width, half_height, inverse_aspect)
      o.colors = data.colors
      current_index += 1

    case 1:
      // one out, we need to split the remaining polygon into 2 triangles
      o1 := &output[current_index]
      o2 := &output[current_index + 1]
      tr1 := triangle
      tr2 : Triangle
      col1 := &o1.colors
      col2 := &o2.colors

      intersect1: Vertex
      intersect2: Vertex

      if clip[0] {
        t1 := (Z_NEAR - triangle.x.z) / (triangle.y.z - triangle.x.z)
        t2 := (Z_NEAR - triangle.x.z) / (triangle.z.z - triangle.x.z)

        intersect1 = math.lerp(triangle.x, triangle.y, t1)
        intersect2 = math.lerp(triangle.x, triangle.z, t2)

        tr1.x = intersect1
        tr2 = {intersect1, triangle.z, intersect2}

        col1.x = math.lerp(data.colors.x, data.colors.y, t1)
        col1.yz = data.colors.yz
        col2.x = math.lerp(data.colors.x, data.colors.y, t1)
        col2.y = data.colors.z
        col2.z = math.lerp(data.colors.x, data.colors.z, t2)

      } else if clip[1] {
        t1 := (Z_NEAR - triangle.y.z) / (triangle.z.z - triangle.y.z)
        t2 := (Z_NEAR - triangle.y.z) / (triangle.x.z - triangle.y.z)
        intersect1 = math.lerp(triangle.y, triangle.z, t1)
        intersect2 = math.lerp(triangle.y, triangle.x, t2)

        tr1.y = intersect1
        tr2 = {intersect2, intersect1, triangle.x}

        col1.y = math.lerp(data.colors.y, data.colors.z, t1)
        col1.xz = data.colors.xz
        col2.x = math.lerp(data.colors.y, data.colors.x, t2)
        col2.y = math.lerp(data.colors.y, data.colors.z, t1)
        col2.z = data.colors.x
      } else if clip[2] {
        t1 := (Z_NEAR - triangle.z.z) / (triangle.x.z - triangle.z.z)
        t2 := (Z_NEAR - triangle.z.z) / (triangle.y.z - triangle.z.z)
        intersect1 = math.lerp(triangle.z, triangle.x, t1)
        intersect2 = math.lerp(triangle.z, triangle.y, t2)

        tr1.z = intersect1
        tr2 = {triangle.y, intersect2, intersect1}

        col1.z = math.lerp(data.colors.z, data.colors.x, t1)
        col1.xy = data.colors.xy
        col2.x = data.colors.y
        col2.y = math.lerp(data.colors.z, data.colors.y, t2)
        col2.z = math.lerp(data.colors.z, data.colors.x, t1)
      }
      project_triangle(&o1.vertices, tr1, f, half_width, half_height, inverse_aspect)
      project_triangle(&o2.vertices, tr2, f, half_width, half_height, inverse_aspect)
      current_index += 2

    case 2: // 2 points out, the remainder is a triangle with an edge contained on the near plane
      o := &output[current_index]
      if !clip[0] {   // x in, rest out
        ty := (Z_NEAR - triangle.x.z) / (triangle.y.z - triangle.x.z)
        tz := (Z_NEAR - triangle.x.z) / (triangle.z.z - triangle.x.z)

        triangle.y = math.lerp(triangle.x, triangle.y, ty)
        triangle.z = math.lerp(triangle.x, triangle.z, tz)

        o.colors.x = data.colors.x
        o.colors.y = math.lerp(data.colors.x, data.colors.y, ty)
        o.colors.z = math.lerp(data.colors.x, data.colors.z, tz)

        project_triangle(&o.vertices, triangle, f, half_width, half_height, inverse_aspect)
      } else if !clip[1] {   // y in
        tx := (Z_NEAR - triangle.y.z) / (triangle.x.z - triangle.y.z)
        tz := (Z_NEAR - triangle.y.z) / (triangle.z.z - triangle.y.z)

        triangle.x = math.lerp(triangle.y, triangle.x, tx)
        triangle.z = math.lerp(triangle.y, triangle.z, tz)

        o.colors.x = math.lerp(data.colors.y, data.colors.x, tx)
        o.colors.y = data.colors.y
        o.colors.z = math.lerp(data.colors.y, data.colors.z, tz)

        project_triangle(&o.vertices, triangle, f, half_width, half_height, inverse_aspect)

      } else {   // z in
        tx := (Z_NEAR - triangle.z.z) / (triangle.x.z - triangle.z.z)
        ty := (Z_NEAR - triangle.z.z) / (triangle.y.z - triangle.z.z)

        triangle.x = math.lerp(triangle.z, triangle.x, tx)
        triangle.y = math.lerp(triangle.z, triangle.y, ty)

        o.colors.x = math.lerp(data.colors.z, data.colors.x, tx)
        o.colors.y = math.lerp(data.colors.z, data.colors.y, ty)
        o.colors.z = data.colors.z

        project_triangle(&o.vertices, triangle, f, half_width, half_height, inverse_aspect)
      }
      current_index += 1
    case 3:
      // fully out
      continue
    }
  }

  output = output[:current_index]

  return
}
