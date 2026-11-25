import DesignSystem
import SwiftUI

struct AgentAccessScreen: View {
    @Environment(AppSession.self) private var session
    @Environment(AppServices.self) private var services
    @State private var token: AgentToken?
    @State private var loading = false
    @State private var error: String?
    @State private var paywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.grid(5)) {
                ScreenTitle(text: "Agent access", size: 44)
                Text("Give your personal agent read-only access to your workouts, stats and streak. Photos and AI insight are never included.")
                    .pgymText(.body, size: 17).foregroundStyle(Color.bone)
                if !services.purchases.canUse(.agentAccess) {
                    InlineNote(text: "Agent access is part of PGYM Pro.", tone: .info, identifier: "agent.pro")
                    Button("See PGYM Pro") { paywall = true }.buttonStyle(.pgymPrimary)
                } else if let token {
                    Text("COPY THIS TOKEN NOW").pgymText(.label).foregroundStyle(Color.steel)
                    Text(token.token).font(.pgym(.data, size: 13)).foregroundStyle(Color.chalk)
                        .textSelection(.enabled).padding(Spacing.grid(4))
                        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.iron))
                        .accessibilityLabel("Personal agent token. Copy it now; it will not be shown again.")
                    Text("It expires in 90 days and cannot change your PGYM data.").pgymText(.body, size: 14).foregroundStyle(Color.bone)
                    Button("Revoke token", role: .destructive) { Task { await revoke(token) } }.buttonStyle(.pgymSecondary)
                } else {
                    Button("Create read-only token") { Task { await create() } }.buttonStyle(.pgymPrimary).disabled(loading)
                }
                if let error { InlineNote(text: error, tone: .info, identifier: "agent.error") }
            }.padding(Spacing.screenMargin)
        }
        .background(Color.ink.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $paywall) { ProPaywallView() }
        .accessibilityIdentifier("screen.agentAccess")
    }

    private var api: AgentTokenAPI { AgentTokenAPI(client: HTTPSClient.live(tokenProvider: session.auth.asTokenProvider())) }
    private func create() async {
        loading = true; defer { loading = false }
        do { token = try await api.create(); error = nil }
        catch { self.error = "A token could not be created. Check your connection and try again." }
    }
    private func revoke(_ token: AgentToken) async {
        loading = true; defer { loading = false }
        do { try await api.revoke(id: token.tokenId); self.token = nil }
        catch { self.error = "The token could not be revoked. Try again." }
    }
}
