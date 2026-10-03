import SwiftUI

/// Privacy and terms, written from what the app verifiably does rather than from boilerplate.
///
/// Every factual claim here is checkable against the source: there is no networking code in the
/// project, drafts are written with complete file protection, and the language model is Apple's
/// own on-device one. Nothing in this screen describes behaviour the app doesn't have.
///
/// The contact and governing-law lines are deliberately left as placeholders rather than
/// invented — see `contactPlaceholder`.
struct PrivacyAndTermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section(
                    "What Rolvexa collects",
                    body: """
                    Nothing. Rolvexa has no account system, no analytics, no crash reporting and \
                    no servers. It never asks who you are.
                    """
                )

                section(
                    "Where your resume goes",
                    body: """
                    Nowhere. Your resume, contact details, employment history, photo and any job \
                    description you paste are read, analysed and rendered entirely on this \
                    device. The app contains no networking code at all, so there is no path by \
                    which your data could be transmitted — not to us, not to an AI provider, not \
                    to anyone.
                    """
                )

                section(
                    "What is stored on your device",
                    body: """
                    Your work in progress is saved so closing the app doesn't lose it. That draft \
                    is kept in the app's private Application Support folder, written with \
                    complete file protection — iOS keeps it encrypted whenever your device is \
                    locked — and excluded from iCloud and iTunes backups. Choosing to discard a \
                    draft deletes the file.
                    """
                )

                section(
                    "The AI, specifically",
                    body: """
                    Where your device supports Apple Intelligence, Rolvexa uses Apple's on-device \
                    language model to rephrase bullet points. It runs inside Apple's own sandbox, \
                    on your hardware, under Apple's privacy guarantees. No prompt or resume text \
                    is sent to an external service.

                    The model only ever rewords. It is prevented from changing a number, claiming \
                    more seniority than your original wording, or introducing a technology or \
                    employer you didn't mention — any rewrite that does is discarded and your \
                    original kept. Spelling and grammar never go near the model.
                    """
                )

                section(
                    "What this does not protect you from",
                    body: """
                    A compromised, jailbroken or shared device. Files you export and then send, \
                    which travel by whatever means you choose. Screenshots. Anything you copy \
                    into another app. Rolvexa's promise is narrow and checkable: the app itself \
                    never transmits your resume. It is not anonymity, and it is not protection \
                    from someone holding your unlocked phone.
                    """
                )

                section(
                    "Accuracy",
                    body: """
                    Scores, job-fit percentages and suggestions are produced by rules running on \
                    your device. They are an opinion about a document, not a prediction about \
                    hiring. Rolvexa does not submit applications on your behalf — you download \
                    your documents and send them yourself.

                    Check anything the app writes before you send it.
                    """
                )

                contactPlaceholder
            }
            .padding(20)
        }
        .navigationTitle("Privacy & Terms")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Everything stays on this device", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(Color.indigo)

            Text("The short version: Rolvexa has no servers, no account and no network code. Your resume never leaves your phone unless you export it and send it yourself.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.indigo.opacity(0.08)))
    }

    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Left blank on purpose.
    ///
    /// A contact address, a company name and a governing jurisdiction are legal commitments, not
    /// copy — inventing them would put a fictional entity's name on a document users are meant
    /// to rely on. They have to be filled in by whoever actually publishes the app.
    private var contactPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Contact")
                .font(.subheadline.bold())
            Text("Add a contact address and governing jurisdiction here before publishing. Rolvexa is an open-source personal project; the source is public and can be read in full.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.appCardBackground))
    }
}

#Preview {
    NavigationStack {
        PrivacyAndTermsView()
    }
}
