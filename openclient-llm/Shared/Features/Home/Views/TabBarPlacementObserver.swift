//
//  TabBarPlacementObserver.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 15/09/2026.
//  Copyright © 2026 Arturo Carretero Calvo. All rights reserved.
//

import SwiftUI

#if os(iOS)
struct TabBarPlacementObserver: ViewModifier {
    @Environment(\.tabBarPlacement) private var placement

    let onChange: (TabBarPlacement) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: placement, initial: true) { _, placement in
                guard let placement else { return }
                onChange(placement)
            }
    }
}
#endif
