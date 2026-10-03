import SwiftUI

struct ResumeTemplateCard: View {
    let name: String
    let role: String
    let summary: String
    let skills: [String]
    let yearsOfExperience: String
    let experienceBullets: [String]
    var rawText: String? = nil
    var email: String? = nil
    var phone: String? = nil
    var location: String? = nil
    /// Profile/portfolio URLs (LinkedIn, GitHub, …), shown with the rest of the contact details.
    var links: [String] = []
    var education: String? = nil
    /// Structured jobs, each with its own title, dates, employer and bullets. The upload flow
    /// has no such structure and leaves this empty, falling back to `role`/`yearsOfExperience`
    /// plus the flat `experienceBullets` list.
    var positions: [WorkExperienceEntry] = []
    /// Optional headshot, prepared by `ResumePhoto`. Only the sidebar layout has a place for it.
    var photoData: Data?
    var style: ResumeTemplateStyle = .modernEdge

    /// The contact values the flowing and banner layouts print as a single run.
    private var contactParts: [String] {
        ([email, phone, location].compactMap { $0 } + links).filter { !$0.isEmpty }
    }

    /// The headshot, or the placeholder silhouette when none was chosen.
    @ViewBuilder
    private var avatar: some View {
        if let photoData, let image = ResumePhoto.image(from: photoData) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
        }
    }

    /// The PROFESSIONAL EXPERIENCE body, shared by all four layouts so the structured and
    /// fallback shapes can't drift apart between templates.
    @ViewBuilder
    private func experienceBody(bulletColor: Color, design: Font.Design = .default) -> some View {
        if positions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    if !role.isEmpty {
                        Text(role).font(.system(size: 14, weight: .semibold, design: design))
                    }
                    if !yearsOfExperience.isEmpty {
                        Text(yearsOfExperience)
                            .font(.system(size: 12.5, design: design))
                            .foregroundStyle(.secondary)
                    }
                }
                bulletList(experienceBullets, color: bulletColor, design: design)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(positions) { position in
                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(position.headingLine)
                                .font(.system(size: 14, weight: .semibold, design: design))
                            if !position.employerLine.isEmpty {
                                Text(position.employerLine)
                                    .font(.system(size: 12.5, design: design))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        bulletList(position.filledBullets, color: bulletColor, design: design)
                    }
                }
            }
        }
    }

    private func bulletList(_ bullets: [String], color: Color, design: Font.Design) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(color).frame(width: 3, height: 3).padding(.top, 5)
                    Text(bullet).font(.system(size: 13.5, design: design)).lineSpacing(2)
                }
            }
        }
    }

    var body: some View {
        Group {
            switch style {
            case .modernEdge:
                modernEdgeLayout
            case .minimalPro:
                minimalProLayout
            case .creativeBold:
                creativeBoldLayout
            case .executiveSuite:
                executiveSuiteLayout
            }
        }
        .background(Color.appPageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.appSeparator.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    // MARK: - Modern Edge (sidebar layout, indigo)

    private var modernEdgeLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            mainContent(accent: .indigo)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            avatar
                .frame(maxWidth: .infinity, alignment: .center)

            sidebarSection(title: "CONTACT") {
                VStack(alignment: .leading, spacing: 8) {
                    sidebarRow(icon: "envelope.fill", text: email ?? "Add your email to see it here")
                    sidebarRow(icon: "phone.fill", text: phone ?? "Add your phone to see it here")
                    sidebarRow(icon: "mappin.and.ellipse", text: location ?? "Add your location to see it here")
                    // Profile links are part of the contact block in the exported files; without
                    // these rows the preview silently dropped them.
                    ForEach(links, id: \.self) { link in
                        sidebarRow(icon: "link", text: link)
                    }
                }
            }

            // When the raw resume dump is shown below, its EDUCATION section already contains
            // this same info in full — repeating an excerpt here just duplicates it and eats
            // sidebar space, so only show it in the sidebar for the generated (non-upload) resume.
            if rawText == nil || rawText?.isEmpty == true {
                sidebarSection(title: "EDUCATION") {
                    Text(education ?? "Add your degree in the experience step to see it here")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                }
            }

            sidebarSection(title: "TECHNICAL SKILLS") {
                if skills.isEmpty {
                    Text("Add skills in the experience step to see them here")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        // No cap: the PDF and Word sidebars list every skill, so truncating here
                        // made the on-screen preview disagree with the file the user downloads.
                        ForEach(skills, id: \.self) { skill in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(.white.opacity(0.8))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 6)
                                Text(skill)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 200, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Color.indigo)
    }

    private func sidebarSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            content()
        }
    }

    private func sidebarRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.white.opacity(0.2)))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
    }

    // MARK: - Minimal Pro (single column, black & white, ATS-friendly)

    private var minimalProLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 22, weight: .bold))
                if !role.isEmpty {
                    Text(role)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(contactParts.joined(separator: "   |   "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let rawText, !rawText.isEmpty {
                if !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("ABOUT ME", isFirst: true, color: .black)
                        Text(summary).font(.system(size: 14)).foregroundStyle(.primary).lineSpacing(3)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("RESUME", isFirst: summary.isEmpty, color: .black)
                    rawResumeBody(rawText, headerColor: .black)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("ABOUT ME", isFirst: true, color: .black)
                    Text(summary).font(.system(size: 14)).foregroundStyle(.primary).lineSpacing(3)
                }
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("PROFESSIONAL EXPERIENCE", color: .black)
                    experienceBody(bulletColor: .secondary)
                }
                if !skills.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("SKILLS", color: .black)
                        Text(skills.joined(separator: ", ")).font(.system(size: 13.5)).foregroundStyle(.primary)
                    }
                }
                if let education, !education.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("EDUCATION", color: .black)
                        Text(education).font(.system(size: 13.5)).foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    // MARK: - Creative Bold (colorful hero header, purple accent)

    private var creativeBoldLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                if !role.isEmpty {
                    Text(role)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text(contactParts.joined(separator: "   |   "))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            )

            VStack(alignment: .leading, spacing: 16) {
                if !skills.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(skills, id: \.self) { skill in
                            Text(skill)
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.purple.opacity(0.15)))
                                .foregroundStyle(Color.purple)
                        }
                    }
                }

                if let rawText, !rawText.isEmpty {
                    if !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionHeader("ABOUT ME", isFirst: true, color: .purple)
                            Text(summary).font(.system(size: 14)).foregroundStyle(.primary).lineSpacing(3)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("RESUME", isFirst: summary.isEmpty, color: .purple)
                        rawResumeBody(rawText, headerColor: .purple)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("ABOUT ME", isFirst: true, color: .purple)
                        Text(summary).font(.system(size: 14)).foregroundStyle(.primary).lineSpacing(3)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("PROFESSIONAL EXPERIENCE", color: .purple)
                        experienceBody(bulletColor: .purple)
                    }
                    if let education, !education.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionHeader("EDUCATION", color: .purple)
                            Text(education).font(.system(size: 13.5)).foregroundStyle(.primary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Executive Suite (formal, centered, serif, gray accent)

    private var executiveSuiteLayout: some View {
        let accent = Color(white: 0.35)
        return VStack(alignment: .center, spacing: 10) {
            Text(name)
                .font(.system(size: 25, weight: .semibold, design: .serif))
            if !role.isEmpty {
                Text(role)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(.secondary)
            }
            Rectangle().fill(accent).frame(width: 70, height: 2).padding(.top, 2)
            Text(contactParts.joined(separator: "   |   "))
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(.secondary)

            Divider().padding(.top, 8)

            VStack(alignment: .leading, spacing: 16) {
                if let rawText, !rawText.isEmpty {
                    if !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionHeader("ABOUT ME", isFirst: true, color: accent, serif: true)
                            Text(summary).font(.system(size: 14, design: .serif)).foregroundStyle(.primary).lineSpacing(3)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("RESUME", isFirst: summary.isEmpty, color: accent, serif: true)
                        rawResumeBody(rawText, headerColor: accent, serif: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("ABOUT ME", isFirst: true, color: accent, serif: true)
                        Text(summary).font(.system(size: 14, design: .serif)).foregroundStyle(.primary).lineSpacing(3)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("PROFESSIONAL EXPERIENCE", color: accent, serif: true)
                        experienceBody(bulletColor: accent, design: .serif)
                    }
                    if !skills.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionHeader("SKILLS", color: accent, serif: true)
                            Text(skills.joined(separator: ", ")).font(.system(size: 13.5, design: .serif)).foregroundStyle(.primary)
                        }
                    }
                    if let education, !education.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionHeader("EDUCATION", color: accent, serif: true)
                            Text(education).font(.system(size: 13.5, design: .serif)).foregroundStyle(.primary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared helpers

    /// Renders the raw extracted resume text line-by-line so section headers (e.g.
    /// "PROFESSIONAL EXPERIENCE") stand out as actual headers instead of blending into the
    /// surrounding paragraph text as just another stacked line.
    private func rawResumeBody(_ text: String, headerColor: Color, serif: Bool = false) -> some View {
        let lines = ResumeSectionKit.removeDanglingHeaders(text.components(separatedBy: "\n"))
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if line.isEmpty {
                    EmptyView()
                } else if ResumeSectionKit.isSectionHeader(line) {
                    Text(line)
                        .font(.system(size: 16, weight: .bold, design: serif ? .serif : .default))
                        .foregroundStyle(headerColor)
                        .padding(.top, index == 0 ? 0 : 16)
                } else {
                    Text(line)
                        .font(.system(size: 14, design: serif ? .serif : .default))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, isFirst: Bool = false, color: Color, serif: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold, design: serif ? .serif : .default))
            .foregroundStyle(color)
            .padding(.top, isFirst ? 0 : 6)
    }

    private func mainContent(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 23, weight: .bold))
                if !role.isEmpty {
                    Text(role)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Rectangle()
                    .fill(accent)
                    .frame(width: 56, height: 3)
                    .padding(.top, 4)
            }

            if let rawText, !rawText.isEmpty {
                if !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader("ABOUT ME", isFirst: true, color: accent)
                        Text(summary)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .lineSpacing(3)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("RESUME", isFirst: summary.isEmpty, color: accent)
                    rawResumeBody(rawText, headerColor: accent)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    sectionHeader("ABOUT ME", isFirst: true, color: accent)
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("PROFESSIONAL EXPERIENCE", color: accent)

                    experienceBody(bulletColor: .secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPageBackground)
    }
}

// Wrapped in a ScrollView to match `ResumeKitView`, which is where this card actually lives.
// Rendered bare, the preview hands the card a fixed screen height and a resume with more than
// one job gets truncated with ellipses that never appear in the app.
#Preview {
    ScrollView {
    ResumeTemplateCard(
        name: "Jamie Chen",
        role: "Senior Product Designer",
        summary: "Senior Product Designer with 5–7 years of experience, skilled in Product Design, Figma, User Research. Seeking to bring this expertise to the Senior Product Designer role at Northwind Labs.",
        skills: ["Product Design", "Figma", "User Research"],
        yearsOfExperience: "5–7 years",
        experienceBullets: ["Led design for a resume-building app", "Improved onboarding conversion by 20%"],
        email: "jamie@example.com",
        phone: "555-0100",
        location: "San Francisco, CA",
        links: ["www.linkedin.com/in/jamiechen", "github.com/jamiechen"],
        education: "BA Interaction Design\nCalifornia College of the Arts, San Francisco, CA\nMay 2017",
        positions: [
            {
                var entry = WorkExperienceEntry()
                entry.title = "Senior Product Designer"
                entry.company = "Northwind Labs"
                entry.location = "San Francisco, CA"
                entry.startDate = "Mar 2021"
                entry.isCurrent = true
                entry.bullets = [
                    "Led design for a resume-building app used by 40k people",
                    "Improved onboarding conversion by 20%"
                ]
                return entry
            }(),
            {
                var entry = WorkExperienceEntry()
                entry.title = "Product Designer"
                entry.company = "Gridline"
                entry.location = "Oakland, CA"
                entry.startDate = "Jun 2017"
                entry.endDate = "Feb 2021"
                entry.bullets = ["Shipped a design system adopted by four product teams"]
                return entry
            }()
        ]
    )
    .padding(20)
    }
}

#Preview("Minimal Pro") {
    ResumeTemplateCard(
        name: "Jamie Chen",
        role: "Senior Product Designer",
        summary: "Senior Product Designer with 5–7 years of experience, skilled in Product Design, Figma, User Research.",
        skills: ["Product Design", "Figma", "User Research"],
        yearsOfExperience: "5–7 years",
        experienceBullets: ["Led design for a resume-building app", "Improved onboarding conversion by 20%"],
        email: "jamie@example.com",
        phone: "555-0100",
        location: "San Francisco, CA",
        style: .minimalPro
    )
    .padding(20)
}

#Preview("Creative Bold") {
    ResumeTemplateCard(
        name: "Jamie Chen",
        role: "Senior Product Designer",
        summary: "Senior Product Designer with 5–7 years of experience, skilled in Product Design, Figma, User Research.",
        skills: ["Product Design", "Figma", "User Research"],
        yearsOfExperience: "5–7 years",
        experienceBullets: ["Led design for a resume-building app", "Improved onboarding conversion by 20%"],
        email: "jamie@example.com",
        phone: "555-0100",
        location: "San Francisco, CA",
        style: .creativeBold
    )
    .padding(20)
}

#Preview("Executive Suite") {
    ResumeTemplateCard(
        name: "Jamie Chen",
        role: "Senior Product Designer",
        summary: "Senior Product Designer with 5–7 years of experience, skilled in Product Design, Figma, User Research.",
        skills: ["Product Design", "Figma", "User Research"],
        yearsOfExperience: "5–7 years",
        experienceBullets: ["Led design for a resume-building app", "Improved onboarding conversion by 20%"],
        email: "jamie@example.com",
        phone: "555-0100",
        location: "San Francisco, CA",
        style: .executiveSuite
    )
    .padding(20)
}
