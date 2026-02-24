//
//  Item.swift
//  Tilawa
//
//  Created by Owais Quadri on 2026-02-24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
