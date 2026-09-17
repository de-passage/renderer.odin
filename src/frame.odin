package renderer

import "core:mem"
import "vendor:x11/xlib"

import "x"

Frame :: struct {
  buffer:       []RGB,
  in_flight:    bool,
  id:           x.ShmSeg,
  shmid:        x.ShmID,
  image:        ^xlib.XImage,
  segment_info: x.SegmentInfo,
}

Frame_Error :: enum {
  NONE,
  SHM_ID_FAILED,
  SHM_ALLOC_FAILED,
  SHM_ATTACH_FAILED,
  SHM_IMAGE_FAILED,
}

init_frame :: proc(frame: ^Frame, height, width: u32, xstate: x.State) -> (err: Frame_Error) {
  // Allocate a shared memory block and get its identifier
  frame_size := height * width
  frame_buffer_byte_size := frame_size * size_of(RGB)
  frame.shmid = x.shmget(
    x.IPC_PRIVATE,
    uintptr(frame_buffer_byte_size),
    x.SHM_R | x.SHM_W | x.IPC_CREAT,
  )
  if frame.shmid == -1 {
    err = .SHM_ID_FAILED
    return
  }

  // Map the shared memory into program virtual address space
  shared_memory := x.shmat(frame.shmid, nil, 0)
  if shared_memory == rawptr(~uintptr(0)) {
    err = .SHM_ALLOC_FAILED
    x.shmctl(frame.shmid, x.IPC_RMID, nil)
    return
  }
  frame.buffer = mem.slice_ptr((^RGB)(shared_memory), int(frame_size)) // Turn it into an Odin object.

  frame.segment_info = x.SegmentInfo {
    shmid    = frame.shmid,
    shmaddr  = shared_memory,
    readonly = false,
  }

  ok := x.Attach(xstate.display, &frame.segment_info)
  if !ok {
    err = .SHM_ATTACH_FAILED
    x.shmdt(shared_memory)
    x.shmctl(frame.shmid, x.IPC_RMID, nil)
    return
  }

  frame.image = x.CreateImage(
    xstate.display,
    xstate.visual,
    u32(xstate.depth),
    .ZPixmap,
    nil,
    &frame.segment_info,
    width,
    height,
  )
  frame.id = frame.segment_info.shmseg
  if frame.image == nil {
    err = .SHM_IMAGE_FAILED
    x.Detach(xstate.display, &frame.segment_info)
    x.shmdt(shared_memory)
    x.shmctl(frame.shmid, x.IPC_RMID, nil)
    return
  }
  frame.image.data = &frame.buffer[0]
  return
}

delete_frame :: proc(frame: ^Frame, state: x.State) {
  if frame.buffer != nil {
    x.Detach(state.display, &frame.segment_info)
  }
  if frame.image != nil {
    xlib.DestroyImage(frame.image)
    frame.image = nil
  }
  if frame.buffer != nil {
    x.shmdt(rawptr(&frame.buffer[0]))
    frame.buffer = nil
  }
  if frame.shmid != -1 {
    x.shmctl(frame.shmid, x.IPC_RMID, nil)
    frame.shmid = -1
  }
}
