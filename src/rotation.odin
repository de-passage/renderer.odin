package renderer

import "core:math"

ZERO_ROTATION := Rotation{1, 0, 0, 0, 1, 0, 0, 0, 1}

rotation_matrix_x :: proc(theta: f64) -> Rotation {
  // odinfmt: disable
  return Rotation{
    1,0,               0,
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
  #no_bounds_check return Rotation {
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

transpose :: proc(mat: Rotation) -> Rotation {
  // odinfmt: disable
  #no_bounds_check return Rotation {
    mat[0], mat[3], mat[6],
    mat[1], mat[4], mat[7],
    mat[2], mat[5], mat[8],
  }
  // odinfmt: enable
}

rotation_matrix :: proc(yaw, pitch, roll: f64) -> Rotation {
  cy, sy := math.cos(yaw), math.sin(yaw)
  cp, sp := math.cos(pitch), math.sin(pitch)
  cr, sr := math.cos(roll), math.sin(roll)

  // odinfmt: disable
  return Rotation {
    cy * cr + sy * sp * sr,  -cy * sr + sy * sp * cr, sy * cp,
    cp * sr,                 cp * cr,                 -sp,
    -sy * cr + cy * sp * sr, sy * sr + cy * sp * cr,  cy * cp,
  }
  // odinfmt: enable
}
