import SwiftUI

@main
struct RobotPlannerApp: App {
    var body: some Scene {
        WindowGroup {
            RobotPlannerContainer()
                .ignoresSafeArea()
        }
    }
}

struct RobotPlannerContainer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> RobotPlannerViewController {
        RobotPlannerViewController()
    }

    func updateUIViewController(_ uiViewController: RobotPlannerViewController, context: Context) {}
}
