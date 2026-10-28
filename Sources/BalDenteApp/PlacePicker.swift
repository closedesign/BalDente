import BalDenteCore
import MapKit
import SwiftUI

/// Pick a zone's saved place on a map: search, click to drop the pin, drag the slider for the radius.
/// Only edits a draft; the zone changes when the user taps Save.
struct PlacePicker: View {
    let initial: Place?
    let onSave: (Place) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var center: CLLocationCoordinate2D?
    @State private var radius: Double
    @State private var camera: MapCameraPosition
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var searchMessage: String?

    init(initial: Place?, onSave: @escaping (Place) -> Void) {
        self.initial = initial; self.onSave = onSave
        let c = initial.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        _center = State(initialValue: c)
        _radius = State(initialValue: initial?.radius ?? 150)
        if let c, let r = initial?.radius {
            _camera = State(initialValue: .region(MKCoordinateRegion(center: c, latitudinalMeters: r * 6, longitudinalMeters: r * 6)))
        } else {
            _camera = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Choose on map").font(.system(.title2, design: .rounded).weight(.bold))
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Button("Save") {
                    if let c = center { onSave(Place(latitude: c.latitude, longitude: c.longitude, radius: radius)) }
                    dismiss()
                }.buttonStyle(.glassProminent).disabled(center == nil)
            }
            HStack {
                TextField("Search for an address or place", text: $query)
                    .textFieldStyle(.roundedBorder).onSubmit(search)
                Button("Search", action: search).buttonStyle(.glass).disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(results, id: \.self) { item in
                            Button { choose(item.placemark.coordinate) } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(item.name ?? "Place").font(.subheadline)
                                    if let a = item.placemark.title {
                                        Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 96)
            } else if let m = searchMessage {
                Text(m).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                    if let c = center {
                        MapCircle(center: c, radius: radius)
                            .foregroundStyle(Color.accentColor.opacity(0.22))
                            .stroke(Color.accentColor, lineWidth: 2)
                        Marker("Zone", coordinate: c)
                    }
                }
                .mapControls { MapZoomStepper(); MapCompass() }
                .onTapGesture { pt in
                    if let c = proxy.convert(pt, from: .local) { center = c }
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .frame(minHeight: 280)
            HStack {
                Text("Radius \(Int(radius)) m").monospacedDigit().frame(width: 120, alignment: .leading)
                Slider(value: $radius, in: 100...Place.maxRadius, step: 100)
            }
            Text(center == nil ? "Click the map to drop the pin." : "Click elsewhere to move the pin. Keep the radius at 100 m or more: Macs locate you by Wi-Fi.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 560, height: 640)
        .presentationBackground(.ultraThinMaterial)
    }

    private func choose(_ c: CLLocationCoordinate2D) {
        center = c; results = []; searchMessage = nil
        camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: max(radius * 6, 800), longitudinalMeters: max(radius * 6, 800)))
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true; searchMessage = nil
        let req = MKLocalSearch.Request(); req.naturalLanguageQuery = q
        Task {
            let found = try? await MKLocalSearch(request: req).start().mapItems
            searching = false
            results = Array((found ?? []).prefix(6))
            if results.isEmpty { searchMessage = "No matches. Try a fuller address." }
        }
    }
}
