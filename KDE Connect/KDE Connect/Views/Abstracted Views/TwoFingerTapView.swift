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
        iconView.tintColor = .systemGray
        iconView.contentMode = .scaleAspectFit
        iconView.alpha = 0.8
        view.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.3),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
        ])

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.5
        pulse.toValue = 0.9
        pulse.duration = 1.5
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        iconView.layer.add(pulse, forKey: "brightnessPulse")

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
