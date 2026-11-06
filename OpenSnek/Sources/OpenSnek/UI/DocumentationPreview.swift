import SwiftUI

/// Suppresses view lifecycle work while rendering fixed documentation fixtures.
private struct DocumentationPreviewKey: EnvironmentKey { static let defaultValue = false }

/// Provides a scoped preview mode without changing the normal app lifecycle.
extension EnvironmentValues {
    var isDocumentationPreview: Bool {
        get { self[DocumentationPreviewKey.self] }
        set { self[DocumentationPreviewKey.self] = newValue }
    }
}
