import SwiftUI
import MapKit

/// Search-as-you-type location picker, reused for both the route's starting point and
/// its destination.
struct LocationSearchSheet: View {
    @ObservedObject var searchService: DestinationSearchService
    let title: String
    /// When non-nil, shows a leading "Use Current Location" row (only meaningful for
    /// picking a starting point — a destination always needs an explicit choice).
    var onUseCurrentLocation: (() -> Void)?
    let onSelect: (MKLocalSearchCompletion) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let onUseCurrentLocation {
                    Button {
                        onUseCurrentLocation()
                        dismiss()
                    } label: {
                        Label("Use Current Location", systemImage: "location.fill")
                    }
                }

                ForEach(searchService.suggestions.indices, id: \.self) { index in
                    let suggestion = searchService.suggestions[index]
                    Button {
                        onSelect(suggestion)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .foregroundColor(.white)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(
                text: $searchService.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search for a location"
            )
            .onAppear { searchService.query = "" }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
