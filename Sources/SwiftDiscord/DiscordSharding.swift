// The MIT License (MIT)
// Copyright (c) 2016 Erik Little

// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
// documentation files (the "Software"), to deal in the Software without restriction, including without
// limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
// Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
// Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
// BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

import Dispatch
import Foundation

/// Protocol that represents a sharded gateway connection. This is the top-level protocol for `DiscordEngineSpec` and
/// `DiscordEngine`
public protocol DiscordShard {
    // MARK: Properties

    /// Whether this shard is connected to the gateway
    var connected: Bool { get }

    /// A reference to the manager
    weak var manager: DiscordShardManager? { get set }

    /// The total number of shards.
    var numShards: Int { get }

    /// This shard's number.
    var shardNum: Int { get }

    // MARK: Methods

    /**
        Starts the connection to the Discord gateway.
    */
    func connect()

    /**
        Disconnects the engine. An `engine.disconnect` is fired on disconnection.
    */
    func disconnect()

    /**
        Sends a gateway payload to Discord.

        - parameter payload: The payload object.
    */
    func sendGatewayPayload(_ payload: DiscordGatewayPayload)
}

/**
    The shard manager is responsible for a client's shards. It decides when a client is considered connected.
    Connected being when all shards have recieved a ready event and are receiving events from the gateway. It also
    decides when a client has fully disconnected. Disconnected being when all shards have closed.
*/
public class DiscordShardManager {
    // MARK: Properties

    /// - returns: The `n`th shard.
    public subscript(n: Int) -> DiscordShard {
        return shards[n]
    }

    /// The individual shards.
    public var shards = [DiscordShard]()

    private let shardQueue = DispatchQueue(label: "shardQueue")

    private weak var client: DiscordClientSpec?
    private var closed = false
    private var closedShards = 0
    private var connectedShards = 0

    init(client: DiscordClientSpec) {
        self.client = client
    }

    // MARK: Methods

    /**
        Connects all shards to the gateway.

        **Note** This method is an async method.
    */
    public func connect() {
        closed = false

        DispatchQueue.global().async {[shards = self.shards] in
            for shard in shards {
                guard !self.closed else { break }

                shard.connect()

                Thread.sleep(forTimeInterval: 5.0)
            }
        }
    }

    /**
        Disconnects all shards.
    */
    public func disconnect() {
        func _disconnect() {
            closed = true

            for shard in shards {
                shard.disconnect()
            }

            if connectedShards != shards.count {
                // Still connecting, say we disconnected, since we never connected to begin with
                client?.handleEvent("shardManager.disconnect", with: [])
            }
        }

        shardQueue.async(execute: _disconnect)
    }

    /**
        Sends a payload on the specified shard.

        - parameter payload: The payload to send.
        - parameter onShard: The shard to send the payload on.
    */
    public func sendPayload(_ payload: DiscordGatewayPayload, onShard shard: Int) {
        self[shard].sendGatewayPayload(payload)
    }

    /**
        Creates the shards for this manager.

        - parameter into: The number of shards to create.
    */
    public func shatter(into numberOfShards: Int) {
        guard let client = self.client else { return }

        DefaultDiscordLogger.Logger.verbose("Shattering into %@ shards", type: "DiscordShardManager",
            args: numberOfShards)

        shards.removeAll()
        closedShards = 0
        connectedShards = 0

        for i in 0..<numberOfShards {
            let engine = DiscordEngine(client: client, shardNum: i, numShards: numberOfShards)

            engine.manager = self

            shards.append(engine)
        }
    }

    /**
        Used by shards to signal that they have connected.

        - parameter shardNum: The number of the shard that disconnected.
    */
    public func signalShardConnected(shardNum: Int) {
        func _signalShardConnected() {
            connectedShards += 1

            guard connectedShards == shards.count else { return }

            client?.handleEvent("shardManager.connect", with: [])
        }

        shardQueue.async(execute: _signalShardConnected)
    }

    /**
        Used by shards to signal that they have disconnected

        - parameter shardNum: The number of the shard that disconnected.
    */
    public func signalShardDisconnected(shardNum: Int) {
        func _signalShardDisconnected() {
            closedShards += 1

            guard closedShards == shards.count else { return }

            client?.handleEvent("shardManager.disconnect", with: [])
        }

        shardQueue.async(execute: _signalShardDisconnected)
    }
}
