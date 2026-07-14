import Foundation
import MapKit

struct LocationCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var displayValue: String {
        guard !address.localizedCaseInsensitiveContains(name) else { return address }
        return "\(name), \(address)"
    }
}

protocol LocationResolving: Sendable {
    func candidates(for query: String) async throws -> [LocationCandidate]
}

enum LocationResolutionError: LocalizedError, Equatable {
    case emptyQuery
    case unavailable
    case noResults

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Enter a venue or address before searching."
        case .unavailable:
            return "Apple Maps search is temporarily unavailable."
        case .noResults:
            return "Apple Maps did not find a matching place. Keep or edit the original location text."
        }
    }
}

struct DisabledLocationResolver: LocationResolving {
    func candidates(for query: String) async throws -> [LocationCandidate] {
        throw LocationResolutionError.unavailable
    }
}

struct MapKitLocationResolver: LocationResolving {
    func candidates(for query: String) async throws -> [LocationCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocationResolutionError.emptyQuery }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            throw LocationResolutionError.unavailable
        }

        let candidates = response.mapItems.prefix(5).compactMap { item -> LocationCandidate? in
            let coordinate = item.placemark.coordinate
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? item.placemark.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let address = item.placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty, let address, !address.isEmpty else { return nil }
            return LocationCandidate(
                id: "\(coordinate.latitude),\(coordinate.longitude),\(name)",
                name: name,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
        guard !candidates.isEmpty else { throw LocationResolutionError.noResults }
        return Array(candidates)
    }
}
