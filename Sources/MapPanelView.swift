import SwiftUI
import MapKit

struct MapPanelView: View {
    @ObservedObject var routePlanner: RoutePlanner
    @Binding var cameraPosition: MapCameraPosition
    let onTapSetStart: () -> Void
    let onTapSetDestination: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Map(position: $cameraPosition) {
                UserAnnotation()

                if let startingPoint = routePlanner.startingPoint {
                    Marker(startingPoint.name ?? "Start", coordinate: startingPoint.placemark.coordinate)
                        .tint(.green)
                }

                if let route = routePlanner.route {
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 6)
                }

                if let destination = routePlanner.destination {
                    Marker(item: destination)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 480, maxHeight: 480)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            HStack(spacing: 8) {
                locationButton(
                    icon: "location.circle",
                    label: routePlanner.startingPoint?.name ?? "Current Location",
                    action: onTapSetStart
                )
                locationButton(
                    icon: "mappin.and.ellipse",
                    label: destinationLabel,
                    action: onTapSetDestination
                )
            }

            if let errorMessage = routePlanner.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }

    private func locationButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
                    .lineLimit(1)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var destinationLabel: String {
        if routePlanner.isPlanning {
            return "Routing…"
        }
        return routePlanner.destination?.name ?? "Set Destination"
    }
}
