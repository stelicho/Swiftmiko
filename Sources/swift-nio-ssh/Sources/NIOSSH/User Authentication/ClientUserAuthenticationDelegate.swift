//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

/// A single server-supplied prompt within a keyboard-interactive (RFC 4256) challenge.
public struct KeyboardInteractivePrompt: Sendable {
    /// Text to display to the user.
    public var prompt: String

    /// Whether the user's typed response should be echoed back (`false` for
    /// anything password-shaped).
    public var echo: Bool

    public init(prompt: String, echo: Bool) {
        self.prompt = prompt
        self.echo = echo
    }
}

/// A ``NIOSSHClientUserAuthenticationDelegate`` is an object that can provide a sequence of
/// SSH user authentication methods based on the the acceptable list from the server.
///
/// This protocol defines the interface that will be used by the user authentication state
/// machine to move forward with challenges. Implementers of this protocol are free to take
/// time to actually get responses: for example, for password authentication it is possible
/// that the application would like to provide a user-interactive password prompt. This is
/// enabled by allowing implementers to satisfy a promise, rather than requiring that they
/// synchronously provide a response.
public protocol NIOSSHClientUserAuthenticationDelegate {
    /// Called when ``NIOSSH`` would like to attempt to offer a new authentication method.
    ///
    /// The callback is provided the authentication methods that the server is willing to accept in
    /// `availableMethods`. The delegate needs to provide an authentication offer by completing
    /// `nextChallengePromise`. If no further authentication offers are available (perhaps because the server
    /// has rejected them all) then this promise should be failed, which will terminate connection establishment.
    ///
    /// - parameters:
    ///     - availableMethods: The authentication methods the server is willing to accept.
    ///     - nextChallengePromise: An `EventLoopPromise` to be fulfilled with the next authentication offer.
    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    )

    /// Called after this delegate has offered `.keyboardInteractive` and the server responds with a
    /// challenge (RFC 4256 §3.2) — possibly more than once in a row, if the server needs multiple
    /// rounds (e.g. a EULA acceptance prompt followed, in a separate round, by a password prompt).
    /// The delegate must supply exactly one response per prompt, in order, by completing
    /// `responsePromise`; failing it ends the keyboard-interactive attempt.
    ///
    /// A default implementation is provided that fails `responsePromise`, so delegates that never
    /// offer `.keyboardInteractive` don't need to implement this at all.
    ///
    /// - parameters:
    ///     - name: Challenge title, intended for display.
    ///     - instruction: Free-text instructions covering every prompt in this round.
    ///     - prompts: The prompts to answer, in order.
    ///     - responsePromise: An `EventLoopPromise` to be fulfilled with one response per prompt.
    func nextKeyboardInteractiveChallenge(
        name: String,
        instruction: String,
        prompts: [KeyboardInteractivePrompt],
        responsePromise: EventLoopPromise<[String]>
    )
}

extension NIOSSHClientUserAuthenticationDelegate {
    public func nextKeyboardInteractiveChallenge(
        name: String,
        instruction: String,
        prompts: [KeyboardInteractivePrompt],
        responsePromise: EventLoopPromise<[String]>
    ) {
        responsePromise.fail(
            NIOSSHError.protocolViolation(
                protocolName: "userauth",
                violation: "received a keyboard-interactive challenge but this delegate does not support it"
            )
        )
    }
}
