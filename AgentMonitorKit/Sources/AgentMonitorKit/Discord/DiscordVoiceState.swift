import Foundation

public struct DiscordVoiceState: Sendable, Equatable {
    public let channelID: String?
    public let channelName: String?
    public let isMuted: Bool
    public let isDeafened: Bool
    public let speakingUserIDs: Set<String>
    public let currentUserID: String?

    public init(
        channelID: String? = nil,
        channelName: String? = nil,
        isMuted: Bool = false,
        isDeafened: Bool = false,
        speakingUserIDs: Set<String> = [],
        currentUserID: String? = nil
    ) {
        self.channelID = channelID
        self.channelName = channelName
        self.isMuted = isMuted
        self.isDeafened = isDeafened
        self.speakingUserIDs = speakingUserIDs
        self.currentUserID = currentUserID
    }

    public var isInVoice: Bool { channelID != nil }
    public var isAnyoneSpeaking: Bool { !speakingUserIDs.isEmpty }
    public var isSelfSpeaking: Bool {
        guard let currentUserID else { return false }
        return speakingUserIDs.contains(currentUserID)
    }
}

public enum DiscordVoiceReducer {
    public static func reducing(_ state: DiscordVoiceState, message: JSONValue) -> DiscordVoiceState {
        if message["evt"]?.stringValue == "ERROR" {
            return state
        }

        let evt = message["evt"]?.stringValue
        let cmd = message["cmd"]?.stringValue
        let data = message["data"]

        if evt == "READY" {
            let userID = data?["user"]?["id"]?.stringValue ?? state.currentUserID
            return DiscordVoiceState(
                channelID: state.channelID,
                channelName: state.channelName,
                isMuted: state.isMuted,
                isDeafened: state.isDeafened,
                speakingUserIDs: state.speakingUserIDs,
                currentUserID: userID
            )
        }

        if cmd == "GET_SELECTED_VOICE_CHANNEL" || evt == "VOICE_CHANNEL_SELECT" {
            guard let data, data != .null else {
                return DiscordVoiceState(
                    channelID: nil,
                    channelName: nil,
                    isMuted: state.isMuted,
                    isDeafened: state.isDeafened,
                    speakingUserIDs: [],
                    currentUserID: state.currentUserID
                )
            }

            let rawChannelID = data["channel_id"]?.stringValue ?? data["id"]?.stringValue
            guard let channelID = rawChannelID, !channelID.isEmpty else {
                return DiscordVoiceState(
                    channelID: nil,
                    channelName: nil,
                    isMuted: state.isMuted,
                    isDeafened: state.isDeafened,
                    speakingUserIDs: [],
                    currentUserID: state.currentUserID
                )
            }

            let nextChannelName = data["name"]?.stringValue
                ?? (channelID == state.channelID ? state.channelName : nil)
            let nextSpeaking = (channelID == state.channelID) ? state.speakingUserIDs : []

            return DiscordVoiceState(
                channelID: channelID,
                channelName: nextChannelName,
                isMuted: state.isMuted,
                isDeafened: state.isDeafened,
                speakingUserIDs: nextSpeaking,
                currentUserID: state.currentUserID
            )
        }

        if cmd == "GET_VOICE_SETTINGS" || cmd == "SET_VOICE_SETTINGS" || evt == "VOICE_SETTINGS_UPDATE" {
            guard let data, data != .null else { return state }
            let muted = data["mute"]?.boolValue ?? state.isMuted
            let deafened = data["deaf"]?.boolValue ?? state.isDeafened
            return DiscordVoiceState(
                channelID: state.channelID,
                channelName: state.channelName,
                isMuted: muted,
                isDeafened: deafened,
                speakingUserIDs: state.speakingUserIDs,
                currentUserID: state.currentUserID
            )
        }

        if evt == "SPEAKING_START", let userID = data?["user_id"]?.stringValue, !userID.isEmpty {
            var nextSpeaking = state.speakingUserIDs
            nextSpeaking.insert(userID)
            return DiscordVoiceState(
                channelID: state.channelID,
                channelName: state.channelName,
                isMuted: state.isMuted,
                isDeafened: state.isDeafened,
                speakingUserIDs: nextSpeaking,
                currentUserID: state.currentUserID
            )
        }

        if evt == "SPEAKING_STOP", let userID = data?["user_id"]?.stringValue {
            var nextSpeaking = state.speakingUserIDs
            nextSpeaking.remove(userID)
            return DiscordVoiceState(
                channelID: state.channelID,
                channelName: state.channelName,
                isMuted: state.isMuted,
                isDeafened: state.isDeafened,
                speakingUserIDs: nextSpeaking,
                currentUserID: state.currentUserID
            )
        }

        return state
    }
}
