import SwiftUI

/// Minimal `UIActivityViewController` wrapper.
///
/// Used wherever the app hands a file to the user to send somewhere themselves — the data
/// export on Legal & Privacy, and sharing a resume out of the library. Note what this implies:
/// once the user picks a destination the file leaves the device by whatever route they chose.
/// That's their decision to make, and the privacy policy says so explicitly; the app's promise
/// is only that *it* never transmits anything on its own.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
