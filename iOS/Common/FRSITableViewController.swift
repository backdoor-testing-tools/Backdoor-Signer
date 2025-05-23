import Foundation
import UIKit

// Import the necessary signing data types
import SwiftUI // For ObservableObject

class FRSITableViewController: FRSTableViewController {
    var signingDataWrapper: SigningDataWrapper
    var mainOptions: SigningMainDataWrapper

    init(signingDataWrapper: SigningDataWrapper, mainOptions: SigningMainDataWrapper) {
        self.signingDataWrapper = signingDataWrapper
        self.mainOptions = mainOptions

        super.init()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
