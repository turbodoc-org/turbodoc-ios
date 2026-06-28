import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authService: AuthenticationService
    @State private var showingSignOutAlert = false
    @State private var showingAbout = false
    @State private var stats: APIUserStats?
    @State private var memberSince: Date?
    @State private var isLoadingStats = false
    @State private var statsErrorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    profileHeader
                    statsSection
                    accountSection
                    supportSection
                    signOutButton
                }
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .refreshable {
                await fetchStats()
            }
            .onAppear {
                if stats == nil { fetchStats() }
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                if let user = authService.currentUser {
                    Text(user.name ?? user.email.components(separatedBy: "@").first ?? "User")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(user.email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("User")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("YOUR LIBRARY")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                if isLoadingStats {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                StatCard(
                    icon: "bookmark.fill",
                    tint: .blue,
                    title: "Bookmarks",
                    value: stats?.bookmark_count
                )
                StatCard(
                    icon: "note.text",
                    tint: .orange,
                    title: "Notes",
                    value: stats?.note_count
                )
                StatCard(
                    icon: "tag.fill",
                    tint: .green,
                    title: "Tags",
                    value: stats?.tag_count
                )
                StatCard(
                    icon: "star.fill",
                    tint: .yellow,
                    title: "Favorites",
                    value: stats?.favorite_count
                )
            }
            .padding(.horizontal, 20)

            if let statsErrorMessage = statsErrorMessage, stats == nil {
                Text(statsErrorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ACCOUNT")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                SettingsRow(
                    icon: "calendar",
                    title: "Member Since",
                    subtitle: memberSinceFormatted,
                    showChevron: false
                ) {}
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
        .padding(.horizontal, 20)
    }

    private var memberSinceFormatted: String {
        if let date = memberSince {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        if let user = authService.currentUser {
            return user.createdAt.formatted(date: .abbreviated, time: .omitted)
        }
        return "—"
    }

    // MARK: - Support

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SUPPORT")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                SettingsRow(
                    icon: "info.circle",
                    title: "About",
                    subtitle: "Version info and legal",
                    showChevron: true
                ) {
                    showingAbout = true
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button {
            showingSignOutAlert = true
        } label: {
            HStack {
                Image(systemName: "arrow.right.square")
                Text("Sign Out")
                    .fontWeight(.medium)
            }
            .foregroundColor(.red)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func fetchStats() {
        guard let userId = authService.currentUser?.id else { return }
        isLoadingStats = true
        statsErrorMessage = nil
        Task {
            do {
                let fetched = try await APIService.shared.getUserStats(userId: userId)
                await MainActor.run {
                    self.stats = fetched
                    self.memberSince = parseISODate(fetched.member_since)
                    self.isLoadingStats = false
                }
            } catch {
                await MainActor.run {
                    self.statsErrorMessage = "Couldn't load stats. Pull to retry."
                    self.isLoadingStats = false
                }
            }
        }
    }

    private func parseISODate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        // Supabase sometimes returns sub-second precision in non-standard ISO.
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        return fallback.date(from: string)
    }

    private func signOut() {
        Task {
            do {
                try await authService.signOut()
            } catch {
                // Error is handled in AuthenticationService
            }
        }
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: Int?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(value.map { String($0) } ?? "—")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let showChevron: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    // App Icon
                    AppIconView()
                        .frame(width: 80, height: 80)

                    Text("Turbodoc")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 16) {
                    Text("About Turbodoc")
                        .font(.headline)

                    Text("Turbodoc helps you save, organize, and search through your bookmarks across all your devices. Keep your important links, articles, and resources organized in one place.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)

                Spacer()

                VStack(spacing: 12) {
                    Text("© 2024 Turbodoc")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 20) {
                        Button("Privacy Policy") {
                            if let url = URL(string: "https://turbodoc.ai/privacy") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption)

                        Button("Terms of Service") {
                            if let url = URL(string: "https://turbodoc.ai/terms") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AppIconView: View {
    var body: some View {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last,
           let image = UIImage(named: lastIcon) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if let image = UIImage(named: "AppIcon") {
            // Try direct AppIcon name
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            // Final fallback to styled SF Symbol
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue)

                Image(systemName: "bookmark")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.white)
            }
        }
    }
}
