const znet = @import("root.zig");
const std = @import("std");

test "Initialize" {
    try znet.init();
    defer znet.deinit();
}
