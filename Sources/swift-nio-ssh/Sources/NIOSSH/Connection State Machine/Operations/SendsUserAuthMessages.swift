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

protocol SendsUserAuthMessages {
    var userAuthStateMachine: UserAuthenticationStateMachine { get set }

    var serializer: SSHPacketSerializer { get set }

    /// Needed so `writeUserAuthRequest` can flag the parser to read message type
    /// 60 as `UserAuthInfoRequestMessage` rather than `UserAuthPKOKMessage` for the
    /// duration of a keyboard-interactive attempt — see
    /// `UserAuthMethodSpecificMessageHint` in `SSHPacketParser.swift`.
    var parser: SSHPacketParser { get set }
}

extension SendsUserAuthMessages {
    mutating func writeServiceRequest(_ message: SSHMessage.ServiceRequestMessage, into buffer: inout ByteBuffer) throws
    {
        self.userAuthStateMachine.sendServiceRequest(message)
        try self.serializer.serialize(message: .serviceRequest(message), to: &buffer)
    }

    mutating func writeServiceAccept(_ message: SSHMessage.ServiceAcceptMessage, into buffer: inout ByteBuffer) throws {
        self.userAuthStateMachine.sendServiceAccept(message)
        try self.serializer.serialize(message: .serviceAccept(message), to: &buffer)
    }

    mutating func writeUserAuthRequest(
        _ message: SSHMessage.UserAuthRequestMessage,
        into buffer: inout ByteBuffer
    ) throws {
        self.userAuthStateMachine.sendUserAuthRequest(message)

        // Flip how the parser will interpret the next type-60 message for the
        // duration of this attempt — see SendsUserAuthMessages.parser's doc comment.
        if case .keyboardInteractive = message.method {
            self.parser.pendingUserAuthHint = .keyboardInteractiveInfoRequest
        } else {
            self.parser.pendingUserAuthHint = .publicKeyOK
        }

        try self.serializer.serialize(message: .userAuthRequest(message), to: &buffer)
    }

    mutating func writeUserAuthSuccess(into buffer: inout ByteBuffer) throws {
        self.userAuthStateMachine.sendUserAuthSuccess()
        try self.serializer.serialize(message: .userAuthSuccess, to: &buffer)
    }

    mutating func writeUserAuthFailure(
        _ message: SSHMessage.UserAuthFailureMessage,
        into buffer: inout ByteBuffer
    ) throws {
        self.userAuthStateMachine.sendUserAuthFailure(message)
        try self.serializer.serialize(message: .userAuthFailure(message), to: &buffer)
    }

    mutating func writeUserAuthBanner(_ message: SSHMessage.UserAuthBannerMessage, into buffer: inout ByteBuffer) throws
    {
        self.userAuthStateMachine.sendUserAuthBanner(message)
        try self.serializer.serialize(message: .userAuthBanner(message), to: &buffer)
    }

    mutating func writeUserAuthPKOK(_ message: SSHMessage.UserAuthPKOKMessage, into buffer: inout ByteBuffer) throws {
        self.userAuthStateMachine.sendUserAuthPKOK(message)
        try self.serializer.serialize(message: .userAuthPKOK(message), to: &buffer)
    }

    mutating func writeUserAuthInfoResponse(
        _ message: SSHMessage.UserAuthInfoResponseMessage,
        into buffer: inout ByteBuffer
    ) throws {
        self.userAuthStateMachine.sendUserAuthInfoResponse(message)
        try self.serializer.serialize(message: .userAuthInfoResponse(message), to: &buffer)
    }
}
