package x

import "vendor:x11/xlib"

foreign import Xext "system:Xext"

@(default_calling_convention = "c", link_prefix = "XShm")
foreign Xext {
  QueryExtension :: proc "c" (display: ^xlib.Display) -> b32 ---

  CreateImage :: proc "c" (display: ^xlib.Display, visual: ^xlib.Visual, depth: u32, format: xlib.ImageFormat, data: rawptr, shminfo: ^SegmentInfo, width, height: u32) -> ^xlib.XImage ---

  Attach :: proc "c" (display: ^xlib.Display, shminfo: ^SegmentInfo) -> b32 ---
  Detach :: proc "c" (display: ^xlib.Display, shminfo: ^SegmentInfo) -> xlib.Status ---
  PutImage :: proc "c" (display: ^xlib.Display, drawable: xlib.Drawable, gc: xlib.GC, image: ^xlib.XImage, src_x, src_y, dest_x, dest_y: i32, width, height: u32, send_event: b32) -> xlib.Status ---
  GetEventBase :: proc "c" (display: ^xlib.Display) -> i32 ---
}

ShmSeg :: distinct xlib.XID

CompletionEvent :: struct {
  type:                   i32,
  serial:                 uint,
  send_event:             b32,
  display:                ^xlib.Display,
  drawable:               xlib.Drawable,
  major_code, minor_code: i32,
  shmseg:                 ShmSeg,
  offset:                 uint,
}

SegmentInfo :: struct {
  shmseg:   ShmSeg,
  shmid:    ShmID,
  shmaddr:  rawptr,
  readonly: b32,
}

foreign import libc "system:c"
@(default_calling_convention = "c")
foreign libc {
  shmget :: proc(key: i32, size: uintptr, shmflg: i32) -> ShmID ---
  shmat :: proc(shmid: ShmID, shmaddr: rawptr, shmflg: i32) -> rawptr ---
  shmdt :: proc(shmaddr: rawptr) -> i32 ---
  shmctl :: proc(shmid: ShmID, cmd: i32, buf: ^ShmId_Ds) -> i32 ---
}

ShmID :: distinct i32
ShmId_Ds :: struct {}

IPC_RMID :: 0
IPC_PRIVATE :: 0
IPC_SET :: 1
IPC_STAT :: 2
IPC_CREAT :: 0o1000
IPC_EXCL :: 0o2000
IPC_NOWAIT :: 0o4000

SHM_R :: 0o400
SHM_W :: 0o200
SHM_RDONLY :: 0o10000
SHM_RND :: 0o20000
SHM_REMAP :: 0o40000
SHM_EXEC :: 0o100000
SHM_LOCK :: 11
SHM_UNLOCK :: 12
