const znet = @import("root.zig");

test "Initialize" {
    try znet.init();
    defer znet.deinit();
}
