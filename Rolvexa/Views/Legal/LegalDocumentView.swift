import SwiftUI

/// Which legal document to show.
enum LegalDocument: Hashable {
    case privacy
    case terms

    var title: String {
        switch self {
        case .privacy: return "Privacy Policy"
        case .terms: return "Terms of Service"
        }
    }
}

/// Renders a legal document.
///
/// Both documents are written from what the app verifiably does rather than from boilerplate.
/// Every factual claim is checkable against the source: there is no networking code in the
/// project, the draft is written with complete file protection, and the language model is
/// Apple's on-device one. Nothing here describes behaviour the app doesn't have.
struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                switch document {
                case .privacy: privacyBody
                case .terms: termsBody
                }
                contactPlaceholder
            }
            .padding(20)
        }
        .navigationTitle(document.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Privacy

    @ViewBuilder
    private var privacyBody: some View {
        highlight(
            "Everything stays on this device",
            "Rolvexa has no servers, no account and no network code. Your resume never leaves your phone unless you export it and send it yourself."
        )

        section("What Rolvexa collects", """
        Nothing. There is no account system, no analytics, no crash reporting and no servers. \
        The app never asks who you are.
        """)

        section("Where your resume goes", """
        Nowhere. Your resume, contact details, employment history, photo and any job description \
        you paste are read, analysed and rendered entirely on this device. The app contains no \
        networking code at all, so there is no path by which your data could be transmitted — \
        not to us, not to an AI provider, not to anyone.
        """)

        section("What is stored on your device", """
        Every resume you work on is saved so closing the app doesn't lose it, and they build up \
        into the library on the My Resumes screen. They are kept in the app's private \
        Application Support folder, written with complete file protection — iOS keeps them \
        encrypted whenever your device is locked — and excluded from iCloud and iTunes backups. \
        You can export them, delete any one of them from My Resumes, or delete all of them at \
        once from Legal & Privacy.
        """)

        section("Cookies and tracking", """
        There are none. Rolvexa has no web views and makes no network requests, so there is \
        nothing to set a cookie, and no third party to track you for.
        """)

        section("The AI, specifically", """
        Where your device supports Apple Intelligence, Rolvexa uses Apple's on-device language \
        model to rephrase bullet points. It runs inside Apple's own sandbox, on your hardware, \
        under Apple's privacy guarantees. No prompt or resume text is sent to an external \
        service.

        The model only ever rewords. It cannot change a number, claim more seniority than your \
        original wording, or introduce a technology or employer you didn't mention — any rewrite \
        that does is discarded and your original kept. Spelling and grammar never go near it.
        """)

        section("What this does not protect you from", """
        A compromised, jailbroken or shared device. Files you download or share, which travel by \
        whatever means you choose — the moment you pick a destination in the share sheet, the \
        file goes wherever you sent it. Screenshots. Anything you copy into another app.

        Rolvexa's promise is narrow and checkable: the app itself never transmits your resume. \
        It is not anonymity, and it is not protection from someone holding your unlocked phone.
        """)
    }

    // MARK: - Terms

    @ViewBuilder
    private var termsBody: some View {
        highlight(
            "Rolvexa helps you write; you decide what to send",
            "The app prepares documents on your device. Submitting them to an employer is always your own action."
        )

        section("What the app does", """
        Rolvexa reads a resume from a PDF, a Word file, a photo or your own typing, scores it, \
        optionally compares it to a job description you paste, and generates a PDF or Word \
        document for you to download.
        """)

        section("What it does not do", """
        It does not apply for jobs on your behalf. It does not send email, upload files or \
        contact employers. Downloading a document and submitting it is entirely up to you.
        """)

        section("About the scores", """
        Scores, job-fit percentages and suggestions are produced by rules running on your \
        device. They are an opinion about a document, not a prediction about hiring, and no \
        outcome is promised or implied. A high score does not mean you will be interviewed, and \
        a low one does not mean you won't.
        """)

        section("Accuracy is your responsibility", """
        Rolvexa will not invent facts, numbers or achievements, and rejects any AI rewrite that \
        tries to. But automated text extraction and rephrasing can still make mistakes.

        Read anything the app produces before you send it. The claims on your resume are yours.
        """)

        section("Provided as-is", """
        This is an open-source personal project, provided without warranty. The source is public \
        and can be read in full, which is the most meaningful assurance on offer: you don't have \
        to take any of this on trust.
        """)
    }

    // MARK: - Shared pieces

    private func highlight(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(Color.indigo)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.indigo.opacity(0.08)))
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Left blank on purpose — a contact address, a company name and a governing jurisdiction
    /// are legal commitments, not copy. Inventing them would put a fictional entity's name on a
    /// document users are meant to rely on.
    private var contactPlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Contact").font(.subheadline.bold())
            Text("Add a contact address and governing jurisdiction here before publishing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.appCardBackground))
    }
}

#Preview("Privacy") {
    NavigationStack { LegalDocumentView(document: .privacy) }
}

#Preview("Terms") {
    NavigationStack { LegalDocumentView(document: .terms) }
}
