import Foundation
import Testing
@testable import AgentMonitorKit

private func decode(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

@Test func reducesReadyChannelJoinMoveLeaveAndSpeaking() throws {
    var state = DiscordVoiceState()

    state = DiscordVoiceReducer.reducing(state, message: try decode(#"{"evt":"READY","data":{"user":{"id":"u1"}}}"#))
    #expect(state.currentUserID == "u1")

    state = DiscordVoiceReducer.reducing(
        state,
        message: try decode(#"{"cmd":"GET_SELECTED_VOICE_CHANNEL","data":{"id":"c1","name":"General Voice"}}"#)
    )
    #expect(state.isInVoice)
    #expect(state.channelID == "c1")
    #expect(state.channelName == "General Voice")

    state = DiscordVoiceReducer.reducing(state, message: try decode(#"{"evt":"SPEAKING_START","data":{"user_id":"u1"}}"#))
    state = DiscordVoiceReducer.reducing(state, message: try decode(#"{"evt":"SPEAKING_START","data":{"user_id":"u2"}}"#))
    #expect(state.isAnyoneSpeaking)
    #expect(state.isSelfSpeaking)

    state = DiscordVoiceReducer.reducing(state, message: try decode(#"{"evt":"SPEAKING_STOP","data":{"user_id":"u1"}}"#))
    #expect(state.isAnyoneSpeaking)
    #expect(!state.isSelfSpeaking)

    // Switching channel clears old speaking users
    state = DiscordVoiceReducer.reducing(
        state,
        message: try decode(#"{"evt":"VOICE_CHANNEL_SELECT","data":{"channel_id":"c2","name":"Lounge"}}"#)
    )
    #expect(state.channelID == "c2")
    #expect(state.channelName == "Lounge")
    #expect(!state.isAnyoneSpeaking)

    // Leaving channel (null channel_id or null data)
    state = DiscordVoiceReducer.reducing(
        state,
        message: try decode(#"{"evt":"VOICE_CHANNEL_SELECT","data":{"channel_id":null}}"#)
    )
    #expect(!state.isInVoice)
    #expect(state.channelName == nil)
}

@Test func reducesVoiceSettingsAndNullData() throws {
    var state = DiscordVoiceState(channelID: "c1", channelName: "Room", speakingUserIDs: ["u2"])

    state = DiscordVoiceReducer.reducing(
        state,
        message: try decode(#"{"cmd":"GET_VOICE_SETTINGS","data":{"mute":true,"deaf":false}}"#)
    )
    #expect(state.isMuted)
    #expect(!state.isDeafened)

    state = DiscordVoiceReducer.reducing(
        state,
        message: try decode(#"{"evt":"VOICE_SETTINGS_UPDATE","data":{"mute":true,"deaf":true}}"#)
    )
    #expect(state.isMuted)
    #expect(state.isDeafened)

    state = DiscordVoiceReducer.reducing(
        state,
        message: try decode(#"{"cmd":"GET_SELECTED_VOICE_CHANNEL","data":null}"#)
    )
    #expect(!state.isInVoice)
    #expect(state.speakingUserIDs.isEmpty)
}
