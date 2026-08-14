import SwiftUI
import MapKit

struct MapPanelView: View {
    @ObservedObject var routePlanner: RoutePlanner
    @Binding var cameraPosition: MapCameraPosition
    let onTapSetDestination: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Map(position: $cameraPosition) {
                UserAnnotation()

                if let route = routePlanner.route {
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 6)
                }

                if let destination = routePlanner.destination {
                    Marker(item: destination)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Button(action: onTapSetDestination) {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(destinationLabel)
                        .lineLimit(1)
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if let errorMessage = routePlanner.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }

    private var destinationLabel: String {
        if routePlanner.isPlanning {
            return "Routing…"
        }
        return routePlanner.destination?.name ?? "Set Destination"
    }
}
