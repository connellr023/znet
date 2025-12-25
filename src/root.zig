const c = @cImport(@cInclude("enet/enet.h"));
const std = @import("std");

pub const Error = error{
    InitializeFailed,
    SendFailed,
    PacketCreateFailed,
    HostServiceFailed,
    SetAddressHostFailed,
    HostCreateFailed,
    HostConnectFailed,
};

pub const Callbacks = c.ENetCallbacks;

pub const Flags = enum(u32) {
    reliable = c.ENET_PACKET_FLAG_RELIABLE,
    unsequenced = c.ENET_PACKET_FLAG_UNSEQUENCED,
    no_allocate = c.ENET_PACKET_FLAG_NO_ALLOCATE,
    unreliable_fragment = c.ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT,
};

pub const AddressHost = union(enum) {
    any,
    broadcast,
    ipv4: [*:0]const u8,

    fn asENetAddress(self: *const AddressHost) !u32 {
        return switch (self) {
            .any => c.ENET_HOST_ANY,
            .broadcast => c.ENET_HOST_BROADCAST,
            .ipv4 => |ip| {
                var addr = @as(c.ENetAddress, undefined);
                if (c.enet_address_set_host_ip(&addr, ip.ptr) != 0) {
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
            .any => c.ENET_PORT_ANY,
            .specific => |port| port,
        };
    }
};

pub const Address = struct {
    addr: c.ENetAddress,

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
    ptr: *c.ENetPacket,

    pub fn init(data: []const u8, flags: Flags) Error!Packet {
        const packet = c.enet_packet_create(data.ptr, data.len, @intFromEnum(flags));
        if (packet == null) {
            return Error.PacketCreateFailed;
        }

        return .{
            .ptr = packet,
        };
    }

    pub fn deinit(self: *Packet) void {
        c.enet_packet_destroy(self.ptr);
    }

    pub fn dataSlice(self: *const Packet) []const u8 {
        return self.ptr.data[0..self.ptr.dataLength];
    }

    pub fn reader(self: *const Packet) std.io.Reader {
        return std.io.Reader.fixed(self.dataSlice());
    }
};

pub const Host = struct {
    ptr: *c.ENetHost,

    pub fn init(
        address: Address,
        peer_count: usize,
        channel_count: usize,
        incoming_bandwidth: Bandwidth,
        outgoing_bandwidth: Bandwidth,
    ) !Host {
        const host = c.enet_host_create(
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

    pub fn connect(
        self: *Host,
        address: Address,
        channel_count: usize,
        data: u32,
    ) !Peer {
        const peer = c.enet_host_connect(
            self.ptr,
            &address.addr,
            channel_count,
            data,
        );
        if (peer == null) {
            return Error.HostConnectFailed;
        }

        return .{
            .ptr = peer,
        };
    }

    pub fn deinit(self: *Host) void {
        c.enet_host_destroy(self.ptr);
    }

    pub fn service(self: *Host, timeout_ms: i32) Error!?Event {
        var event = @as(c.ENetEvent, undefined);
        if (c.enet_host_service(self.ptr, &event, timeout_ms) < 0) {
            return Error.HostServiceFailed;
        }

        return switch (event.type) {
            c.ENET_EVENT_TYPE_CONNECT => .{
                .connect = .{
                    .peer = .{ .ptr = event.peer },
                    .data = event.data,
                },
            },
            c.ENET_EVENT_TYPE_DISCONNECT => .{
                .disconnect = .{
                    .peer = .{ .ptr = event.peer },
                    .data = event.data,
                },
            },
            c.ENET_EVENT_TYPE_RECEIVE => .{
                .receive = .{
                    .packet = .{ .ptr = event.packet },
                    .channel_id = event.channelID,
                },
            },
            else => null,
        };
    }

    pub fn broadcast(self: *Host, channel_id: u8, packet: *Packet) void {
        c.enet_host_broadcast(self.ptr, channel_id, packet.ptr);
    }
};

pub const PeerState = enum(c.ENetPeerState) {
    disconnected = c.ENET_PEER_STATE_DISCONNECTED,
    connecting = c.ENET_PEER_STATE_CONNECTING,
    acknowledging_connect = c.ENET_PEER_STATE_ACKNOWLEDGING_CONNECT,
    connection_pending = c.ENET_PEER_STATE_CONNECTION_PENDING,
    connection_succeeded = c.ENET_PEER_STATE_CONNECTION_SUCCEEDED,
    connected = c.ENET_PEER_STATE_CONNECTED,
    disconnect_later = c.ENET_PEER_STATE_DISCONNECT_LATER,
    disconnecting = c.ENET_PEER_STATE_DISCONNECTING,
    acknowledging_disconnect = c.ENET_PEER_STATE_ACKNOWLEDGING_DISCONNECT,
    zombie = c.ENET_PEER_STATE_ZOMBIE,
};

pub const Peer = struct {
    ptr: *c.ENetPeer,

    pub fn send(self: *Peer, channel_id: u8, packet: *Packet) Error!void {
        if (c.enet_peer_send(self.ptr, channel_id, packet.ptr) != 0) {
            return Error.SendFailed;
        }
    }

    pub fn dataPtr(self: *Peer) ?*anyopaque {
        return self.ptr.data;
    }

    pub fn state(self: *const Peer) PeerState {
        return @enumFromInt(self.ptr.state);
    }

    pub fn disconnect(self: *Peer, data: u32) void {
        c.enet_peer_disconnect(self.ptr, data);
    }

    pub fn disconnect_later(self: *Peer, data: u32) void {
        c.enet_peer_disconnect_later(self.ptr, data);
    }

    pub fn disconnect_now(self: *Peer, data: u32) void {
        c.enet_peer_disconnect_now(self.ptr, data);
    }

    pub fn reset(self: *Peer) void {
        c.enet_peer_reset(self.ptr);
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
    if (c.enet_initialize() != 0) {
        return Error.InitializeFailed;
    }
}

pub fn init_with_callbacks(callbacks: Callbacks) Error!void {
    if (c.enet_initialize_with_callbacks(c.ENET_VERSION, &callbacks) != 0) {
        return Error.InitializeFailed;
    }
}

pub fn deinit() void {
    c.enet_deinitialize();
}
