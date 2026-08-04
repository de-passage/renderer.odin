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

RGB :: distinct [3]u8
Point :: [3]f64
Vertex :: distinct Point
Triangle :: [3]Point
Triangle_Colors :: [3][3]f64
Box :: [2][2]int

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

    efabc := 1. / edge_function(a.x, a.y, b, c)
    efbca := 1. / edge_function(b.x, b.y, c, a)
    efcab := 1. / edge_function(c.x, c.y, a, b)

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
          wa := efxbc * efabc
          wb := efxca * efbca
          wc := efxab * efcab

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
      // EF(x, y + 1) = EF(x, y) + dx
      efyab -= dxab
      efybc -= dxbc
      efyca -= dxca
    }
  }
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
  depth_buffer := make([dynamic]f64, size, size)
  defer delete(depth_buffer)
  current_index := 0

  fw := f64(opts.width)
  fh := f64(opts.height)
  triangles: [2]Triangle = {
    {{fw * 0.5, fh * 0.2, 1.}, {fw * 0.2, fh * 0.7, 1.}, {fw * 0.8, fh * 0.8, 1.}},
    {{fw * 0.5, fh * 0.5, 0.1}, {fw * 1., fh * 0.1, 0.1}, {fw * 1., fh * 0.9, 0.1}},
  }
  colors: [2]Triangle_Colors = {
    {{1., 0., 0.}, {0., 1., 0.}, {0., 0., 1.}},
    {{1., 1., 1.}, {1., 1., 1.}, {1., 1., 0.}},
  }

  rasterize(triangles[:], colors[:], depth_buffer[:], opts.width, opts.height, output[:])

  file := opts.output
  fmt.fprintf(file, "P6\n%i %i\n255\n", opts.width, opts.height)
  os.write(file, mem.slice_to_bytes(output[:]))
  return
}
