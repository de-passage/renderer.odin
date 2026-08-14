package renderer

import "core:mem"
import "core:slice"

Mesh :: struct {
  position:  []Vertex,
  triangles: []Triangle_Index,
}

allocate_mesh :: proc {
  allocate_mesh_non_zeroed,
  allocate_mesh_clone,
}

allocate_mesh_non_zeroed :: proc(
  positions: int,
  triangles: int,
  allocator := context.allocator,
) -> (
  mesh: Mesh,
  err: mem.Allocator_Error,
) {
  raw := mem.alloc(size_of(Vertex) * positions, align_of(Vertex), allocator) or_return
  mesh.position = slice.from_ptr(cast(^Vertex)raw, positions)

  raw, err = mem.alloc(size_of(Triangle_Index) * triangles, align_of(Triangle_Index), allocator)
  if err != .None {
    delete(mesh.position, allocator)
    mesh.position = nil
    return
  }
  mesh.triangles = slice.from_ptr(cast(^Triangle_Index)raw, triangles)
  return
}
allocate_mesh_clone :: proc(
  positions: []Vertex,
  triangles: []Triangle_Index,
  allocator := context.allocator,
) -> (
  mesh: Mesh,
  err: mem.Allocator_Error,
) {
  mesh.position = slice.clone(positions, allocator) or_return
  mesh.triangles, err = slice.clone(triangles, allocator)
  if err != .None {
    delete(mesh.position, allocator)
    mesh.position = nil
    return
  }
  return
}
release_mesh :: proc(mesh: ^Mesh, allocator := context.allocator) {
  delete(mesh.position, allocator)
  delete(mesh.triangles, allocator)
  mesh.position = nil
  mesh.triangles = nil
}
