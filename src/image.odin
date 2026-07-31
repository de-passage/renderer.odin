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

RGB :: struct {
  red:   u8,
  green: u8,
  blue:  u8,
}

exit_with_prejudice :: proc(text: string, args: ..any, exit_code := 1) {
  fmt.eprintfln(text, ..args)
  os.exit(exit_code)
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
  current_index := 0

  for y in 0 ..< opts.height {
    for x in 0 ..< opts.width {
      r := math.lerp(0., 255., f64(x) / f64(opts.width))
      g := math.lerp(0., 255., f64(y) / f64(opts.height))
      output[current_index] = RGB{u8(r), u8(g), 0}
      current_index += 1
    }
  }

  file := opts.output
  fmt.fprintfln(file, "P6\n%i %i\n255\n", opts.width, opts.height)
  os.write(file, mem.slice_to_bytes(output[:]))
  return
}
