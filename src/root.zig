const c = @cImport(@cInclude("enet/enet.h"));
const std = @import("std");

pub const Error = error{
    InitializeFailed,
    SendFailed,
    PacketCreateFailed,
    HostServiceFailed,
    SetHostIPFailed,
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

pub const HostIP = union(enum) {
    any,
    broadcast,
    ipv4: [*:0]const u8,

    fn asENetHostIP(self: *const HostIP) !u32 {
        return switch (self.*) {
            .any => c.ENET_HOST_ANY,
            .broadcast => c.ENET_HOST_BROADCAST,
            .ipv4 => |ip| {
                var addr = @as(c.ENetAddress, undefined);
                if (c.enet_address_set_host(&addr, ip) != 0) {
                    return Error.SetHostIPFailed;
                }

                return addr.host;
            },
        };
    }
};

pub const HostPort = union(enum) {
    any,
    specific: u16,

    fn asENetPort(self: *const HostPort) u16 {
        return switch (self.*) {
            .any => c.ENET_PORT_ANY,
            .specific => |port| port,
        };
    }
};

pub const Address = struct {
    inner: c.ENetAddress,

    pub fn init(host: HostIP, port: HostPort) !Address {
        return .{
            .inner = .{
                .host = try host.asENetHostIP(),
                .port = port.asENetPort(),
            },
        };
    }
};

pub const Bandwidth = union(enum) {
    unlimited,
    specific: u32,

    fn asENetBandwidth(self: *const Bandwidth) u32 {
        return switch (self.*) {
            .unlimited => 0,
            .specific => |bw| bw,
        };
    }
};

pub const Packet = struct {
    ptr: *c.ENetPacket,
    channel_id: u8,

    pub fn init(data: []const u8, channel_id: u8, flags: Flags) Error!Packet {
        const packet = c.enet_packet_create(data.ptr, data.len, @intFromEnum(flags));
        if (packet == null) {
            return Error.PacketCreateFailed;
        }

        return .{
            .ptr = packet,
            .channel_id = channel_id,
        };
    }

    pub fn deinit(self: *const Packet) void {
        c.enet_packet_destroy(self.ptr);
    }

    pub fn dataSlice(self: *const Packet) []const u8 {
        return self.ptr.data[0..self.ptr.dataLength];
    }

    pub fn reader(self: *const Packet) std.io.Reader {
        return std.io.Reader.fixed(self.dataSlice());
    }
};

pub const HostConfig = struct {
    addr: ?Address,
    peer_count: usize,
    channel_count: usize,
    incoming_bandwidth: Bandwidth,
    outgoing_bandwidth: Bandwidth,
};

pub const Host = struct {
    ptr: *c.ENetHost,

    pub fn init(config: HostConfig) !Host {
        const addr = if (config.addr) |addr| &addr.inner else null;
        const host = c.enet_host_create(
            addr,
            config.peer_count,
            config.channel_count,
            config.incoming_bandwidth.asENetBandwidth(),
            config.outgoing_bandwidth.asENetBandwidth(),
        );

        if (host == null) {
            return Error.HostCreateFailed;
        }

        return .{
            .ptr = host,
        };
    }

    pub fn connect(
        self: *const Host,
        addr: Address,
        channel_count: usize,
        data: u32,
    ) !Peer {
        const peer = c.enet_host_connect(
            self.ptr,
            &addr.inner,
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

    pub fn deinit(self: *const Host) void {
        c.enet_host_destroy(self.ptr);
    }

    pub fn service(self: *const Host, timeout_ms: u32) Error!?Event {
        var event = @as(c.ENetEvent, undefined);
        if (c.enet_host_service(self.ptr, &event, timeout_ms) < 0) {
            return Error.HostServiceFailed;
        }

        return switch (event.type) {
            c.ENET_EVENT_TYPE_CONNECT => .{
                .connect = .{
                    .peer = .{
                        .ptr = event.peer,
                    },
                    .data = event.data,
                },
            },
            c.ENET_EVENT_TYPE_DISCONNECT => .{
                .disconnect = .{
                    .peer = .{
                        .ptr = event.peer,
                    },
                    .data = event.data,
                },
            },
            c.ENET_EVENT_TYPE_RECEIVE => .{
                .receive = .{
                    .peer = .{
                        .ptr = event.peer,
                    },
                    .packet = .{
                        .ptr = event.packet,
                        .channel_id = event.channelID,
                    },
                },
            },
            else => null,
        };
    }

    pub fn broadcast(self: *const Host, packet: Packet) void {
        c.enet_host_broadcast(self.ptr, packet.channel_id, packet.ptr);
    }

    pub fn flush(self: *const Host) void {
        c.enet_host_flush(self.ptr);
    }

    pub fn iterPeers(self: *const Host) PeerIterator {
        return .{
            .peers = self.ptr.peers[0..self.ptr.peerCount],
            .index = 0,
        };
    }
};

pub const PeerIterator = struct {
    peers: []c.ENetPeer,
    index: usize,

    pub fn next(self: *PeerIterator) ?Peer {
        if (self.index >= self.peers.len) {
            return null;
        }

        const index = self.index;
        self.index += 1;

        return .{
            .ptr = &self.peers[index],
        };
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

    pub fn send(self: *const Peer, packet: Packet) Error!void {
        if (c.enet_peer_send(self.ptr, packet.channel_id, packet.ptr) != 0) {
            return Error.SendFailed;
        }
    }

    pub fn state(self: *const Peer) PeerState {
        return @enumFromInt(self.ptr.state);
    }

    pub fn disconnect(self: *const Peer, data: u32) void {
        c.enet_peer_disconnect(self.ptr, data);
    }

    pub fn disconnect_later(self: *const Peer, data: u32) void {
        c.enet_peer_disconnect_later(self.ptr, data);
    }

    pub fn disconnect_now(self: *const Peer, data: u32) void {
        c.enet_peer_disconnect_now(self.ptr, data);
    }

    pub fn reset(self: *const Peer) void {
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
        peer: Peer,
        packet: Packet,
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
