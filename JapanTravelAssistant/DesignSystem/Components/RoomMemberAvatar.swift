import SwiftUI

/// 成員頭像：圓圈裡放名字的第一個字，下面是名字。房主有星星。
struct RoomMemberAvatar: View {
    let member: RoomMember
    var isMe: Bool = false

    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]

    private var color: Color {
        let index = abs(member.id.hashValue) % Self.palette.count
        return Self.palette[index]
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Text(String(member.displayName.prefix(1)))
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color, in: Circle())
                if member.isHost {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(3)
                        .background(Color.white, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
            Text(isMe && member.displayName != "我" ? "\(member.displayName)（我）" : member.displayName)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)
        }
        .frame(minWidth: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(member.displayName)\(member.isHost ? "，房主" : "")\(isMe ? "，就是我" : "")")
    }
}

#Preview {
    HStack(spacing: 12) {
        RoomMemberAvatar(member: RoomMember(roomId: UUID(), userId: UUID(), displayName: "我", isHost: true), isMe: true)
        RoomMemberAvatar(member: RoomMember(roomId: UUID(), userId: UUID(), displayName: "媽媽"))
        RoomMemberAvatar(member: RoomMember(roomId: UUID(), userId: UUID(), displayName: "爸爸"))
    }
    .padding()
}
