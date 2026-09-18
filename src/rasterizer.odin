package renderer

import "core:math"

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
  triangles: Triangle_List,
  depth_buffer: []f64,
  width: int,
  height: int,
  frame_buffer: []RGB,
) {
  length := len(triangles)

  for t in 0 ..< length {
    triangle := triangles[t].vertices
    box := bounding_box(triangle, width, height)

    a := triangle[0]
    b := triangle[1]
    c := triangle[2]

    // tl means top left
    tl_x := f64(box[0].x) + .5
    tl_y := f64(box[0].y) + .5

    area := edge_function(a.x, a.y, Point(b), Point(c))
    if area >= 0 {
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
          waz := wa * a.z
          wbz := wb * b.z
          wcz := wc * c.z

          depth := (waz + wbz + wcz)
          coord := y * width + x

          if depth_buffer[coord] < depth {
            depth_buffer[coord] = depth
            denom := 255. / depth

            color := triangles[t].colors

            frame_buffer[coord] = {
              u8((waz * color[0].b + wbz * color[1].b + wcz * color[2].b) * denom),
              u8((waz * color[0].g + wbz * color[1].g + wcz * color[2].g) * denom),
              u8((waz * color[0].r + wbz * color[1].r + wcz * color[2].r) * denom),
              0,
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
