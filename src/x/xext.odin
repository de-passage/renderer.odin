package x

import "vendor:x11/xlib"
foreign import Xext "system:Xext"

foreign Xext {
  XShmQueryExtension :: proc "c" (display: ^xlib.Display) -> b32 ---

  XShmCreateImage :: proc "c" (display: ^xlib.Display, visual: ^xlib.Visual, depth: u32, format: i32, data: rawptr, shminfo: ^ShmSegmentInfo, width, height: u32) -> ^xlib.XImage ---

  XShmAttach :: proc "c" (display: ^xlib.Display, shminfo: ^ShmSegmentInfo) -> xlib.Status ---
  XShmDetach :: proc "c" (display: ^xlib.Display, shminfo: ^ShmSegmentInfo) -> xlib.Status ---
  XShmPutImage :: proc "c" (display: ^xlib.Display, drawable: xlib.Drawable, gc: xlib.GC, image: ^xlib.XImage, src_x, src_y, dest_x, dest_y: i32, width, height: u32, send_event: b32) -> xlib.Status ---
}

ShmSeg :: distinct xlib.XID

ShmCompletionEvent :: struct {
  type:                   i32,
  serial:                 uint,
  send_event:             b32,
  display:                ^xlib.Display,
  drawable:               xlib.Drawable,
  major_code, minor_code: i32,
  shmseg:                 ShmSeg,
  offset:                 uint,
}

ShmSegmentInfo :: struct {
  shmseg:   ShmSeg,
  shmid:    i32,
  shmaddr:  rawptr,
  readonly: b32,
}
