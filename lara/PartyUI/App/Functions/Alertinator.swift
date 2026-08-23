//
//  Alertinator.swift
//  PartyUI
//
//  Created by lunginspector on 2/12/26.
//

import Foundation
import UIKit

@MainActor
public class Alertinator {
    public static let shared = Alertinator()
    
    var alertController: UIAlertController?
    
    public func alert(title: String, body: String, showCancel: Bool = true) {
        Task { @MainActor in
            alertController = UIAlertController(title: title, message: body, preferredStyle: .alert)
            if showCancel {
                alertController?.addAction(.init(title: "OK", style: .cancel))
            }
            alertController?.view.tintColor = UIColor(named: "AccentColor")
            guard let controller = self.alertController else { return }
            self.present(controller)
        }
    }
    
    public func alert(title: String, body: String, showCancel: Bool = true, actionLabel: String = "OK", action: @escaping () -> Void) {
        Task { @MainActor in
            alertController = UIAlertController(title: title, message: body, preferredStyle: .alert)
            alertController?.addAction(.init(title: actionLabel, style: .default) { _ in
                action()
            })
            if showCancel {
                alertController?.addAction(.init(title: "Cancel", style: .cancel))
            }
            alertController?.view.tintColor = UIColor(named: "AccentColor")
            guard let controller = self.alertController else { return }
            self.present(controller)
        }
    }
    
    public func prompt(title: String, placeholder: String, showCancel: Bool = true, completion: @escaping (String?) async -> Void) {
        Task { @MainActor in
            alertController = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            alertController?.addTextField { field in
                field.placeholder = placeholder
            }
            if showCancel {
                alertController?.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    Task {
                        await completion(nil)
                    }
                })
            }
            alertController?.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                let field = self.alertController?.textFields?.first
                Task {
                    await completion(field?.text)
                }
            })
            alertController?.view.tintColor = UIColor(named: "AccentColor")
            guard let controller = self.alertController else { return }
            self.present(controller)
        }
    }
    
    @MainActor
    private func present(_ alert: UIAlertController) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              var topController = window.rootViewController else {
            return
        }

        while let presentedViewController = topController.presentedViewController {
            // Replace an already-visible alert instead of stacking forever.
            if presentedViewController is UIAlertController {
                presentedViewController.dismiss(animated: false) {
                    topController.present(alert, animated: true)
                }
                return
            }
            topController = presentedViewController
        }

        topController.present(alert, animated: true)
    }
}

