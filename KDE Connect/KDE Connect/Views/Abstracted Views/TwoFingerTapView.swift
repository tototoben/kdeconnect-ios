/*
 * SPDX-FileCopyrightText: 2021 Lucas Wang <lucas.wang@tuta.io>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

// Original header below:
//
//  TwoFingerTapView.swift
//  KDE Connect Test
//
//  Created by Lucas Wang on 2021-09-06.
//

#if !os(macOS)

import UIKit
import SwiftUI

struct TwoFingerTapView: UIViewRepresentable {
    let tapCallback: (UITapGestureRecognizer) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(tapCallback: tapCallback)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemBackground
        let twoFingerTapGestureRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(sender:))
        )
        
        // Set number of touches.
        twoFingerTapGestureRecognizer.numberOfTouchesRequired = 2
        
        view.addGestureRecognizer(twoFingerTapGestureRecognizer)

        let iconView: UIImageView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "hand.tap")
        iconView.tintColor = .secondarySystemFill
        iconView.contentMode = .scaleAspectFit
        iconView.alpha = 0.5
        view.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.3),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
        ])

        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
    }
    
    class Coordinator {
        let tapCallback: (UITapGestureRecognizer) -> Void
        
        init(tapCallback: @escaping (UITapGestureRecognizer) -> Void) {
            self.tapCallback = tapCallback
        }
        
        @objc func handleTap(sender: UITapGestureRecognizer) {
            tapCallback(sender)
        }
    }
}

#endif
