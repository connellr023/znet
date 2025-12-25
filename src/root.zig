const cdefs = @cImport(@cInclude("enet/enet.h"));
const std = @import("std");

pub const Error = error{
    InitializeFailed,
    SendFailed,
    PacketCreateFailed,
    HostServiceFailed,
    SetAddressHostFailed,
    HostCreateFailed,
};

pub const Callbacks = cdefs.ENetCallbacks;

pub const Flags = enum(u32) {
    reliable = cdefs.ENET_PACKET_FLAG_RELIABLE,
    unsequenced = cdefs.ENET_PACKET_FLAG_UNSEQUENCED,
    no_allocate = cdefs.ENET_PACKET_FLAG_NO_ALLOCATE,
    unreliable_fragment = cdefs.ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT,
};

pub const AddressHost = union(enum) {
    any,
    broadcast,
    ipv4: [*:0]const u8,

    fn asENetAddress(self: *const AddressHost) !u32 {
        return switch (self) {
            .any => cdefs.ENET_HOST_ANY,
            .broadcast => cdefs.ENET_HOST_BROADCAST,
            .ipv4 => |ip| {
                var addr = @as(cdefs.ENetAddress, undefined);
                if (cdefs.enet_address_set_host_ip(&addr, ip.ptr) != 0) {
                    return Error.SetAddressHostFailed;
                }

                return addr.host;
            },
        };
    }
};

pub const AddressPort = union(enum) {
    any,
    specific: u16,

    fn asENetPort(self: *const AddressPort) u16 {
        return switch (self) {
            .any => cdefs.ENET_PORT_ANY,
            .specific => |port| port,
        };
    }
};

pub const Address = struct {
    addr: cdefs.ENetAddress,

    pub fn init(host: AddressHost, port: AddressPort) !Address {
        return .{
            .addr = .{
                .host = try host.asENetAddress(),
                .port = port.asENetPort(),
            },
        };
    }
};

pub const Bandwidth = union(enum) {
    unlimited,
    specific: u32,

    fn asENetBandwidth(self: *const Bandwidth) u32 {
        return switch (self) {
            .unlimited => 0,
            .specific => |bw| bw,
        };
    }
};

pub const Packet = struct {
    ptr: *cdefs.ENetPacket,

    pub fn init(data: [*]const u8, flags: Flags) Error!Packet {
        const packet = cdefs.enet_packet_create(data.ptr, data.len, @intFromEnum(flags));
        if (packet == null) {
            return Error.PacketCreateFailed;
        }

        return .{
            .ptr = packet,
        };
    }

    pub fn deinit(self: *Packet) void {
        cdefs.enet_packet_destroy(self.ptr);
    }
};

pub const Host = struct {
    ptr: *cdefs.ENetHost,

    pub fn init(
        address: Address,
        peer_count: usize,
        channel_count: usize,
        incoming_bandwidth: Bandwidth,
        outgoing_bandwidth: Bandwidth,
    ) !Host {
        const host = cdefs.enet_host_create(
            &address.addr,
            peer_count,
            channel_count,
            incoming_bandwidth.asENetBandwidth(),
            outgoing_bandwidth.asENetBandwidth(),
        );
        if (host == null) {
            return Error.HostCreateFailed;
        }

        return .{
            .ptr = host,
        };
    }

    pub fn deinit(self: *Host) void {
        cdefs.enet_host_destroy(self.ptr);
    }

    pub fn service(self: *Host, timeout_ms: i32) Error!?Event {
        var event = @as(cdefs.ENetEvent, undefined);
        if (cdefs.enet_host_service(self.ptr, &event, timeout_ms) < 0) {
            return Error.HostServiceFailed;
        }

        return switch (event.type) {
            cdefs.ENET_EVENT_TYPE_CONNECT => .{
                .connect = .{
                    .peer = .{ .ptr = event.peer },
                    .data = event.data,
                },
            },
            cdefs.ENET_EVENT_TYPE_DISCONNECT => .{
                .disconnect = .{
                    .peer = .{ .ptr = event.peer },
                    .data = event.data,
                },
            },
            cdefs.ENET_EVENT_TYPE_RECEIVE => .{
                .receive = .{
                    .packet = .{ .ptr = event.packet },
                    .channel_id = event.channelID,
                },
            },
            else => null,
        };
    }
};

pub const Peer = struct {
    ptr: *cdefs.ENetPeer,

    pub fn send(self: *Peer, channel_id: u8, packet: Packet) Error!void {
        if (cdefs.enet_peer_send(self.ptr, channel_id, packet.ptr) != 0) {
            return Error.SendFailed;
        }
    }

    pub fn disconnect(self: *Peer, data: u32) void {
        cdefs.enet_peer_disconnect(self.ptr, data);
    }

    pub fn disconnect_later(self: *Peer, data: u32) void {
        cdefs.enet_peer_disconnect_later(self.ptr, data);
    }

    pub fn disconnect_now(self: *Peer, data: u32) void {
        cdefs.enet_peer_disconnect_now(self.ptr, data);
    }

    pub fn reset(self: *Peer) void {
        cdefs.enet_peer_reset(self.ptr);
    }
};

pub const Event = union(enum) {
    connect: struct {
        peer: Peer,
        data: u32,
    },
    disconnect: struct {
        peer: Peer,
        data: u32,
    },
    receive: struct {
        packet: Packet,
        channel_id: u8,
    },
};

pub fn init() Error!void {
    if (cdefs.enet_initialize() != 0) {
        return Error.InitializeFailed;
    }
}

pub fn init_with_callbacks(callbacks: *const Callbacks) Error!void {
    if (cdefs.enet_initialize_with_callbacks(cdefs.ENET_VERSION, callbacks) != 0) {
        return Error.InitializeFailed;
    }
}

pub fn deinit() void {
    cdefs.enet_deinitialize();
}
