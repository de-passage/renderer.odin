package renderer

import "vendor:x11/xlib"

handle_window_event :: proc(
  camera: ^Camera,
  keys: ^[256]bool,
  state: XLib_State,
  elapsed: f64,
) -> (
  needs_render: bool,
) {
  display := state.display
  event := state.event
  needs_render = false
  for xlib.Pending(display) > 0 {
    xlib.NextEvent(display, &event)

    #partial switch event.type {
    case .Expose:
      if event.xexpose.count == 0 {
        needs_render = true
      }
    case .ClientMessage:
      if event.xclient.data.l[0] == int(state.closeWindowMessage) {
        quited = true
        break
      }
    case .KeyPress:
      keys[event.xkey.keycode] = true
    case .KeyRelease:
      if xlib.LookupKeysym(&event.xkey, 0) == .XK_Escape {
        quited = true
        break
      }
      keys[event.xkey.keycode] = false
    }
  }

  angle := ROTATION_ANGLE * elapsed
  x_rotation := rotation_matrix_x(angle)
  y_rotation := rotation_matrix_y(angle)
  z_rotation := rotation_matrix_z(angle)

  if keys[state.r_code] {
    needs_render = true
    camera.orientation = matrix_mult(camera.orientation, x_rotation)
  }
  if keys[state.f_code] {
    needs_render = true
    camera.orientation = matrix_mult(camera.orientation, transpose(x_rotation))
  }
  if keys[state.q_code] {
    needs_render = true
    camera.orientation = matrix_mult(camera.orientation, y_rotation)
  }
  if keys[state.e_code] {
    needs_render = true
    camera.orientation = matrix_mult(camera.orientation, transpose(y_rotation))
  }

  offset := MOVEMENT_OFFSET * elapsed
  x_movement := rotate(&Vec3{offset, 0, 0}, camera.orientation)
  y_movement := rotate(&Vec3{0, offset, 0}, camera.orientation)
  z_movement := rotate(&Vec3{0, 0, offset}, camera.orientation)

  if keys[state.a_code] {
    needs_render = true
    camera.position -= x_movement
  }
  if keys[state.w_code] {
    needs_render = true
    camera.position += z_movement
  }
  if keys[state.s_code] {
    needs_render = true
    camera.position -= z_movement
  }
  if keys[state.d_code] {
    needs_render = true
    camera.position += x_movement
  }
  if keys[state.x_code] {
    needs_render = true
    camera.position -= y_movement
  }
  if keys[state.c_code] {
    needs_render = true
    camera.position += y_movement
  }

  return needs_render
}
