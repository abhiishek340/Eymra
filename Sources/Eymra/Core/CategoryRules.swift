import Foundation

/// Label → category mapping as data. Identifiers are Vision `ClassifyImageRequest` class names;
/// an entry matches a label equal to it or starting with it followed by "_" (e.g. "food" matches "food_other").
nonisolated enum CategoryRules {
    static let sceneryLabels: Set<String> = [
        "outdoor", "landscape", "sky", "cloudy", "sunset_sunrise", "architecture", "structure", "building",
        "water", "water_body", "mountain", "hill", "beach", "shore", "sea", "ocean", "lake", "river", "waterfall",
        "forest", "tree", "nature", "field", "grass", "desert", "snow", "canyon", "cliff", "coast", "island",
        "bridge", "skyscraper", "cityscape", "city", "street", "road", "tower", "castle", "monument", "park",
        "garden", "night_sky", "aurora", "volcano", "glacier", "valley", "rainbow", "harbour", "lighthouse",
    ]

    static let foodLabels: Set<String> = [
        "food", "drink", "dish", "meal", "dessert", "beverage", "coffee", "tea", "wine", "cocktail", "beer",
        "pizza", "burger", "sandwich", "sushi", "salad", "pasta", "bread", "cake", "ice_cream", "fruit",
        "vegetable", "breakfast", "noodles", "soup", "steak", "seafood", "baked_goods", "pastry", "juice",
        "cheese", "chocolate", "cookie", "donut", "taco", "curry", "rice", "barbecue",
    ]

    static func matches(_ label: String, in table: Set<String>) -> Bool {
        let id = label.lowercased()
        if table.contains(id) { return true }
        if let head = id.split(separator: "_").first, table.contains(String(head)) { return true }
        return false
    }

    static func hasLabel(_ labels: [LabelScore], in table: Set<String>, minConfidence: Float = Tuning.categoryLabelConfidence) -> Bool {
        labels.contains { $0.confidence >= minConfidence && matches($0.identifier, in: table) }
    }

    /// Heuristic category, evaluated top to bottom, first match wins (spec §8).
    /// - Parameter withMe: whether the user is in the photo; nil when we can't tell.
    static func category(for f: FeatureRecord, withMe: Bool? = nil) -> Category {
        let faceCount = f.faces.count
        let largestFace = f.faces.map(\.box.area).max() ?? 0
        let largestHuman = f.humanBoxes.map(\.area).max() ?? 0
        let scenery = hasLabel(f.labels, in: sceneryLabels)
        // People, but the user isn't one of them.
        if faceCount > 0 && withMe == false { return .friends }
        if faceCount >= 3 { return .group }
        if (1...2).contains(faceCount) || !f.humanBoxes.isEmpty {
            if largestFace >= Tuning.meFaceArea || largestHuman >= Tuning.meHumanArea { return .me }
            if scenery { return .meWithView }
        }
        if faceCount == 0 {
            if hasLabel(f.labels, in: foodLabels) { return .food }
            if scenery { return .view }
            if let s = f.saliencyBox, s.area < Tuning.detailSaliencyArea { return .detail }
        }
        return .other
    }
}
