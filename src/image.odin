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

bounding_box :: proc(triangle: Triangle) -> Box {
  return Box {
    {
      int(math.floor(min(triangle[0].x, triangle[1].x, triangle[2].x))),
      int(math.floor(min(triangle[0].y, triangle[1].y, triangle[2].y))),
    },
    {
      int(math.ceil(max(triangle[0].x, triangle[1].x, triangle[2].x))),
      int(math.ceil(max(triangle[0].y, triangle[1].y, triangle[2].y))),
    },
  }
}

sign :: #force_inline proc(v: f64) -> u64 {
  return transmute(u64)(v) >> 63
}

edge_function :: proc (x: f64, y: f64, a: Point, b: Point) -> f64 {
  return ((x - a.x) * (b.y - a.y)) - ((y - a.y) * (b.x - a.x))
}

rasterize :: proc(
  triangles: []Triangle,
  colors: []Triangle_Colors,
  depth_buffer: []f64,
  width: int,
  frame_buffer: []RGB,
) {
  length := len(triangles)

  for t in 0 ..< length {
    box := bounding_box(triangles[t])

    a := triangles[t][0]
    b := triangles[t][1]
    c := triangles[t][2]

    for y in box[0].y ..< box[1].y {
      for x in box[0].x ..< box[1].x {
        px := f64(x) + .5
        py := f64(y) + .5
        ab := edge_function(px, py, a, b)
        bc := edge_function(px, py, b, c)
        ca := edge_function(px, py, c, a)

        // 0 iff sum of relative position was 0 or 3 (all same relative position)
        // 0 = 0b00 -> (+1) 0b001 -> (& 0b010) -> 0
        // 1 = 0b01 -> (+1) 0b010 -> (& 0b010) -> 2
        // 2 = 0b10 -> (+1) 0b011 -> (& 0b010) -> 2
        // 3 = 0b11 -> (+1) 0b100 -> (& 0b010) -> 0
        abc := ((sign(ab) + sign(bc) + sign(ca) + 1) & 0b010)

        if abc == 0 /* && compute depth buffer here */ {
          coord := y * width + x

          wa := bc / edge_function(a.x, a.y, b, c)
          wb := ca / edge_function(b.x, b.y, c, a)
          wc := ab / edge_function(c.x, c.y, a, b)

          color := colors[t]

          frame_buffer[coord] = {
            u8((wa * color[0].r + wb * color[1].r + wc * color[2].r) * 255),
            u8((wa * color[0].g + wb * color[1].g + wc * color[2].g) * 255),
            u8((wa * color[0].b + wb * color[1].b + wc * color[2].b) * 255),
          }
        }
      }
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
  triangles : [1]Triangle = {{
    {fw * 0.5, fh * 0.2, 0. },
    {fw * 0.2, fh * 0.7, 0. },
    {fw * 0.8, fh * 0.8, 0. }
  }}
  colors : [1]Triangle_Colors = {
    {
      {1., 0., 0.},
      {0., 1., 0.},
      {0., 0., 1.},
    }
  }

  rasterize(triangles[:], colors[:], depth_buffer[:], opts.width, output[:])

  file := opts.output
  fmt.fprintfln(file, "P6\n%i %i\n255\n", opts.width, opts.height)
  os.write(file, mem.slice_to_bytes(output[:]))
  return
}
