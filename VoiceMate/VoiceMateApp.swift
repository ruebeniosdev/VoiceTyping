

import SwiftUI
import StoreKit
import AVFoundation
import Combine


@main
struct VoiceMateApp: App {
  
      @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
      @AppStorage("appOpenCount") private var appOpenCount = 0   // Count app opens

      var body: some Scene {
          WindowGroup {
              Group {
                  if hasCompletedOnboarding {
                      ContentView()
                         // .environmentObject(manager)
                          .preferredColorScheme(.light)
                  } else {
                      OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                          .preferredColorScheme(.light)
                  }
              }
              // ✅ Correct place to run app launch logic
              .onAppear {
                  onAppLaunch()
              }
          }
      }

      // MARK: - App Launch Logic
      
      private func onAppLaunch() {
          appOpenCount += 1
          print("App has been opened \(appOpenCount) times")

          // ⭐️ Ask for rating on second open
          if appOpenCount == 2 {
              DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                  requestReview()
              }
          }
      }

      // MARK: - Request Rating
      
      private func requestReview() {
          guard let scene =
                  UIApplication.shared.connectedScenes.first as? UIWindowScene else {
              return
          }
          
          SKStoreReviewController.requestReview(in: scene)
          print("Rating request triggered")
      }
  }
