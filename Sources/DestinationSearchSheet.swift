import SwiftUI
import MapKit

struct DestinationSearchSheet: View {
    @ObservedObject var searchService: DestinationSearchService
    let onSelect: (MKLocalSearchCompletion) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(searchService.suggestions.indices, id: \.self) { index in
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
            .listStyle(.plain)
            .searchable(
                text: $searchService.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search for a destination"
            )
            .navigationTitle("Destination")
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
