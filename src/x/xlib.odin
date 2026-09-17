package x

import "vendor:x11/xlib"

Error :: enum {
  None,
  Display_Open_Failed,
  Window_No_Root,
  Window_Create_Failed,
  Extension_Missing,
}

State :: struct {
  display:            ^xlib.Display,
  event:              xlib.XEvent,
  visual:             ^xlib.Visual,
  window:             xlib.Window,
  screen:             i32,
  gc:                 xlib.GC,
  depth:              i32,
  closeWindowMessage: xlib.Atom,
  a_code:             xlib.KeyCode,
  w_code:             xlib.KeyCode,
  s_code:             xlib.KeyCode,
  d_code:             xlib.KeyCode,
  q_code:             xlib.KeyCode,
  e_code:             xlib.KeyCode,
  r_code:             xlib.KeyCode,
  f_code:             xlib.KeyCode,
  x_code:             xlib.KeyCode,
  c_code:             xlib.KeyCode,
  completion_type:    i32,
}

fill_keysyms :: proc(state: ^State) {
  state.a_code = xlib.KeysymToKeycode(state.display, .XK_a)
  state.w_code = xlib.KeysymToKeycode(state.display, .XK_w)
  state.s_code = xlib.KeysymToKeycode(state.display, .XK_s)
  state.d_code = xlib.KeysymToKeycode(state.display, .XK_d)
  state.q_code = xlib.KeysymToKeycode(state.display, .XK_q)
  state.e_code = xlib.KeysymToKeycode(state.display, .XK_e)
  state.r_code = xlib.KeysymToKeycode(state.display, .XK_r)
  state.f_code = xlib.KeysymToKeycode(state.display, .XK_f)
  state.x_code = xlib.KeysymToKeycode(state.display, .XK_x)
  state.c_code = xlib.KeysymToKeycode(state.display, .XK_c)
}

teardown_xlib :: proc(state: State) {
  xlib.DestroyWindow(state.display, state.window)
  xlib.CloseDisplay(state.display)
}

setup_xlib :: proc(width, height: u32) -> (state: State, err: Error) {

  state.display = xlib.OpenDisplay(nil)

  if state.display == nil {
    err = .Display_Open_Failed
    return
  }
  display := state.display

  if !QueryExtension(display) {
    xlib.CloseDisplay(display)
    err = .Extension_Missing
    return
  }

  root := xlib.DefaultRootWindow(display)
  if root == xlib.None {
    xlib.CloseDisplay(display)
    err = .Window_No_Root
    return
  }

  state.window = xlib.CreateSimpleWindow(display, root, 0, 0, width, height, 0, 0, 0xffffffff)
  window := state.window
  if (window == xlib.None) {
    xlib.CloseDisplay(display)
    err = .Window_Create_Failed
    return
  }

  state.completion_type = GetEventBase(state.display)
  xlib.SelectInput(display, window, {.Exposure, .KeyPress, .KeyRelease})
  xlib.MapWindow(display, window)

  closeWindowMessage := xlib.InternAtom(display, "WM_DELETE_WINDOW", false)
  xlib.SetWMProtocols(display, window, &closeWindowMessage, 1)

  state.screen = xlib.DefaultScreen(display)
  state.depth = xlib.DefaultDepth(display, state.screen)
  state.visual = xlib.DefaultVisual(display, state.screen)
  state.gc = xlib.DefaultGC(display, state.screen)

  fill_keysyms(&state)

  return
}
