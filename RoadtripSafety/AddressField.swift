import SwiftUI
import MapKit
import CoreLocation

/// A text field that shows live address/city suggestions and reports the
/// resolved coordinate + display name back to the caller.
struct AddressField: View {
    let label: String
    let iconColor: Color
    @Binding var displayName: String
    let onResolved: (CLLocationCoordinate2D, String) -> Void

    @StateObject private var search = AddressSearchService()
    @FocusState private var focused: Bool
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(iconColor).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    TextField("City or address", text: Binding(
                        get: { displayName },
                        set: { newValue in
                            displayName = newValue
                            search.query = newValue
                            showSuggestions = true
                        }
                    ))
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                }
            }
            .padding(.vertical, 8)

            if showSuggestions && focused && !search.suggestions.isEmpty {
                Divider()
                ForEach(search.suggestions.prefix(4), id: \.self) { suggestion in
                    Button {
                        Task { await choose(suggestion) }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(suggestion.title).font(.subheadline)
                                .foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    if suggestion != search.suggestions.prefix(4).last {
                        Divider()
                    }
                }
            }
        }
    }

    private func choose(_ suggestion: MKLocalSearchCompletion) async {
        if let (coord, name) = await search.resolve(suggestion) {
            displayName = name
            onResolved(coord, name)
        }
        showSuggestions = false
        focused = false
        search.clear()
    }
}
