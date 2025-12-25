const c = @cImport(@cInclude("enet/enet.h"));
const std = @import("std");

/// Error union of potential things that could go wrong when using ZNet.
pub const Error = error{
    InitializeFailed,
    SendFailed,
    PacketCreateFailed,
    HostServiceFailed,
    SetHostIPFailed,
    HostCreateFailed,
    HostConnectFailed,
};

/// Type alias for `ENetCallbacks` struct from ENet.
pub const Callbacks = c.ENetCallbacks;

/// Packet flags mapping to ENet packet flags.
pub const Flags = enum(u32) {
    /// Packet must be received by the target peer and resent until acknowledged.
    reliable = c.ENET_PACKET_FLAG_RELIABLE,
    /// Packet will be sent without regard to sequencing.
    unsequenced = c.ENET_PACKET_FLAG_UNSEQUENCED,
    /// Packet data will not be copied internally; data lifetime must exceed packet lifetime.
    no_allocate = c.ENET_PACKET_FLAG_NO_ALLOCATE,
    /// Packet will be fragmented using unreliable sends if it exceeds the MTU.
    unreliable_fragment = c.ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT,
};

/// Representation of a host IP address.
pub const HostIP = union(enum) {
    /// Any IP address; Maps to `ENET_HOST_ANY`.
    any,
    /// Broadcast IP address; Maps to `ENET_HOST_BROADCAST`.
    broadcast,
    /// IP address as a raw `u32`.
    uint: u32,
    /// IP address in octet representation as a C-string.
    ipv4: [*:0]const u8,

    /// Convert to ENet host IP representation.
    fn asENetHostIP(self: HostIP) !u32 {
        return switch (self) {
            .any => c.ENET_HOST_ANY,
            .broadcast => c.ENET_HOST_BROADCAST,
            .uint => |ip| ip,
            .ipv4 => |cstr| {
                // SAFETY: `enet_address_set_host` sets the host field.
                var addr: c.ENetAddress = undefined;
                if (c.enet_address_set_host(&addr, cstr) != 0) {
                    return Error.SetHostIPFailed;
                }

                return addr.host;
            },
        };
    }
};

/// Representation of a host port.
pub const HostPort = union(enum) {
    /// Any port; Maps to `ENET_PORT_ANY`.
    any,
    /// Specific port number.
    specific: u16,

    /// Convert to ENet port representation.
    fn asENetPort(self: HostPort) u16 {
        return switch (self) {
            .any => c.ENET_PORT_ANY,
            .specific => |port| port,
        };
    }
};

/// Representation of a host address consisting of IP and port.
pub const Address = struct {
    /// Internal ENet address representation.
    inner: c.ENetAddress,

    /// Create an `Address` from a `HostIP` and `HostPort`.
    pub fn init(host: HostIP, port: HostPort) !Address {
        return .{
            .inner = .{
                .host = try host.asENetHostIP(),
                .port = port.asENetPort(),
            },
        };
    }
};

/// Representation of bandwidth limit settings in bytes per second.
pub const BandwidthLimit = union(enum) {
    /// Unlimited bandwidth.
    unlimited,
    /// Specific bandwidth in bytes per second.
    specific: u32,

    /// Convert to ENet bandwidth representation.
    fn asENetBandwidth(self: BandwidthLimit) u32 {
        return switch (self) {
            .unlimited => 0,
            .specific => |bps| bps,
        };
    }
};

/// Representation of `Peer` and `Host` packet channel limits.
pub const ChannelLimit = union(enum) {
    /// Maximum allowed channels; Maps to `ENET_PROTOCOL_MAXIMUM_CHANNEL_COUNT`.
    max,
    /// User-defined specific channel limit.
    specific: usize,

    /// Convert to ENet channel limit representation.
    fn asENetChannelLimit(self: ChannelLimit) usize {
        return switch (self) {
            .max => c.ENET_PROTOCOL_MAXIMUM_CHANNEL_COUNT,
            .specific => |limit| limit,
        };
    }
};

/// Representation of a network packet.
pub const Packet = struct {
    /// Internal pointer to ENet packet.
    ptr: *c.ENetPacket,
    /// Channel ID the packet is associated with.
    channel_id: u8,

    /// Create a new `Packet` from data, channel ID, and flags.
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

    /// Deinitialize the packet and free associated resources.
    /// Accessing the `ptr` member after calling this is UB.
    pub fn deinit(self: Packet) void {
        c.enet_packet_destroy(self.ptr);
    }

    /// Get a slice of the packet's data.
    /// This `Packet`'s lifetime must exceed that of the returned slice.
    pub fn dataSlice(self: *const Packet) []const u8 {
        return self.ptr.data[0..self.ptr.dataLength];
    }

    /// Get a reader for the packet's data.
    /// This `Packet`'s lifetime must exceed that of the returned reader.
    pub fn reader(self: *const Packet) std.io.Reader {
        return std.io.Reader.fixed(self.dataSlice());
    }
};

/// Configuration for initializing a `Host`.
pub const HostConfig = struct {
    /// An optional address to bind the host to.
    /// If `null`, then no peers may connect to the host.
    addr: ?Address,
    /// Maximum number of peers for the host.
    peer_limit: usize,
    /// Maximum number of channels the host can use.
    channel_limit: ChannelLimit,
    /// Incoming bandwidth limit in bytes per second.
    incoming_bandwidth: BandwidthLimit,
    /// Outgoing bandwidth limit in bytes per second.
    outgoing_bandwidth: BandwidthLimit,
};

/// Representation of a network host.
pub const Host = struct {
    /// Internal pointer to ENet host.
    ptr: *c.ENetHost,

    /// Initialize a new `Host` with the given configuration.
    pub fn init(config: HostConfig) !Host {
        const addr = if (config.addr) |addr| &addr.inner else null;
        const host = c.enet_host_create(
            addr,
            config.peer_limit,
            config.channel_limit.asENetChannelLimit(),
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

    /// Connect to a remote peer at the given address.
    pub fn connect(
        self: Host,
        addr: Address,
        channel_limit: ChannelLimit,
        data: u32,
    ) !Peer {
        const peer = c.enet_host_connect(
            self.ptr,
            &addr.inner,
            channel_limit.asENetChannelLimit(),
            data,
        );
        if (peer == null) {
            return Error.HostConnectFailed;
        }

        return .{
            .ptr = peer,
        };
    }

    /// Deinitialize the host and free associated resources.
    /// Accessing the `ptr` member after calling this is UB.
    pub fn deinit(self: Host) void {
        c.enet_host_destroy(self.ptr);
    }

    /// Service the host for events, waiting up to `timeout_ms` milliseconds.
    /// Setting `timeout_ms` to `0` makes this a non-blocking call.
    pub fn service(self: Host, timeout_ms: u32) Error!?Event {
        // SAFETY: `enet_host_service` fills out the event struct
        var event: c.ENetEvent = undefined;
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

    /// Broadcast a `Packet` to all connected peers on the `Packet`'s channel.
    pub fn broadcast(self: Host, packet: Packet) void {
        c.enet_host_broadcast(self.ptr, packet.channel_id, packet.ptr);
    }

    /// Flush all pending outgoing packets to connected peers.
    pub fn flush(self: Host) void {
        c.enet_host_flush(self.ptr);
    }

    /// Get an iterator over all connected peers.
    /// This `Host` must outlive the returned iterator.
    pub fn iterPeers(self: *const Host) PeerIterator {
        return .{
            .peers = self.ptr.peers[0..self.ptr.peerCount],
            .index = 0,
        };
    }
};

/// Lazy iterator over connected peers in a `Host`.
pub const PeerIterator = struct {
    /// Slice over all ENet peers allocated to the host.
    peers: []c.ENetPeer,
    /// Current iteration index.
    index: usize,

    /// Yield the next `Peer` in the iterator, or `null` if iteration is complete.
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

/// Representation of the state of a `Peer`.
/// Maps 1:1 to `ENetPeerState`.
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

/// Representation of a network peer.
pub const Peer = struct {
    /// Internal pointer to ENet peer.
    ptr: *c.ENetPeer,

    /// Send a `Packet` to the peer on the `Packet`'s channel.
    pub fn send(self: Peer, packet: Packet) Error!void {
        if (c.enet_peer_send(self.ptr, packet.channel_id, packet.ptr) != 0) {
            return Error.SendFailed;
        }
    }

    /// Get the current state of the peer.
    pub fn state(self: Peer) PeerState {
        return @enumFromInt(self.ptr.state);
    }

    /// Disconnect the peer, and ensure the peer receives a disconnect notification.
    pub fn disconnect(self: Peer, data: u32) void {
        c.enet_peer_disconnect(self.ptr, data);
    }

    /// Request disconnection of the peer after all outgoing packets are sent.
    pub fn disconnect_later(self: Peer, data: u32) void {
        c.enet_peer_disconnect_later(self.ptr, data);
    }

    /// Immediately terminate the connection to the peer without notification.
    pub fn disconnect_now(self: Peer, data: u32) void {
        c.enet_peer_disconnect_now(self.ptr, data);
    }

    /// Forcefully disconnect a peer and notify the remote peer.
    pub fn reset(self: Peer) void {
        c.enet_peer_reset(self.ptr);
    }
};

/// Representation of an event occurring on a `Host`.
pub const Event = union(enum) {
    /// Connect event emitted when a peer connects to the host.
    connect: struct {
        /// The peer that connected.
        peer: Peer,
        /// Arbitrary user data associated with the connection.
        data: u32,
    },
    /// Disconnect event emitted when a peer disconnects from the host.
    disconnect: struct {
        /// The peer that disconnected.
        peer: Peer,
        /// Arbitrary user data associated with the disconnection.
        data: u32,
    },
    /// Receive event emitted when a packet is received from a peer.
    receive: struct {
        /// The peer that sent the packet.
        peer: Peer,
        /// The received packet.
        /// Ownership of the packet is transferred to the caller.
        packet: Packet,
    },
};

/// Initialize the ENet library.
pub fn init() Error!void {
    if (c.enet_initialize() != 0) {
        return Error.InitializeFailed;
    }
}

/// Initialize the ENet library with custom callbacks.
pub fn init_with_callbacks(callbacks: Callbacks) Error!void {
    if (c.enet_initialize_with_callbacks(c.ENET_VERSION, &callbacks) != 0) {
        return Error.InitializeFailed;
    }
}

/// Deinitialize the ENet library.
pub fn deinit() void {
    c.enet_deinitialize();
}
