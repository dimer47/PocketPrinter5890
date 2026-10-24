import Foundation
import PocketPrinter5890Kit

/// Imprimante choisie et reglages qui en dependent, conserves entre deux
/// lancements.
///
/// L'ordre compte: on choisit d'abord la famille et le modele, et le papier
/// propose en decoule. Changer de modele remet donc un papier compatible si
/// l'ancien ne l'est plus (un rouleau de 102 mm n'entre pas dans une TD-2).
@MainActor
final class PrinterSetup: ObservableObject {
    @Published var brand: PrinterBrand {
        didSet { store(brand.rawValue, for: .brand) }
    }

    @Published var brotherModel: BrotherModel {
        didSet {
            store(brotherModel.rawValue, for: .brotherModel)
            if !brotherMedia.isCompatible(with: brotherModel) {
                brotherMedia = BrotherMedia.defaultMedia(for: brotherModel)
            }
        }
    }

    @Published var brotherMedia: BrotherMedia {
        didSet { storeEncoded(brotherMedia, for: .brotherMedia) }
    }

    /// Coupe automatique. Desactivee par defaut: sur une TD le massicot est
    /// un accessoire qui n'est pas forcement installe.
    @Published var cut: BrotherCutOptions {
        didSet { storeEncoded(cut, for: .cut) }
    }

    @Published var copies: Int {
        didSet { store(copies, for: .copies) }
    }

    private let defaults: UserDefaults

    private enum Key: String {
        case brand = "printer.brand"
        case brotherModel = "printer.brother.model"
        case brotherMedia = "printer.brother.media"
        case cut = "printer.brother.cut"
        case copies = "printer.brother.copies"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        brand = defaults.string(forKey: Key.brand.rawValue).flatMap(PrinterBrand.init) ?? .pocket5890
        let model = defaults.string(forKey: Key.brotherModel.rawValue).flatMap(BrotherModel.init)
            ?? .defaultModel
        brotherModel = model
        let media: BrotherMedia? = Self.decode(defaults.data(forKey: Key.brotherMedia.rawValue))
        brotherMedia = media.flatMap { $0.isCompatible(with: model) ? $0 : nil }
            ?? .defaultMedia(for: model)
        cut = Self.decode(defaults.data(forKey: Key.cut.rawValue)) ?? BrotherCutOptions()
        copies = max(1, defaults.object(forKey: Key.copies.rawValue) as? Int ?? 1)
    }

    /// Travail Brother correspondant aux choix courants.
    var brotherJob: BrotherJob {
        BrotherJob(model: brotherModel, media: brotherMedia, cut: cut, copies: copies)
    }

    private func store(_ value: Any, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private func storeEncoded<T: Encodable>(_ value: T, for key: Key) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key.rawValue)
    }

    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

/// Ce qu'il faut savoir pour imprimer sur une Brother.
struct BrotherJob {
    let model: BrotherModel
    let media: BrotherMedia
    let cut: BrotherCutOptions
    let copies: Int
}
