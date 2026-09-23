import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0

    private let pages: [Page] = [
        Page(
            symbol: "camera.viewfinder",
            title: "Photograph the display",
            message: "Point the camera at a digital scale or blood pressure monitor. VitalSnap reads the digits on this iPhone. The photo is not uploaded."
        ),
        Page(
            symbol: "checkmark.circle",
            title: "Check every number",
            message: "The reader is a best guess. You will see the reading before anything is saved, and you can correct a digit the camera missed."
        ),
        Page(
            symbol: "heart.text.square",
            title: "Keep it in Apple Health",
            message: "When you confirm, VitalSnap writes weight or blood pressure into the Health app. It does not interpret the reading or offer a diagnosis."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VITALSNAP")
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.green)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 20) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(Theme.green)
                            .frame(width: 84, height: 84)
                            .background(Theme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        Text(item.title)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.message)
                            .font(.title3)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Theme.green : Theme.ink.opacity(0.18))
                            .frame(width: index == page ? 22 : 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(page + 1) of \(pages.count)")

                PrimaryButton(title: page == pages.count - 1 ? "Get started" : "Continue") {
                    if page == pages.count - 1 {
                        model.completeOnboarding()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                Text("Camera access is requested when you take a photo. Apple Health is requested when you save.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}

private struct Page {
    var symbol: String
    var title: String
    var message: String
}

#Preview {
    OnboardingView()
        .environment(AppModel(previewData: true))
}
