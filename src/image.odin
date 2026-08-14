package renderer

import "core:flags"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"

Options :: struct {
  program_name: string `args:"pos=0"`,
  width:        int,
  height:       int,
  output:       ^os.File `args:"file=cw"`,
}

Rotation :: distinct [9]f64

Object :: struct {
  using mesh: Mesh,
  rotation: Rotation,
  translation: Vec3,
}

rotation_matrix_x :: proc(theta: f64) -> Rotation {
  // odinfmt: disable
  return Rotation{
    1,0,0,
    0,math.cos(theta), -math.sin(theta),
    0,math.sin(theta), math.cos(theta),
  }
  // odinfmt: enable
}

rotation_matrix_y :: proc(theta: f64) -> Rotation {
  // odinfmt: disable
  return Rotation{
    math.cos(theta),  0, math.sin(theta),
    0,                1, 0,
    -math.sin(theta), 0, math.cos(theta)
  }
  // odinfmt: enable
}

rotation_matrix_z :: proc(theta: f64) -> Rotation {
  // odinfmt: disable
  return Rotation{
    math.cos(theta), -math.sin(theta), 0,
    math.sin(theta), math.cos(theta),  0,
    0,               0,                1
  }
  // odinfmt: enable
}

matrix_mult :: proc(l, r: Rotation) -> Rotation {
  return Rotation {
    l[0] * r[0] + l[1] * r[3] + l[2] * r[6],
    l[0] * r[1] + l[1] * r[4] + l[2] * r[7],
    l[0] * r[2] + l[1] * r[5] + l[2] * r[8],
    l[3] * r[0] + l[4] * r[3] + l[5] * r[6],
    l[3] * r[1] + l[4] * r[4] + l[5] * r[7],
    l[3] * r[2] + l[4] * r[5] + l[5] * r[8],
    l[6] * r[0] + l[7] * r[3] + l[8] * r[6],
    l[6] * r[1] + l[7] * r[4] + l[8] * r[7],
    l[6] * r[2] + l[7] * r[5] + l[8] * r[8],
  }
}

exit_with_prejudice :: proc(text: string, args: ..any, exit_code := 1) {
  fmt.eprintfln(text, ..args)
  os.exit(exit_code)
}

bounding_box :: proc(triangle: Triangle, width, height: int) -> Box {
  min_x := int(math.floor(min(triangle[0].x, triangle[1].x, triangle[2].x)))
  min_y := int(math.floor(min(triangle[0].y, triangle[1].y, triangle[2].y)))
  max_x := int(math.ceil(max(triangle[0].x, triangle[1].x, triangle[2].x)))
  max_y := int(math.ceil(max(triangle[0].y, triangle[1].y, triangle[2].y)))
  return Box {
    {clamp(min_x, 0, width), clamp(min_y, 0, height)},
    {clamp(max_x, 0, width), clamp(max_y, 0, height)},
  }
}

sign :: #force_inline proc(v: f64) -> u64 {
  return transmute(u64)(v) >> 63
}

edge_function :: proc(x: f64, y: f64, a: Point, b: Point) -> f64 {
  return ((x - a.x) * (b.y - a.y)) - ((y - a.y) * (b.x - a.x))
}

edge_function_constants :: proc(a, b: [2]f64) -> (dx, dy, cst: f64) {
  // edge function (x - a.x) * (b.y - a.y) - (y - a.y) * (b.x - a.x)
  //  =>           x(b.y - a.y) - a.x(b.y - a.y) - y(b.x - a.x) + a.y(b.x - a.x)
  //  =>           x(b.y - a.y) - y(b.x - a.x)  + a.y(b.x - a.x) - a.x(b.y - a.y)
  dy = b.y - a.y
  dx = b.x - a.x
  cst = a.y * dx - a.x * dy
  return
}

move :: proc(vertex: ^Vertex, vector: Vec3) {
  vertex.x += vector.x
  vertex.y += vector.y
  vertex.z += vector.z
}

rotate :: proc(vertex: ^Vertex, rotation: Rotation) {
  v : Vertex = ---
  v.x = rotation[0] * vertex.x + rotation[1] * vertex.y + rotation[2] * vertex.z
  v.y = rotation[3] * vertex.x + rotation[4] * vertex.y + rotation[5] * vertex.z
  v.z = rotation[6] * vertex.x + rotation[7] * vertex.y + rotation[8] * vertex.z
  vertex^ = v
}

transform :: proc(buffer: ^[]Triangle, object: Object) {
  assert(len(buffer) >= len(object.triangles))

  for tri_idx, idx in object.triangles {
    t := &buffer[idx]

    t.x = object.position[tri_idx.x]
    t.y = object.position[tri_idx.y]
    t.z = object.position[tri_idx.z]

    rotate(&t.x, object.rotation)
    rotate(&t.y, object.rotation)
    rotate(&t.z, object.rotation)

    move(&t.x, object.translation)
    move(&t.y, object.translation)
    move(&t.z, object.translation)
  }
}

rasterize :: proc(
  triangles: []Triangle,
  colors: []Triangle_Colors,
  depth_buffer: []f64,
  width: int,
  height: int,
  frame_buffer: []RGB,
) {
  length := len(triangles)

  for t in 0 ..< length {
    triangle := triangles[t]
    box := bounding_box(triangle, width, height)

    a := triangle[0]
    b := triangle[1]
    c := triangle[2]

    // tl means top left
    tl_x := f64(box[0].x) + .5
    tl_y := f64(box[0].y) + .5

    area := edge_function(a.x, a.y, Point(b), Point(c))
    if area == 0 {
      continue
    }
    inverse_area := 1. / area

    dxab, dyab, cstab := edge_function_constants(a.xy, b.xy)
    dxbc, dybc, cstbc := edge_function_constants(b.xy, c.xy)
    dxca, dyca, cstca := edge_function_constants(c.xy, a.xy)

    // => EF(x, y) = xDY - yDX + CST
    efyab := tl_x * dyab - tl_y * dxab + cstab
    efybc := tl_x * dybc - tl_y * dxbc + cstbc
    efyca := tl_x * dyca - tl_y * dxca + cstca

    for y in box[0].y ..< box[1].y {
      efxab := efyab
      efxbc := efybc
      efxca := efyca
      for x in box[0].x ..< box[1].x {

        // 0 iff sum of relative position was 0 or 3 (all same relative position)
        // 0 = 0b00 -> (+1) 0b001 -> (& 0b010) -> 0
        // 1 = 0b01 -> (+1) 0b010 -> (& 0b010) -> 2
        // 2 = 0b10 -> (+1) 0b011 -> (& 0b010) -> 2
        // 3 = 0b11 -> (+1) 0b100 -> (& 0b010) -> 0
        abc := ((sign(efxab) + sign(efxbc) + sign(efxca) + 1) & 0b010)
        if abc == 0 {
          wa := efxbc * inverse_area
          wb := efxca * inverse_area
          wc := efxab * inverse_area

          depth := (wa * triangle[0].z + wb * triangle[1].z + wc * triangle[2].z)
          coord := y * width + x

          if depth_buffer[coord] < depth {
            depth_buffer[coord] = depth

            color := colors[t]

            frame_buffer[coord] = {
              u8((wa * color[0].r + wb * color[1].r + wc * color[2].r) * 255),
              u8((wa * color[0].g + wb * color[1].g + wc * color[2].g) * 255),
              u8((wa * color[0].b + wb * color[1].b + wc * color[2].b) * 255),
            }
          }
        }
        // EF(x + 1, y) = EF(x, y) + dy
        efxab += dyab
        efxbc += dybc
        efxca += dyca
      }
      // EF(x, y + 1) = EF(x, y) - dx
      efyab -= dxab
      efybc -= dxbc
      efyca -= dxca
    }
  }
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

  for triangle, current_index in triangles {
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

main :: proc() {

  opts := Options {
    width  = 80,
    height = 80,
  }
  flag_error := flags.parse(&opts, os.args)

  switch error in flag_error {
  case flags.Parse_Error:
    exit_with_prejudice("Parse error: %s, %v", error.message, error.reason)

  case flags.Open_File_Error:
    exit_with_prejudice("Failed to open file: %s (%v)", error.filename, error.errno)

  case flags.Help_Request:
    fmt.printfln("Usage:\n\t%s -width:WIDTH -height:HEIGHT -output:OUTPUT_FILE", opts.program_name)
    os.exit(0)

  case flags.Validation_Error:
    exit_with_prejudice("Validation error: %s", error.message)
  }

  size := opts.width * opts.height
  output := make([dynamic]RGB, size, size)
  defer delete(output)

  fw := f64(opts.width)
  fh := f64(opts.height)

  err: mem.Allocator_Error
  cube: Object
  cube.mesh, err = new_cube()
  cube.translation.z = 2.
  cube.rotation = matrix_mult(matrix_mult(rotation_matrix_y(math.PI / 3.), rotation_matrix_x(math.PI / 10)), rotation_matrix_z(math.PI / 10))

  triangles := make([dynamic]Triangle, len(cube.triangles), len(cube.triangles))[:]
  defer delete(triangles)
  transform(&triangles, cube)

  if err != .None { return }

  projection : []Triangle
  projection, err = project(triangles[:], 1.57, fw, fh)
  if err != .None { return }
  defer delete(projection)

  depth_buffer := make([dynamic]f64, size, size)
  defer delete(depth_buffer)

  colors := create_cube_colors({RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA})
  rasterize(projection, colors[:], depth_buffer[:], opts.width, opts.height, output[:])

  file := opts.output
  fmt.fprintf(file, "P6\n%i %i\n255\n", opts.width, opts.height)
  os.write(file, mem.slice_to_bytes(output[:]))
  return
}
