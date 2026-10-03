import SwiftUI

/// Legal and privacy hub.
///
/// Follows the supplied design's structure — a Documents group and a Data Management group —
/// but only lists things this app actually has. Two rows from the design are deliberately
/// absent:
///
/// - **Cookie Policy.** There are no cookies. The project contains no web view and no
///   networking, so a cookie policy would describe behaviour that cannot occur.
/// - **Delete Account.** There is no account to delete. The equivalent real action is deleting
///   the locally saved resume, which is offered below under its own name.
struct LegalAndPrivacyView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    @State private var exportURL: URL?
    @State private var isConfirmingDelete = false
    @State private var savedCount = 0

    private var hasSavedData: Bool { savedCount > 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                group("DOCUMENTS") {
                    row(icon: "doc.text.fill", tint: .indigo, title: "Terms of Service") {
                        router.push(.legalDocument(.terms))
                    }
                    Divider().padding(.leading, 60)
                    row(icon: "lock.shield.fill", tint: .green, title: "Privacy Policy") {
                        router.push(.legalDocument(.privacy))
                    }
                }

                group("DATA MANAGEMENT") {
                    row(
                        icon: "square.and.arrow.down.fill",
                        tint: .indigo,
                        title: "Export my data",
                        subtitle: hasSavedData
                            ? "Everything Rolvexa has stored, as a readable file"
                            : "Nothing stored to export"
                    ) {
                        exportURL = ResumeLibrary.exportForSharing()
                    }
                    .disabled(!hasSavedData)

                    Divider().padding(.leading, 60)

                    // "Delete my saved resumes", not "Delete account" — there is no account, and
                    // naming it that would imply a server-side record that doesn't exist.
                    row(
                        icon: "trash.fill",
                        tint: .red,
                        title: "Delete my saved resumes",
                        subtitle: savedCount == 0
                            ? "Nothing saved on this device"
                            : savedCount == 1
                                ? "Removes the one resume stored on this device"
                                : "Removes all \(savedCount) resumes stored on this device",
                        isDestructive: true
                    ) {
                        isConfirmingDelete = true
                    }
                    .disabled(!hasSavedData)
                }

                footer
            }
            .padding(20)
        }
        .navigationTitle("Legal & Privacy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { savedCount = ResumeLibrary.count }
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .confirmationDialog(
            savedCount == 1 ? "Delete your saved resume?" : "Delete all \(savedCount) saved resumes?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.deleteAllResumes()
                savedCount = 0
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes everything stored on this device. It can't be undone, and there is no copy anywhere else.")
        }
    }

    // MARK: - Pieces

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.appCardBackground)
                )
        }
    }

    private func row(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay { Image(systemName: icon).font(.footnote).foregroundStyle(tint) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(isDestructive ? Color.red : .primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Version comes from the bundle rather than being typed in, so it can't drift from the
    /// build. The design's "v2.4.0" and "© 2024 Rolvexa Technologies Inc." are both replaced:
    /// this is version 1.0, and no such company exists — putting an invented legal entity on a
    /// legal page is exactly the kind of claim this screen is supposed to make checkable.
    private var footer: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        return VStack(spacing: 4) {
            Text("Rolvexa \(version) (\(build))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("An open-source personal project. The source is public and can be read in full.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

#Preview {
    NavigationStack {
        LegalAndPrivacyView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
