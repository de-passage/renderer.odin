package x

import "vendor:x11/xlib"
foreign import "system:Xext"

foreign Xext {
  XShmQueryExtension :: proc "c" (display: ^xlib.Display) -> bool ---

  XShmCreateImage :: proc "c" (display: ^xlib.Display, visual: ^xlib.Visual, depth: u32, format: i32, data: rawptr, shminfo: ^ShmSegmentInfo, width, height: u32) -> xlib.XImage ---

  XShmAttach :: proc "c" (display: ^xlib.Display, shminfo: ^ShmSegmentInfo) -> bool ---
  XShmDetach :: proc "c" (display: ^xlib.Display, shminfo: ^ShmSegmentInfo) -> bool ---
  XShmPutImage :: proc "c" (display: ^xlib.Display, drawable: xlib.Drawable, gc: xlib.GC, src_x, src_y, dest_x, dest_y: i32, width, height: u32, send_event: bool) -> bool ---
}

ShmSeg :: distinct xlib.XID

ShmCompletionEvent :: struct {
  type:                   i32,
  serial:                 u64,
  send_event:             bool,
  display:                ^xlib.Display,
  drawable:               xlib.Drawable,
  major_code, minor_code: i32,
  shmseg:                 ShmSeg,
  offset:                 u64,
}

ShmSegmentInfo :: struct {
  shmseg:   ShmSeg,
  shmid:    i32,
  shmaddr:  rawptr,
  readonly: bool,
}
