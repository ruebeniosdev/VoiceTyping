//
//  VoiceMateApp.swift
//  VoiceMate
//
//  Created by Fenuku Kekeli on 11/4/25.
//

import SwiftUI
import StoreKit
import RevenueCat
import Network
import Combine
import RevenueCatUI

@main
struct VoiceMateApp: App {
    // MARK: - AppStorage Flags
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasRequestedReviewAfterOnboarding") private var hasRequestedReviewAfterOnboarding = false

    // MARK: - Managers
    @StateObject private var onboardingManager = OnboardingManager()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var networkMonitor = NetworkMonitor()

    // MARK: - Init
    init() {
        // Force Light Mode globally for UIKit components
        UIView.appearance().overrideUserInterfaceStyle = .light
    }

    // MARK: - Main Scene
    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootView()
                        .environmentObject(subscriptionManager)
                        .environmentObject(networkMonitor)
                        .environmentObject(onboardingManager)
                        .onAppear {
                            askForReviewIfNeeded()
                        }
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .environmentObject(onboardingManager)
                        .environmentObject(subscriptionManager)

                }
            }
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Request Review After Onboarding
    private func askForReviewIfNeeded() {
        guard hasCompletedOnboarding, !hasRequestedReviewAfterOnboarding else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: scene)
                hasRequestedReviewAfterOnboarding = true
                print("✅ Requested App Review after onboarding")
            }
        }
    }
}

// MARK: - ONBOARDING MANAGER
class OnboardingManager: ObservableObject {
    @Published var hasCompletedOnboarding: Bool = false

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

// MARK: - NETWORK MONITOR
class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published var isConnected: Bool = true

    init() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - NO CONNECTION VIEW
struct NoConnectionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🔌 No Internet Connection")
                .font(.title2)
                .bold()
            Text("An internet connection is required to verify your subscription and unlock premium features.")
                .multilineTextAlignment(.center)
                .padding()
            ProgressView("Waiting for connection...")
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - ROOT VIEW
struct RootView: View {
    @AppStorage("showIntroView") private var showIntroView: Bool = true
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @State private var isLoading = true

    var body: some View {
        Group {
            if !networkMonitor.isConnected {
                NoConnectionView()
            } else if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if showIntroView {
                // Replace with your intro view
                SpeechToTextView()
                    .environmentObject(subscriptionManager)

            } else {
                SpeechToTextView()
            }
        }
        .onAppear {
            checkSubscription()
        }
    }

    private func checkSubscription() {
        guard networkMonitor.isConnected else { return }
        isLoading = true
        subscriptionManager.checkSubscriptionStatus { _ in
            isLoading = false
        }
    }
}

// MARK: - SUBSCRIPTION MANAGER (RevenueCat)
class SubscriptionManager: NSObject, ObservableObject {
    @Published var isSubscribed: Bool = false
    private let entitlementID = "pro" // Must match your RevenueCat Entitlement ID

    override init() {
        super.init()
        Purchases.configure(withAPIKey: "appl_oIUfSPbFQKEQHZbxAtRhiffNBTC")
        Purchases.shared.delegate = self
        checkSubscriptionStatus()
    }

    func checkSubscriptionStatus(completion: ((Bool) -> Void)? = nil) {
        Purchases.shared.getCustomerInfo { [weak self] info, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Subscription check error: \(error.localizedDescription)")
                    completion?(false)
                    return
                }

                let active = info?.entitlements[self?.entitlementID ?? ""]?.isActive == true
                self?.isSubscribed = active
                print("🔔 Subscription status: \(active ? "Active" : "Inactive")")
                completion?(active)
            }
        }
    }
}

// MARK: - REVENUECAT DELEGATE
extension SubscriptionManager: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        DispatchQueue.main.async {
            let active = customerInfo.entitlements[self.entitlementID]?.isActive == true
            self.isSubscribed = active
            print("🔄 Subscription updated: \(active ? "Subscribed" : "Not subscribed")")
        }
    }
}

