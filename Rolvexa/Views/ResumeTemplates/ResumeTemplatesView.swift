import SwiftUI

struct ResumeTemplatesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState

    private struct TemplateOption: Identifiable {
        let id = UUID()
        let name: String
        let category: String
        let badge: String?
        let badgeColor: Color
        let description: String
        let accentColor: Color
        let style: ResumeTemplateStyle
    }

    private let categories = ["All", "Modern", "Minimal", "Creative", "Executive"]

    private let templates: [TemplateOption] = [
        TemplateOption(name: "Modern Edge", category: "Modern", badge: "MOST POPULAR", badgeColor: .indigo, description: "Best for tech & product roles", accentColor: .indigo, style: .modernEdge),
        TemplateOption(name: "Minimal Pro", category: "Minimal", badge: "ATS-FRIENDLY", badgeColor: .green, description: "Clean & distraction-free", accentColor: .black, style: .minimalPro),
        TemplateOption(name: "Creative Bold", category: "Creative", badge: nil, badgeColor: .clear, description: "Stand out with color and personality", accentColor: .purple, style: .creativeBold),
        TemplateOption(name: "Executive Suite", category: "Executive", badge: nil, badgeColor: .clear, description: "Polished look for senior roles", accentColor: .gray, style: .executiveSuite)
    ]

    private var selectedTemplate: TemplateOption {
        templates.first { $0.id == selectedTemplateID } ?? templates[0]
    }

    @State private var selectedCategory = "All"
    @State private var selectedTemplateID: UUID?
    @State private var showUploadChoice = false

    private var filteredTemplates: [TemplateOption] {
        selectedCategory == "All" ? templates : templates.filter { $0.category == selectedCategory }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    StepProgressHeader(step: 2, totalSteps: 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pick a design for your resume")
                            .font(.title2.bold())
                        Text("Choose a layout that best fits your style and role.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    categoryChips

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(filteredTemplates) { template in
                            templateCard(template)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Preview") {}
                            .buttonStyle(.bordered)
                            .tint(.indigo)

                        Button {
                            appState.keepOriginalUploadedLayout = false
                            appState.selectedResumeTemplateStyle = selectedTemplate.style
                            router.push(.aiBuilding)
                        } label: {
                            HStack { Text("Use This Template"); Image(systemName: "arrow.right") }
                        }
                        .buttonStyle(.primaryGradient)
                    }
                }
                .padding(20)
            }

            if showUploadChoice {
                uploadChoiceOverlay
            }
        }
        .onAppear {
            if selectedTemplateID == nil {
                selectedTemplateID = templates.first?.id
            }
            if appState.buildSource == .upload {
                showUploadChoice = true
            }
        }
    }

    private var uploadChoiceOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { showUploadChoice = false }

            VStack(spacing: 20) {
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "wand.and.stars")
                            .font(.title2)
                            .foregroundStyle(Color.indigo)
                    }

                VStack(spacing: 8) {
                    Text("Enhance your design?")
                        .font(.title3.bold())
                    Text("We can keep your current layout or upgrade it to a professional, recruiter-approved template.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Button {
                        appState.keepOriginalUploadedLayout = false
                        appState.selectedResumeTemplateStyle = selectedTemplate.style
                        showUploadChoice = false
                    } label: {
                        HStack {
                            Image(systemName: "paintpalette.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Replace with Template").font(.subheadline.bold())
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.indigo.opacity(0.4), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.keepOriginalUploadedLayout = true
                        showUploadChoice = false
                        router.push(.aiBuilding)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(Color.indigo)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Use Uploaded File").font(.subheadline.bold()).foregroundStyle(.primary)
                                Text("Keep original layout").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.appCardBackground))
                    }
                    .buttonStyle(.plain)
                }

                Button("Cancel") {
                    showUploadChoice = false
                }
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.appPageBackground))
            .padding(.horizontal, 32)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(category)
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(selectedCategory == category ? Color.indigo : Color.appCardBackground))
                            .foregroundStyle(selectedCategory == category ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func templateCard(_ template: TemplateOption) -> some View {
        let isSelected = template.id == selectedTemplateID
        return Button {
            selectedTemplateID = template.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    previewThumbnail(for: template)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white, Color.indigo)
                            .padding(6)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    if let badge = template.badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(template.badgeColor.opacity(0.15)))
                            .foregroundStyle(template.badgeColor)
                    }

                    Text(template.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.appCardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.indigo : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func previewThumbnail(for template: TemplateOption) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(template.accentColor).frame(width: 50, height: 8)
            RoundedRectangle(cornerRadius: 2).fill(Color.appSubtleFill).frame(height: 5).frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 2).fill(Color.appSubtleFill).frame(width: 60, height: 5)
            Divider().padding(.vertical, 2)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2).fill(Color.appSubtleFill).frame(height: 5).frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.appPageBackground))
    }
}

#Preview {
    NavigationStack {
        ResumeTemplatesView()
    }
    .environment(AppRouter())
    .environment(AppState())
}
