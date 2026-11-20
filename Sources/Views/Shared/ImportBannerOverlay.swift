import SwiftUI

/// Видимый баннер-оверлей вместо `.alert`: системный алерт в иерархии
/// TabView мог не показываться, а нам критично видеть этапы импорта.
struct ImportBannerOverlay: View {
    let banner: ImportBanner
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title)
                    .font(.subheadline.weight(.semibold))
                Text(banner.message)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("OK", action: onDismiss)
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .onTapGesture(perform: onDismiss)
        .accessibilityAddTraits(.isStaticText)
    }
}
