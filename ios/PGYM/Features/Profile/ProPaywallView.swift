import DesignSystem
import SwiftUI

struct ProPaywallView: View {
    @Environment(AppServices.self) private var services
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedID: String?
    @State private var working = false
    @State private var message: String?

    private var purchases: PurchaseState { services.purchases }
    private var selected: PurchaseOption? {
        purchases.options.first(where: { $0.id == selectedID }) ?? purchases.options.first(where: \.isAnnual) ?? purchases.options.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.grid(5)) {
                    Text("PGYM PRO")
                        .pgymText(.display, size: 54).foregroundStyle(Color.chalk)
                        .accessibilityAddTraits(.isHeader)
                    Text("Turn every session into proof.")
                        .pgymText(.title).foregroundStyle(Color.chalk)
                    benefit("sparkles", "A private, transient AI workout insight")
                    benefit("chart.xyaxis.line", "Full proof history and advanced progress")
                    benefit("link", "Read-only access for your personal agent")

                    if !network.isOnline {
                        InlineNote(text: "You are offline. Logging and proof cards still work.", tone: .info, identifier: "paywall.offline")
                    } else if purchases.phase == .loading && purchases.options.isEmpty {
                        ProgressView("Loading plans…").tint(Color.plate).accessibilityIdentifier("paywall.loading")
                    } else if purchases.options.isEmpty {
                        ErrorCard(message: message ?? "Plans are unavailable right now. Your workouts still work.", retryTitle: "Try again", identifier: "paywall.error") {
                            Task { await purchases.refresh() }
                        }
                    } else {
                        ForEach(purchases.options) { option in optionButton(option) }
                        Button(primaryTitle) { Task { await buy() } }
                            .buttonStyle(.pgymPrimary).disabled(working || selected == nil)
                            .accessibilityIdentifier("paywall.purchase")
                    }

                    HStack {
                        Button("Restore purchases") { Task { await restore() } }
                        Spacer()
                        Button("Terms") { openURL(SiteLinks.terms) }
                        Button("Privacy") { openURL(SiteLinks.privacy) }
                    }
                    .font(.pgym(.bodyMedium, size: 14)).foregroundStyle(Color.bone)
                    .frame(minHeight: Spacing.touchTargetMin)
                }
                .padding(Spacing.screenMargin)
            }
            .background(Color.ink.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).accessibilityLabel("Close Pro plans")
                }
            }
            .task {
                await purchases.refresh()
                selectedID = purchases.options.first(where: \.isAnnual)?.id ?? purchases.options.first?.id
            }
            .accessibilityIdentifier("screen.paywall")
        }
        .preferredColorScheme(.dark)
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Spacing.grid(3)) {
            Image(systemName: icon).foregroundStyle(Color.plate).frame(width: 28).accessibilityHidden(true)
            Text(text).pgymText(.bodyMedium, size: 17).foregroundStyle(Color.chalk)
        }.accessibilityElement(children: .combine)
    }

    private func optionButton(_ option: PurchaseOption) -> some View {
        Button {
            withAnimation(Animation.pgymSpring(reduceMotion: reduceMotion)) { selectedID = option.id }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title).pgymText(.bodyMedium, size: 18).foregroundStyle(Color.chalk)
                    Text([option.localizedPrice, option.localizedPeriod, option.introductoryTerms].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .pgymText(.body, size: 14).foregroundStyle(Color.bone)
                }
                Spacer()
                Image(systemName: selected?.id == option.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected?.id == option.id ? Color.plate : Color.steel).accessibilityHidden(true)
            }
            .padding(Spacing.grid(4))
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(Color.iron))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(selected?.id == option.id ? Color.plate : Color.rail, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title), \(option.localizedPrice), \(option.localizedPeriod)\(option.introductoryTerms.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(selected?.id == option.id ? .isSelected : [])
    }

    private var primaryTitle: String {
        guard let selected else { return "Continue" }
        return selected.introductoryTerms.map { "Start \($0)" } ?? "Continue with \(selected.title)"
    }
    private func buy() async {
        guard let selected else { return }
        working = true; defer { working = false }
        do { try await purchases.purchase(selected); if purchases.isPro { dismiss() } }
        catch PurchaseError.cancelled { }
        catch { message = "The purchase did not complete. Try again when you are ready." }
    }
    private func restore() async {
        working = true; defer { working = false }
        do {
            try await purchases.restore()
            message = purchases.isPro ? "PGYM Pro is restored." : "No active PGYM Pro purchase was found."
        } catch { message = "Restore is unavailable right now. Try again later." }
    }
}
