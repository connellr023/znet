# ZNet

> Reliable UDP networking from **ENet** wrapped in **Zig**.

![Zig](https://img.shields.io/badge/Zig-%23F7A41D.svg?style=for-the-badge&logo=zig&logoColor=white)
![C](https://img.shields.io/badge/c-%2300599C.svg?style=for-the-badge&logo=c&logoColor=white)

**ZNet** is a **Zig** binding for [ENet](http://enet.bespin.org/), a reliable UDP networking library. It provides a type-safe, idiomatic **Zig** interface for building high-performance networked applications with optional reliability guarantees.

<!-- prettier-ignore -->
> [!NOTE]
> **ZNet** is not a complete binding of **ENet**, but it covers the essential APIs needed for typical networking use cases.

## Installation

Add **ZNet** to your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/connellr023/znet
```

Then in your `build.zig`, add ZNet as a dependency:

```zig
/// ...

const znet_dep = b.dependency("znet", .{
    .target = target,
    .optimize = optimize,
});
const znet_mod = znet_dep.module("znet");
const znet_artifact = znet_dep.artifact("znet");

/// ...

exe.root_module.addImport(znet_mod);
exe.linkLibrary(znet_artifact);
```

## Usage

### Basic Server

```zig
const znet = @import("znet");

pub fn main() !void {
    try znet.init();
    defer znet.deinit();

    const host = try znet.Host.init(.{
        .addr = try .init(.{
            .ip = .any,
            .port = .{ .uint = 5000 },
        }),
        .peer_limit = 32,
        .channel_limit = .max,
        .incoming_bandwidth = .unlimited,
        .outgoing_bandwidth = .unlimited,
    });

    // Service events
    while (try host.service(500)) |event| switch (event) {
        .connect => |data| {
            // Handle connection
        },
        .disconnect => |data| {
            // Handle disconnection
        },
        .receive => |data| {
            // Handle received packet
            defer data.packet.deinit();
        },
    };
}
```

### Basic Client

```zig
const znet = @import("znet");

pub fn main() !void {
    try znet.init();
    defer znet.deinit();

    const host = try znet.Host.init(.{
        .addr = null,
        .peer_limit = 1,
        .channel_limit = .max,
        .incoming_bandwidth = .unlimited,
        .outgoing_bandwidth = .unlimited,
    });
    defer host.deinit();

    const peer = try host.connect(.{
        .addr = try .init(.{
            .ip = .{ .ipv4 = "127.0.0.1" },
            .port = .{ .uint = 5000 },
        }),
        .channel_limit = .max,
        .data = 0,
    });

    // Send reliable packet
    var packet = try znet.Packet.init("Hello, Server!", 0, .reliable);
    try peer.send(packet);

    // Service events
    while (try host.service(500)) |event| switch (event) {
        .connect => |data| {
            // Handle connection
        },
        .disconnect => |data| {
            // Handle disconnection
        },
        .receive => |data| {
            // Handle received packet
            defer data.packet.deinit();
        },
    };
}
```

## Features

- **Type-safe ENet bindings** with **Zig**'s error handling
- **Flexible address and port configuration** via union types
- **Packet flags** for reliability and fragmentation control
- **Bandwidth limiting** and channel management
- **Peer state tracking** and event-driven architecture

## Contributing

Contributions are welcome! Feel free to submit issues, fork the repository, and create pull requests.

## License

MIT
