import SwiftUI

#if os(iOS)
import UIKit

extension UIApplication {
    static var keyWindow: UIWindow? {
        guard let scene = shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return nil
        }
        return window
    }
}
#endif 