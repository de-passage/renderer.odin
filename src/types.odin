package renderer

Triangle_Index :: distinct [3]int

RGB :: distinct [4]u8
fRGB :: distinct [3]f64
Vec3 :: [3]f64
Point :: Vec3
Vertex :: Point
Triangle :: [3]Vertex
Triangle_Colors :: [3]fRGB
Box :: [2][2]int
Rotation :: distinct [9]f64

Rich_Triangle :: struct {
  vertices: Triangle,
  colors: Triangle_Colors,
}

Triangle_List :: #soa []Rich_Triangle
