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
    var education: String? = nil
    var style: ResumeTemplateStyle = .modernEdge

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
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .center)

            sidebarSection(title: "CONTACT") {
                VStack(alignment: .leading, spacing: 8) {
                    sidebarRow(icon: "envelope.fill", text: email ?? "Add your email to see it here")
                    sidebarRow(icon: "phone.fill", text: phone ?? "Add your phone to see it here")
                    sidebarRow(icon: "mappin.and.ellipse", text: location ?? "Add your location to see it here")
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
                        ForEach(skills.prefix(6), id: \.self) { skill in
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
                Text([email, phone, location].compactMap { $0 }.joined(separator: "  •  "))
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
                    VStack(alignment: .leading, spacing: 2) {
                        if !role.isEmpty { Text(role).font(.system(size: 14, weight: .semibold)) }
                        if !yearsOfExperience.isEmpty {
                            Text(yearsOfExperience).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(experienceBullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(Color.secondary).frame(width: 3, height: 3).padding(.top, 5)
                                Text(bullet).font(.system(size: 13.5)).lineSpacing(2)
                            }
                        }
                    }
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
                Text([email, phone, location].compactMap { $0 }.joined(separator: "  •  "))
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
                        VStack(alignment: .leading, spacing: 2) {
                            if !role.isEmpty { Text(role).font(.system(size: 14, weight: .semibold)) }
                            if !yearsOfExperience.isEmpty {
                                Text(yearsOfExperience).font(.system(size: 12.5)).foregroundStyle(.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(experienceBullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle().fill(Color.purple).frame(width: 3, height: 3).padding(.top, 5)
                                    Text(bullet).font(.system(size: 13.5)).lineSpacing(2)
                                }
                            }
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
            Text([email, phone, location].compactMap { $0 }.joined(separator: "   |   "))
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
                        VStack(alignment: .leading, spacing: 2) {
                            if !role.isEmpty { Text(role).font(.system(size: 14, weight: .semibold, design: .serif)) }
                            if !yearsOfExperience.isEmpty {
                                Text(yearsOfExperience).font(.system(size: 12.5, design: .serif)).foregroundStyle(.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(experienceBullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle().fill(accent).frame(width: 3, height: 3).padding(.top, 5)
                                    Text(bullet).font(.system(size: 13.5, design: .serif)).lineSpacing(2)
                                }
                            }
                        }
                    }
                    if !skills.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionHeader("SKILLS", color: accent, serif: true)
                            Text(skills.joined(separator: ", ")).font(.system(size: 13.5, design: .serif)).foregroundStyle(.primary)
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

                    VStack(alignment: .leading, spacing: 2) {
                        if !role.isEmpty {
                            Text(role)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        if !yearsOfExperience.isEmpty {
                            Text(yearsOfExperience)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(experienceBullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(Color.secondary)
                                    .frame(width: 3, height: 3)
                                    .padding(.top, 5)
                                Text(bullet)
                                    .font(.system(size: 13.5))
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPageBackground)
    }
}

#Preview {
    ResumeTemplateCard(
        name: "Jamie Chen",
        role: "Senior Product Designer",
        summary: "Senior Product Designer with 5–7 years of experience, skilled in Product Design, Figma, User Research. Seeking to bring this expertise to the Senior Product Designer role at Northwind Labs.",
        skills: ["Product Design", "Figma", "User Research"],
        yearsOfExperience: "5–7 years",
        experienceBullets: ["Led design for a resume-building app", "Improved onboarding conversion by 20%"]
    )
    .padding(20)
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
