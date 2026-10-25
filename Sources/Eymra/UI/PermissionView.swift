import SwiftUI

struct PermissionView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Eymra").font(.largeTitle.bold())
                Text("Pick the photos worth posting from a trip or a night out: one per moment, no repeats, real variety.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Label("Your photos are analysed on this iPhone. Nothing is uploaded unless you turn on AI Judge.",
                  systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            Spacer()
            if app.access == .denied {
                Text("Photo access is off. Turn it on in Settings to continue.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                Button("Open Settings") { app.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button {
                    Task { await app.requestAccess() }
                } label: {
                    Text("Allow photo access").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("allowAccess")
            }
        }
        .padding(24)
    }
}
