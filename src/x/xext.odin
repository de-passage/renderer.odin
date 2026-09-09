package x

import "vendor:x11/xlib"
foreign import "system:Xext"

foreign Xext {
  XshmQueryExtension :: proc "c" (display: ^xlib.Display) -> bool ---
}
