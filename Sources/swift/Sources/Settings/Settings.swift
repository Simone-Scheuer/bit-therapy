import Schwifty
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appConfig: AppConfig

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: .xl) {
                PageTitle(text: Lang.Page.settings)
                VStack(spacing: .xl) {
                    Switches()
                    FixOnScreenPets()
                    ScreensOnOffSettings()
                    BackgroundSettings()
                }
                .frame(when: .any(.macOS, .iPad, .landscape), width: 350)
                .positioned(.leading)
                .padding(.bottom, .xxxxl)
            }
            .padding(.md)
        }
    }
}

private struct Switches: View {
    var body: some View {
        VStack(spacing: .lg) {
            SizeControl()
            SpeedControl()
            AnimationFrequencyControl()
            LaunchAtLoginSwitch()
            LaunchSilentlySwitch()
            GravitySwitch()
            BounceOffOtherPets()
            MenuBarSwitch()
            DesktopInteractionsSwitch()
            FloatOverFullScreenAppsSwitch()
            RandomEventsSwitch()
        }
    }
}

// MARK: - Reset

struct FixOnScreenPets: View {
    var body: some View {
        Button(Lang.PetSelection.fixOnScreenPets) {
            @Inject var onScreen: OnScreenCoordinator
            onScreen.show()
        }
        .buttonStyle(.regular)
        .positioned(.leading)
    }
}

// MARK: - Random Events

private struct RandomEventsSwitch: View {
    @EnvironmentObject var appConfig: AppConfig
    @State var showingDetails = false

    var body: some View {
        Toggle(isOn: $appConfig.randomEvents) {
            HStack {
                Text(Lang.Settings.randomEventsTitle)
                if showingDetails {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .onTapGesture { showingDetails = true }
                }
            }
        }
        .sheet(isPresented: $showingDetails) {
            VStack(alignment: .center, spacing: .xl) {
                Text(Lang.Settings.randomEventsTitle)
                    .font(.largeTitle)
                    .padding(.top)
                Text(Lang.Settings.randomEventsMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                Button(Lang.cancel) { showingDetails = false }
                    .buttonStyle(.text)
            }
            .padding()
            .frame(when: .is(.macOS), width: 400)
        }
        .positioned(.leading)
    }
}

// MARK: - Gravity

struct GravitySwitch: View {
    @EnvironmentObject var appConfig: AppConfig

    var body: some View {
        Toggle(isOn: $appConfig.gravityEnabled) {
            Text(Lang.Settings.gravity)
        }
        .positioned(.leading)
    }
}

// MARK: - Bounce off other pets

struct BounceOffOtherPets: View {
    @EnvironmentObject var appConfig: AppConfig

    var body: some View {
        Toggle(isOn: $appConfig.bounceOffPetsEnabled) {
            Text(Lang.Settings.bounceOffPets)
        }
        .positioned(.leading)
    }
}

// MARK: - Pet Size

struct SizeControl: View {
    @EnvironmentObject var appConfig: AppConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Lang.Settings.size)
                    .textAlign(.leading)
                Spacer()
                Text("\(Int(appConfig.petSize))")
                    .monospacedDigit()
                    .frame(width: 50)
            }
            
            Slider(
                value: $appConfig.petSize,
                in: PetSize.minSize...PetSize.maxSize,
                step: 5
            ) {
                Text(Lang.Settings.size)
            } minimumValueLabel: {
                Text("\(Int(PetSize.minSize))")
                    .font(.caption)
            } maximumValueLabel: {
                Text("\(Int(PetSize.maxSize))")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Pet Speed Multiplier

struct SpeedControl: View {
    @EnvironmentObject var appConfig: AppConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Lang.Settings.speed)
                    .textAlign(.leading)
                Spacer()
                Text("\(Int(appConfig.speedMultiplier * 100))%")
                    .monospacedDigit()
                    .frame(width: 50)
            }
            
            Slider(
                value: $appConfig.speedMultiplier,
                in: 0.25...3,
                step: 0.25
            ) {
                Text(Lang.Settings.speed)
            } minimumValueLabel: {
                Text("25%")
                    .font(.caption)
            } maximumValueLabel: {
                Text("300%")
                    .font(.caption)
            }
        }
    }
}

// MARK: - Animation Frequency

struct AnimationFrequencyControl: View {
    @EnvironmentObject var appConfig: AppConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Animation Frequency")
                    .textAlign(.leading)
                Spacer()
                Text("\(Int(appConfig.animationFrequency * 100))%")
                    .monospacedDigit()
                    .frame(width: 50)
            }
            
            Slider(
                value: $appConfig.animationFrequency,
                in: 0.1...2.0,
                step: 0.1
            ) {
                Text("Animation Frequency")
            } minimumValueLabel: {
                Text("10%")
                    .font(.caption)
            } maximumValueLabel: {
                Text("200%")
                    .font(.caption)
            }
        }
    }
}

struct SettingsSwitch: View {
    let label: String
    let value: Binding<Bool>
    var showHelp: Binding<Bool>?

    var body: some View {
        HStack {
            Text(label)
            if let showHelp {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .onTapGesture { showHelp.wrappedValue = true }
            }
            Spacer()
            Toggle("", isOn: value).toggleStyle(.switch)
        }
    }
}
