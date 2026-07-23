import SwiftUI

struct ContentView: View {
    @StateObject private var vm = TripViewModel()
    @AppStorage("advisoryAcknowledged") private var advisoryAcknowledged = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Tagline banner.
                    HStack(spacing: 10) {
                        Text("☀️").font(.title3)
                        Text("We'll route you around severe weather, not just around traffic.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                    routeCard
                    stopsCard
                    departureCard
                    preferencesCard

                    if let error = vm.errorMessage {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "car.side.and.exclamationmark")
                                .foregroundStyle(.red).font(.title3)
                            Text(error)
                                .font(.subheadline).foregroundStyle(.primary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        Task { await vm.runPlan() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right")
                            Text("Plan Route").bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isLoading)
                }
                .padding()
            }
            .navigationTitle("Plan a Trip")
            .scrollContentBackground(.hidden)
            .background(ScreenGradient())
            .sheet(isPresented: .constant(!advisoryAcknowledged)) {
                AdvisoryView(acknowledged: $advisoryAcknowledged)
            }
            .overlay {
                if vm.isLoading {
                    PlanningLoadingView()
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { vm.plan != nil && !vm.isLoading },
                set: { if !$0 { vm.plan = nil } }
            )) {
                if let plan = vm.plan {
                    ResultsView(plan: plan,
                                originName: vm.originName,
                                destName: vm.destName)
                }
            }
        }
    }

    // MARK: - Cards

    @State private var newStopName = ""

    private var stopsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STOPS ALONG THE WAY").font(.caption).bold().foregroundStyle(.secondary)
            VStack(spacing: 0) {
                // Existing custom stops, each removable.
                ForEach(vm.customStops) { stop in
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.orange)
                        Text(stop.name).font(.subheadline)
                        Spacer()
                        Button {
                            vm.removeCustomStop(stop)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    Divider()
                }

                // Add-a-stop field.
                AddressField(label: "Add a stop", iconColor: .orange,
                             displayName: $newStopName) { coord, name in
                    vm.addCustomStop(name: name, coordinate: coord)
                    newStopName = ""
                }
            }
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ROUTE").font(.caption).bold().foregroundStyle(.secondary)
            VStack(spacing: 0) {
                AddressField(label: "Origin", iconColor: .green,
                             displayName: $vm.originName) { coord, name in
                    vm.originCoord = coord; vm.originName = name
                }
                Divider().padding(.leading, 24)
                AddressField(label: "Destination", iconColor: .red,
                             displayName: $vm.destName) { coord, name in
                    vm.destCoord = coord; vm.destName = name
                }
            }
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var departureCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEPARTURE").font(.caption).bold().foregroundStyle(.secondary)
            DatePicker("Depart at", selection: $vm.departureDate)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PREFERENCES").font(.caption).bold().foregroundStyle(.secondary)
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("⛽ Fuel range")
                        Spacer()
                        Text("\(Int(vm.fuelRange)) mi").foregroundStyle(.secondary)
                    }
                    Slider(value: $vm.fuelRange, in: 150...500, step: 10)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("☕ Break every")
                        Spacer()
                        Text(breakLabel).foregroundStyle(.secondary)
                    }
                    Slider(value: $vm.breakEvery, in: 60...240, step: 15)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var breakLabel: String {
        let hrs = vm.breakEvery / 60
        return String(format: "%.1f hr", hrs)
    }
}

#Preview {
    ContentView()
}
